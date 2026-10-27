import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:dartssh2/dartssh2.dart';
import '../models/alert_entry.dart';
import '../models/app_entry.dart';
import '../models/cron_entry.dart';
import '../models/server_connection.dart';
import 'ssh_key_loader.dart';

class AgentInstallResult {
  final bool success;
  final String log;
  const AgentInstallResult(this.success, this.log);
}

/// Installs a tiny Python metrics agent on the remote host over SSH,
/// then verifies GET http://host:9108/metrics returns JSON.
class AgentService {
  static const int agentPort = 9108;

  /// The agent: stdlib-only Python, exposes {"cpu":0-1,"ram":0-1,"disk":0-1,"uptime_days":n}
  static const String agentScript = r'''
import json, os, time
from http.server import BaseHTTPRequestHandler, HTTPServer

def read_cpu():
    try:
        with open('/proc/stat') as f:
            p = f.readline().split()[1:]
        vals = list(map(int, p[:8]))
        idle1, total1 = vals[3], sum(vals)
        time.sleep(0.5)
        with open('/proc/stat') as f:
            p = f.readline().split()[1:]
        vals = list(map(int, p[:8]))
        idle2, total2 = vals[3], sum(vals)
        d_idle, d_total = idle2 - idle1, total2 - total1
        if d_total == 0: return 0.0
        return max(0.0, min(1.0, 1.0 - d_idle / d_total))
    except Exception:
        try: return min(1.0, os.getloadavg()[0])
        except Exception: return 0.0

def read_ram():
    try:
        info = {}
        with open('/proc/meminfo') as f:
            for line in f:
                k, v = line.split(':')
                info[k.strip()] = int(v.strip().split()[0])
        total, avail = info.get('MemTotal', 1), info.get('MemAvailable', info.get('MemFree', 0))
        return max(0.0, min(1.0, 1.0 - avail / total))
    except Exception: return 0.0

def read_disk():
    try:
        st = os.statvfs('/')
        total, free = st.f_blocks * st.f_frsize, st.f_bavail * st.f_frsize
        if total == 0: return 0.0
        return max(0.0, min(1.0, 1.0 - free / total))
    except Exception: return 0.0

def read_uptime_days():
    try:
        with open('/proc/uptime') as f:
            return int(float(f.read().split()[0]) // 86400)
    except Exception: return 0

class H(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path != '/metrics':
            self.send_response(404); self.end_headers(); return
        body = json.dumps({'cpu': round(read_cpu(), 3), 'ram': round(read_ram(), 3),
                           'disk': round(read_disk(), 3), 'uptime_days': read_uptime_days()}).encode()
        self.send_response(200)
        self.send_header('Content-Type', 'application/json')
        self.send_header('Content-Length', str(len(body)))
        self.end_headers(); self.wfile.write(body)
    def log_message(self, *a): pass

HTTPServer(('0.0.0.0', 9108), H).serve_forever()
''';

  static const String serviceUnit = '''
[Unit]
Description=MyControlPanel metrics agent
After=network.target
[Service]
ExecStart=/usr/bin/python3 /opt/mcp-agent/agent.py
Restart=always
RestartSec=5
[Install]
WantedBy=multi-user.target
''';

  /// One-click install over SSH. Supports password AND key auth.
  /// [keyPassphrase] unlocks encrypted private keys (prompted in UI first).
  /// Returns 'SSH_KEY_AUTH' only when the key can't be loaded at all —
  /// caller should then fall back to the guided manual install.
  Future<AgentInstallResult> install(
    ServerConnection s,
    void Function(String line) onLog, {
    String? keyPassphrase,
  }) async {
    final logs = <String>[];
    void log(String m) { logs.add(m); onLog(m); }

    // Auth: password OR saved key (path or content)
    List<SSHKeyPair>? keyPairs;
    String? Function()? passwordCb;
    if (s.authMethod == AuthMethod.password) {
      passwordCb = () => s.credential;
    } else {
      log('Resolving saved key…');
      final loaded = await SshKeyLoader.load(s.credential, passphrase: keyPassphrase);
      if (loaded.keys == null) {
        if (loaded.needsPassphrase && keyPassphrase == null) {
          return const AgentInstallResult(false, 'SSH_KEY_NEEDS_PASSPHRASE');
        }
        if (loaded.needsPassphrase) {
          return const AgentInstallResult(false, 'SSH_KEY_BAD_PASSPHRASE');
        }
        log('Key failed: ${loaded.error}');
        return const AgentInstallResult(false, 'SSH_KEY_AUTH');
      }
      keyPairs = loaded.keys;
      log('Key loaded (${keyPairs!.length} identit${keyPairs!.length == 1 ? 'y' : 'ies'}).');
      if (loaded.detected.isNotEmpty) log('Key type: ${loaded.detected}.');
    }
    SSHClient? client;
    try {
      log('Connecting ${s.username}@${s.host}:${s.port} ...');
      final socket = await SSHSocket.connect(s.host, s.port,
          timeout: const Duration(seconds: 10));
      client = SSHClient(socket,
          username: s.username,
          onPasswordRequest: passwordCb,
          identities: keyPairs ?? const []);
      await client.authenticated.timeout(const Duration(seconds: 20));
      log('SSH authenticated.');

      // Every command gets a timeout AND non-interactive sudo: a password
      // prompt would otherwise hang forever with zero feedback.
      Future<String> run(String cmd, {Duration timeout = const Duration(seconds: 45)}) async {
        log('\$ $cmd');
        final session = await client!.execute(cmd);
        final out = await session.stdout.cast<List<int>>().transform(utf8.decoder).join().timeout(timeout);
        final err = await session.stderr.cast<List<int>>().transform(utf8.decoder).join().timeout(const Duration(seconds: 5));
        final code = session.exitCode;
        if (out.trim().isNotEmpty) log(out.trim().split('\n').take(4).join('\n'));
        if (code != 0) throw Exception('exit $code: ${(err + out).trim().split('\n').first}');
        return out;
      }

      await run('python3 --version');
      // Fail fast when passwordless sudo is missing — never hang on a prompt.
      final sudoCheck = await run('sudo -n true 2>/dev/null && echo SUDO_OK || echo SUDO_NEED_PASS');
      if (!sudoCheck.contains('SUDO_OK')) {
        throw Exception(
            'Passwordless sudo is not enabled for "${s.username}". One-click install needs it.\n'
            'Fix on the server (as root): echo "${s.username} ALL=(ALL) NOPASSWD:ALL" | sudo tee /etc/sudoers.d/${s.username}\n'
            'Or use the manual install, where you type the sudo password yourself.');
      }
      log('Passwordless sudo confirmed.');
      await run('sudo -n mkdir -p /opt/mcp-agent && sudo -n chmod 755 /opt/mcp-agent');
      // upload agent.py via stdin
      final upload = await client.execute(
          "sudo -n tee /opt/mcp-agent/agent.py > /dev/null && sudo -n chmod 644 /opt/mcp-agent/agent.py && echo UPLOADED");
      upload.stdin.add(utf8.encode(agentScript));
      await upload.stdin.close().timeout(const Duration(seconds: 30));
      final upOut = await upload.stdout.cast<List<int>>().transform(utf8.decoder).join().timeout(const Duration(seconds: 30));
      if (!upOut.contains('UPLOADED')) throw Exception('agent upload failed');
      log('Agent script uploaded.');
      // systemd unit
      final unit = await client.execute(
          'sudo -n tee /etc/systemd/system/mcp-agent.service > /dev/null && echo UNIT_OK');
      unit.stdin.add(utf8.encode(serviceUnit));
      await unit.stdin.close().timeout(const Duration(seconds: 30));
      await unit.done.timeout(const Duration(seconds: 30));
      log('systemd unit written.');
      await run('sudo -n systemctl daemon-reload && sudo -n systemctl enable --now mcp-agent && sleep 2 && sudo -n systemctl is-active mcp-agent');
      log('Service active.');
      await run('ss -ltn 2>/dev/null | grep 9108 || netstat -ltn 2>/dev/null | grep 9108 || echo PORT_CHECK_SKIP');
      // Configure host firewall for the agent port (best-effort — ignored if ufw absent)
      try {
        await run('sudo -n ufw allow $agentPort/tcp 2>/dev/null || sudo -n firewall-cmd --permanent --add-port=$agentPort/tcp --quiet 2>/dev/null && sudo -n firewall-cmd --reload --quiet 2>/dev/null; echo FW_OK');
        log('Firewall opened for TCP $agentPort (or no local firewall present).');
      } catch (_) {
        log('No local firewall rule applied (non-fatal — cloud security groups may still apply).');
      }
      client.close();

      // verify from this machine
      log('Verifying http://${s.host}:$agentPort/metrics ...');
      final m = await fetch(s.host);
      if (m == null) throw Exception('agent installed but /metrics unreachable from here (firewall? open TCP $agentPort)');
      log('Verified: cpu=${m['cpu']} ram=${m['ram']} disk=${m['disk']} uptime=${m['uptime_days']}d');
      return AgentInstallResult(true, logs.join('\n'));
    } catch (e) {
      try { client?.close(); } catch (_) {}
      log('ERROR: $e');
      return AgentInstallResult(false, logs.join('\n'));
    }
  }

  /// Self-contained manual install: paste into the server's own SSH terminal.
  /// Base64-embeds agent.py + systemd unit, no network download needed.
  static String manualInstallScript() {
    final py = base64.encode(utf8.encode(agentScript));
    final unit = base64.encode(utf8.encode(serviceUnit));
    return 'sudo mkdir -p /opt/mcp-agent && echo $py | base64 -d | sudo tee /opt/mcp-agent/agent.py > /dev/null && echo $unit | base64 -d | sudo tee /etc/systemd/system/mcp-agent.service > /dev/null && sudo systemctl daemon-reload && sudo systemctl enable --now mcp-agent && sleep 2 && sudo systemctl is-active mcp-agent && curl -s http://127.0.0.1:9108/metrics && echo && echo AGENT_OK';
  }

  static List<String> manualSteps(ServerConnection s) => [
    '1. Open a terminal on THIS machine (or any machine with SSH access).',
    '2. SSH in with your key:  ssh -i <your-key.pem> -p ${s.port} ${s.username}@${s.host}',
    '3. Paste the install command below (single line) and press Enter.',
    '4. You should see AGENT_OK + JSON like {"cpu":0.1,...}.',
    '5. Ensure TCP ${AgentService.agentPort} is open to this machine, then tap VERIFY below.',
  ];

  /// Discover cronjobs on a server over SSH: user crontab + /etc/crontab + /etc/cron.d/*.
  /// [keyPassphrase] unlocks encrypted keys. Returns parsed entries (may be empty).
  Future<List<CronEntry>> fetchCrons(ServerConnection s, {String? keyPassphrase}) async {
    List<SSHKeyPair>? keys;
    String? Function()? passwordCb;
    if (s.authMethod == AuthMethod.password) {
      passwordCb = () => s.credential;
    } else {
      final loaded = await SshKeyLoader.load(s.credential, passphrase: keyPassphrase);
      if (loaded.keys == null) throw Exception(loaded.error ?? 'key load failed');
      keys = loaded.keys;
    }
    SSHClient? client;
    try {
      final socket = await SSHSocket.connect(s.host, s.port, timeout: const Duration(seconds: 10));
      client = SSHClient(socket, username: s.username, onPasswordRequest: passwordCb, identities: keys ?? const []);
      await client.authenticated.timeout(const Duration(seconds: 15));

      Future<String> run(String cmd) async {
        final session = await client!.execute(cmd);
        final out = await session.stdout.cast<List<int>>().transform(utf8.decoder).join().timeout(const Duration(seconds: 15));
        return out;
      }

      final entries = <CronEntry>[];
      // user crontab of the SSH user
      try {
        final user = await run('crontab -l 2>/dev/null || echo NO_CRONTAB');
        if (!user.contains('NO_CRONTAB')) {
          entries.addAll(CronEntry.parse(output: user, source: 'crontab', hasUserField: false, serverId: s.id, serverName: s.name));
        }
      } catch (_) {}
      // system crontab
      try {
        final sys = await run('cat /etc/crontab 2>/dev/null || echo NO_SYS');
        if (!sys.contains('NO_SYS')) {
          entries.addAll(CronEntry.parse(output: sys, source: '/etc/crontab', hasUserField: true, serverId: s.id, serverName: s.name));
        }
      } catch (_) {}
      // /etc/cron.d/*
      try {
        final d = await run(r'for f in /etc/cron.d/*; do [ -f "$f" ] && echo "###FILE:$f" && cat "$f" 2>/dev/null; done; echo DONE');
        var current = '/etc/cron.d';
        final buf = StringBuffer();
        void flush() {
          if (buf.isNotEmpty) {
            entries.addAll(CronEntry.parse(output: buf.toString(), source: current, hasUserField: true, serverId: s.id, serverName: s.name));
            buf.clear();
          }
        }
        for (final line in d.split('\n')) {
          if (line.startsWith('###FILE:')) {
            flush();
            current = line.substring(8).trim();
          } else if (line.trim() == 'DONE') {
            flush();
          } else {
            buf.writeln(line);
          }
        }
      } catch (_) {}
      client.close();
      return entries;
    } catch (e) {
      try { client?.close(); } catch (_) {}
      rethrow;
    }
  }

  /// Discover apps on a server over SSH: running systemd services,
  /// docker containers, and listening TCP ports.
  Future<List<AppEntry>> fetchApps(ServerConnection s, {String? keyPassphrase}) async {
    List<SSHKeyPair>? keys;
    String? Function()? passwordCb;
    if (s.authMethod == AuthMethod.password) {
      passwordCb = () => s.credential;
    } else {
      final loaded = await SshKeyLoader.load(s.credential, passphrase: keyPassphrase);
      if (loaded.keys == null) throw Exception(loaded.error ?? 'key load failed');
      keys = loaded.keys;
    }
    SSHClient? client;
    try {
      final socket = await SSHSocket.connect(s.host, s.port, timeout: const Duration(seconds: 10));
      client = SSHClient(socket, username: s.username, onPasswordRequest: passwordCb, identities: keys ?? const []);
      await client.authenticated.timeout(const Duration(seconds: 15));

      Future<String> run(String cmd) async {
        final session = await client!.execute(cmd);
        final out = await session.stdout.cast<List<int>>().transform(utf8.decoder).join().timeout(const Duration(seconds: 15));
        return out;
      }

      final apps = <AppEntry>[];
      // 1. running systemd services (skip template/infra noise)
      try {
        final units = await run(r"systemctl list-units --type=service --state=running --no-legend --no-pager 2>/dev/null | awk '{print $1}'");
        const noise = {'dbus', 'systemd', 'sshd', 'ssh', 'cron', 'crond', 'rsyslog', 'networkd', 'resolved', 'logind', 'udevd', 'getty', 'serial-getty'};
        for (final line in units.split('\n')) {
          final u = line.trim();
          if (u.isEmpty || !u.endsWith('.service')) continue;
          final name = u.replaceAll('.service', '');
          final base = name.split('@').first;
          if (noise.any((n) => base.startsWith(n))) continue;
          if (apps.any((a) => a.name == name)) continue;
          apps.add(AppEntry(name: name, detail: 'systemd • running', source: 'systemd', serverId: s.id, serverName: s.name));
        }
      } catch (_) {}
      // 2. docker containers
      try {
        final ps = await run('docker ps --format "{{.Names}}|{{.Image}}|{{.Status}}" 2>/dev/null || echo NO_DOCKER');
        if (!ps.contains('NO_DOCKER')) {
          for (final line in ps.split('\n')) {
            final parts = line.split('|');
            if (parts.length < 3 || parts[0].trim().isEmpty) continue;
            apps.add(AppEntry(name: parts[0].trim(), detail: '${parts[1].trim()} • ${parts[2].trim()}', source: 'docker', serverId: s.id, serverName: s.name));
          }
        }
      } catch (_) {}
      // 3. listening TCP ports (catches non-systemd / bare-metal apps)
      try {
        final ss = await run('ss -ltnp 2>/dev/null | tail -n +2 || netstat -ltnp 2>/dev/null | tail -n +2 || echo NO_SS');
        if (!ss.contains('NO_SS')) {
          for (final line in ss.split('\n')) {
            final m = RegExp(r':(\d+)\s').firstMatch(line);
            if (m == null) continue;
            final port = m.group(1)!;
            if ({'22', '9108'}.contains(port)) continue; // ssh + our agent
            if (apps.any((a) => a.detail.contains(':$port'))) continue;
            final proc = RegExp(r'users:\(\("([^"]+)"').firstMatch(line)?.group(1) ?? 'port';
            apps.add(AppEntry(name: proc == 'port' ? 'port-$port' : proc, detail: 'listening :$port', source: 'port', serverId: s.id, serverName: s.name));
          }
        }
      } catch (_) {}
      client.close();
      return apps;
    } catch (e) {
      try { client?.close(); } catch (_) {}
      rethrow;
    }
  }

  /// Harvest alert-worthy signals from a server over SSH:
  /// failed systemd units, high disk usage, recent SSH brute-force,
  /// recent error-rate in logs. Lightweight — a handful of read-only commands.
  Future<List<AlertEntry>> fetchAlerts(ServerConnection s, {String? keyPassphrase}) async {
    List<SSHKeyPair>? keys;
    String? Function()? passwordCb;
    if (s.authMethod == AuthMethod.password) {
      passwordCb = () => s.credential;
    } else {
      final loaded = await SshKeyLoader.load(s.credential, passphrase: keyPassphrase);
      if (loaded.keys == null) throw Exception(loaded.error ?? 'key load failed');
      keys = loaded.keys;
    }
    SSHClient? client;
    try {
      final socket = await SSHSocket.connect(s.host, s.port, timeout: const Duration(seconds: 10));
      client = SSHClient(socket, username: s.username, onPasswordRequest: passwordCb, identities: keys ?? const []);
      await client.authenticated.timeout(const Duration(seconds: 15));

      Future<String> run(String cmd) async {
        final session = await client!.execute(cmd);
        final out = await session.stdout.cast<List<int>>().transform(utf8.decoder).join().timeout(const Duration(seconds: 20));
        return out;
      }

      final alerts = <AlertEntry>[];
      AlertEntry mk(String title, String source, String severity, {String status = 'firing'}) =>
          AlertEntry(title: title, source: source, severity: severity, serverId: s.id, serverName: s.name, status: status);

      // 1. failed systemd units
      try {
        final failed = await run(r"systemctl list-units --type=service --state=failed --no-legend --no-pager 2>/dev/null | awk '{print $1}'");
        for (final line in failed.split('\n')) {
          final u = line.trim();
          if (u.isEmpty || !u.endsWith('.service')) continue;
          alerts.add(mk('Service failed: ${u.replaceAll('.service', '')}', 'systemd • ${s.name}', 'critical'));
        }
      } catch (_) {}
      // 2. disk usage per mount (warn 80+, critical 90+)
      try {
        final df = await run(r"df -h --output=target,pcent 2>/dev/null | tail -n +2");
        for (final line in df.split('\n')) {
          final m = RegExp(r'(\S+)\s+(\d+)%').firstMatch(line.trim());
          if (m == null) continue;
          final pct = int.parse(m.group(2)!);
          if (pct >= 90) {
            alerts.add(mk('Disk ${pct}% full on ${m.group(1)}', 'disk • ${s.name}', 'critical'));
          } else if (pct >= 80) {
            alerts.add(mk('Disk ${pct}% full on ${m.group(1)}', 'disk • ${s.name}', 'warning'));
          }
        }
      } catch (_) {}
      // 3. SSH brute force in last 24h (journal or auth.log)
      try {
        final auth = await run(r"sudo -n journalctl -u ssh -u sshd --since '24 hours ago' --no-pager 2>/dev/null | grep -ci 'Failed password' || grep -c 'Failed password' /var/log/auth.log 2>/dev/null || echo 0");
        final n = int.tryParse(auth.trim().split('\n').last) ?? 0;
        if (n >= 20) {
          alerts.add(mk('$n failed SSH logins in 24h (possible brute force)', 'auth • ${s.name}', 'critical'));
        } else if (n >= 5) {
          alerts.add(mk('$n failed SSH logins in 24h', 'auth • ${s.name}', 'warning'));
        }
      } catch (_) {}
      // 4. load average vs CPU count
      try {
        final la = await run(r"cat /proc/loadavg | awk '{print $1}' && nproc");
        final parts = la.trim().split('\n');
        if (parts.length == 2) {
          final load = double.tryParse(parts[0]) ?? 0;
          final cpus = int.tryParse(parts[1]) ?? 1;
          if (load > cpus * 2) {
            alerts.add(mk('Load average ${parts[0]} on $cpus CPUs (overloaded)', 'load • ${s.name}', 'critical'));
          } else if (load > cpus) {
            alerts.add(mk('Load average ${parts[0]} on $cpus CPUs (high)', 'load • ${s.name}', 'warning'));
          }
        }
      } catch (_) {}
      // 5. recent kernel errors (oom, io)
      try {
        final kern = await run(r"dmesg --level=err,warn --since '24 hours ago' 2>/dev/null | tail -5 || dmesg 2>/dev/null | grep -iE 'oom|I/O error|EXT4-fs error' | tail -5");
        final lines = kern.trim().split('\n').where((l) => l.trim().isNotEmpty).toList();
        if (lines.isNotEmpty) {
          final oom = lines.any((l) => l.toLowerCase().contains('out of memory') || l.contains('oom'));
          alerts.add(mk(oom ? 'Out-of-memory killer fired in last 24h' : '${lines.length} kernel warnings in last 24h', 'kernel • ${s.name}', oom ? 'critical' : 'warning'));
        }
      } catch (_) {}
      // 6. rebooted recently (uptime < 1h may indicate crash)
      try {
        final up = await run(r"cat /proc/uptime | awk '{print int($1)}'");
        final secs = int.tryParse(up.trim()) ?? -1;
        if (secs >= 0 && secs < 3600) {
          alerts.add(mk('Server rebooted ${secs ~/ 60}m ago — unexpected restart?', 'uptime • ${s.name}', 'warning'));
        }
      } catch (_) {}
      client.close();
      return alerts;
    } catch (e) {
      try { client?.close(); } catch (_) {}
      rethrow;
    }
  }

  /// Run one arbitrary command over SSH, return combined stdout (trimmed).
  /// Used by AI tools (guarded by an allowlist in ai_tools.dart).
  Future<String> runCommand(ServerConnection s, String cmd, {String? keyPassphrase}) async {
    List<SSHKeyPair>? keys;
    String? Function()? passwordCb;
    if (s.authMethod == AuthMethod.password) {
      passwordCb = () => s.credential;
    } else {
      final loaded = await SshKeyLoader.load(s.credential, passphrase: keyPassphrase);
      if (loaded.keys == null) {
        if (loaded.needsPassphrase) {
          throw Exception('SSH key is encrypted — re-run from the Terminal tab and enter the passphrase there.');
        }
        throw Exception(loaded.error ?? 'key load failed');
      }
      keys = loaded.keys;
    }
    SSHClient? client;
    try {
      final socket = await SSHSocket.connect(s.host, s.port, timeout: const Duration(seconds: 10));
      client = SSHClient(socket, username: s.username, onPasswordRequest: passwordCb, identities: keys ?? const []);
      await client.authenticated.timeout(const Duration(seconds: 15));
      final session = await client.execute(cmd);
      final out = await session.stdout.cast<List<int>>().transform(utf8.decoder).join().timeout(const Duration(seconds: 30));
      final err = await session.stderr.cast<List<int>>().transform(utf8.decoder).join().timeout(const Duration(seconds: 5));
      final code = session.exitCode;
      client.close();
      final text = (out + (err.isNotEmpty ? '\n[stderr] $err' : '')).trim();
      return '[exit $code]\n$text';
    } catch (e) {
      try { client?.close(); } catch (_) {}
      rethrow;
    }
  }

  /// Tail logs for one cronjob: greps journal + syslog for the command's
  /// program name (first token basename), newest first, capped at 200 lines.
  Future<String> fetchCronLogs(ServerConnection s, CronEntry entry, {String? keyPassphrase}) async {
    List<SSHKeyPair>? keys;
    String? Function()? passwordCb;
    if (s.authMethod == AuthMethod.password) {
      passwordCb = () => s.credential;
    } else {
      final loaded = await SshKeyLoader.load(s.credential, passphrase: keyPassphrase);
      if (loaded.keys == null) {
        if (loaded.needsPassphrase) throw Exception('SSH key is encrypted — enter the passphrase in the Terminal tab first.');
        throw Exception(loaded.error ?? 'key load failed');
      }
      keys = loaded.keys;
    }
    SSHClient? client;
    try {
      final socket = await SSHSocket.connect(s.host, s.port, timeout: const Duration(seconds: 10));
      client = SSHClient(socket, username: s.username, onPasswordRequest: passwordCb, identities: keys ?? const []);
      await client.authenticated.timeout(const Duration(seconds: 15));

      Future<String> run(String cmd) async {
        final session = await client!.execute(cmd);
        final out = await session.stdout.cast<List<int>>().transform(utf8.decoder).join().timeout(const Duration(seconds: 20));
        return out;
      }

      final firstToken = entry.command.trim().split(RegExp(r'\s+')).firstWhere((t) => t.isNotEmpty, orElse: () => '');
      final prog = firstToken.split('/').last.replaceAll(RegExp(r'[^A-Za-z0-9@._:\-]'), '');
      if (prog.isEmpty) return 'No searchable program name in: ${entry.command}';
      final q = "'$prog'";
      final out = await run(
          "(journalctl --no-pager --since '7 days ago' 2>/dev/null | grep -i $q | tail -100; "
          "echo '--- syslog ---'; "
          "(sudo -n grep -hi $q /var/log/syslog /var/log/messages /var/log/cron* 2>/dev/null || grep -hi $q /var/log/syslog /var/log/messages /var/log/cron* 2>/dev/null) | tail -100)");
      client.close();
      final text = out.trim();
      return text.isEmpty ? 'No log lines mentioning "$prog" in the last 7 days.' : text;
    } catch (e) {
      try { client?.close(); } catch (_) {}
      rethrow;
    }
  }

  /// Rewrite one crontab line in place. System files use sudo tee.
  /// [entry.rawLine] must match exactly one line in the source.
  Future<void> updateCron(ServerConnection s, CronEntry entry, String newSchedule, String newCommand, {String? keyPassphrase}) async {
    List<SSHKeyPair>? keys;
    String? Function()? passwordCb;
    if (s.authMethod == AuthMethod.password) {
      passwordCb = () => s.credential;
    } else {
      final loaded = await SshKeyLoader.load(s.credential, passphrase: keyPassphrase);
      if (loaded.keys == null) {
        if (loaded.needsPassphrase) throw Exception('SSH key is encrypted — enter the passphrase in the Terminal tab first.');
        throw Exception(loaded.error ?? 'key load failed');
      }
      keys = loaded.keys;
    }
    newSchedule = newSchedule.trim();
    newCommand = newCommand.trim();
    if (newSchedule.isEmpty || newCommand.isEmpty) throw Exception('Schedule and command are required.');
    if (entry.rawLine.isEmpty) throw Exception('Cannot safely edit: original line unknown. Rescan and retry.');
    SSHClient? client;
    try {
      final socket = await SSHSocket.connect(s.host, s.port, timeout: const Duration(seconds: 10));
      client = SSHClient(socket, username: s.username, onPasswordRequest: passwordCb, identities: keys ?? const []);
      await client.authenticated.timeout(const Duration(seconds: 15));

      Future<String> run(String cmd) async {
        final session = await client!.execute(cmd);
        final out = await session.stdout.cast<List<int>>().transform(utf8.decoder).join().timeout(const Duration(seconds: 15));
        final err = await session.stderr.cast<List<int>>().transform(utf8.decoder).join().timeout(const Duration(seconds: 5));
        if (session.exitCode != 0) throw Exception('exit ${session.exitCode}: ${(err + out).trim().split('\n').first}');
        return out;
      }

      // Preserve the user field for system crontabs (/etc/crontab, /etc/cron.d/*).
      String prefix = '';
      if (entry.source != 'crontab') {
        final parts = entry.rawLine.trim().split(RegExp(r'\s+'));
        if (entry.rawLine.trim().startsWith('@')) {
          if (parts.length >= 3) prefix = '${parts[1]} ';
        } else if (parts.length >= 6) {
          prefix = '${parts[5]} ';
        }
      }
      final newLine = '$newSchedule $prefix$newCommand';

      if (entry.source == 'crontab') {
        final current = await run('crontab -l');
        final lines = current.split('\n');
        var replaced = 0;
        final updated = lines.map((l) {
          if (l.trim() == entry.rawLine.trim()) {
            replaced++;
            return newLine;
          }
          return l;
        }).toList();
        if (replaced != 1) throw Exception('Expected exactly 1 matching line, found $replaced — crontab changed underneath. Rescan and retry.');
        final session = await client.execute('crontab -');
        session.stdin.add(utf8.encode('${updated.join('\n')}\n'));
        await session.stdin.close();
        await session.done;
        if (session.exitCode != 0) throw Exception('crontab install failed (exit ${session.exitCode})');
      } else {
        final path = entry.source;
        if (!path.startsWith('/etc/crontab') && !path.startsWith('/etc/cron.d/')) {
          throw Exception('Refusing to edit unexpected path: $path');
        }
        final check = await run("grep -cFx '${entry.rawLine.trim().replaceAll("'", "'\\''")}' $path || echo 0");
        if (check.trim().split('\n').last.trim() != '1') {
          throw Exception('Expected exactly 1 matching line in $path — file changed underneath. Rescan and retry.');
        }
        await run("sudo cp -p $path $path.mcp-bak && "
            "grep -vFx '${entry.rawLine.trim().replaceAll("'", "'\\''")}' $path | sudo tee $path > /dev/null && "
            "echo '$newLine' | sudo tee -a $path > /dev/null && "
            "echo SAVED");
      }
      client.close();
    } catch (e) {
      try { client?.close(); } catch (_) {}
      rethrow;
    }
  }

  /// GET http://host:9108/metrics -> {cpu,ram,disk,uptime_days} or null
  Future<Map<String, dynamic>?> fetch(String host) async {
    try {
      final hc = HttpClient()..connectionTimeout = const Duration(seconds: 5);
      final req = await hc.get(host, agentPort, '/metrics');
      final resp = await req.close().timeout(const Duration(seconds: 6));
      if (resp.statusCode != 200) return null;
      final body = await resp.transform(utf8.decoder).join();
      hc.close();
      return jsonDecode(body) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }
}
