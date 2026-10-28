import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:dartssh2/dartssh2.dart';
import '../models/alert_entry.dart';
import '../models/app_entry.dart';
import '../models/app_proc.dart';
import '../models/cron_entry.dart';
import '../models/server_connection.dart';
import 'agent_protocol.dart';
import 'cron_run_tracker.dart';
import 'secure_store.dart';
import 'ssh_host_keys.dart';
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

  /// Agent v5: stdlib-only Python.
  /// /metrics -> {"cpu","ram","disk","uptime_days","version":5,"load1":...}
  /// /procstats -> {"version":5,"top":[{"pid","name","cpu","mem_mb"}], "ports":{"3000":{"listening":true,"established":2}}}
  /// /sysstats (v3+) -> {"version":5,"load1","load5","load15",
  ///   "mem":{"total_mb","avail_mb","swap_total_mb","swap_free_mb"},
  ///   "gpu":{"present","count"},"agent_uptime_s":...,
  ///   "nproc":...,"boot_epoch_s":...}
  /// /health (v4+) -> {"status":"ok","version":5,"agent_uptime_s":...}
  /// /cronruns (v5+) -> {"version":5,"runs":[{"at","name","exit","dur_s"}]}
  ///   (agent-side run log; missing log file = empty list)
  /// Token auth (v4+): when MCP_AGENT_TOKEN is set (via /etc/mcp-agent.env),
  /// every endpoint requires `X-MCP-Agent-Token`; mismatch -> 401 JSON.
  /// Unset = open (backwards compatible with v2/v3 clients).
  /// APM-lite: top processes by CPU + per-port established connections.
  /// Sysstats adds load average, memory detail, GPU presence, agent uptime,
  /// CPU count and boot epoch for capacity planning (e.g. sizing on-host
  /// model serving) and reboot detection without an SSH round-trip.
  /// Cronruns (v5+) surfaces the agent-side cron run log for Zara's
  /// last-run tracker; older agents answer 404 and the app falls back to
  /// its local cache.
  /// Inference stats themselves live app-side in LlmReliability and are
  /// correlated by host — the agent never fabricates inference counters.
  static const int agentVersion = 5;
  static const String agentScript = r'''
import json, os, time
import hmac
import subprocess
from http.server import BaseHTTPRequestHandler, HTTPServer
from urllib.parse import urlsplit, parse_qs

AGENT_VERSION = 5
START_TIME = time.time()
# Optional shared secret. Set via EnvironmentFile /etc/mcp-agent.env
# (MCP_AGENT_TOKEN=...). Empty = open (v2/v3-compatible).
AGENT_TOKEN = os.environ.get('MCP_AGENT_TOKEN', '')
TOKEN_HEADER = 'X-MCP-Agent-Token'
# /logs sources. journald first, plain syslog files as fallback —
# never arbitrary paths, never shell.
ALLOWED_LOG_SOURCES = ('journal', 'syslog')
# Cron run log (v5+): jobs append one line per run, e.g.
#   echo "$(date +%s) backup 0 12" >> /var/log/mcp-cronruns.log
# fields: <epoch_s> <name> <exit> [dur_s]. Missing file = no data (200 []).
CRONRUNS_LOG = '/var/log/mcp-cronruns.log'

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

def read_loadavg():
    try:
        with open('/proc/loadavg') as f:
            p = f.read().split()
        return [float(p[0]), float(p[1]), float(p[2])]
    except Exception:
        return [0.0, 0.0, 0.0]

def read_mem_detail():
    try:
        info = {}
        with open('/proc/meminfo') as f:
            for line in f:
                k, v = line.split(':')
                info[k.strip()] = int(v.strip().split()[0])
        return {'total_mb': info.get('MemTotal', 0) // 1024,
                'avail_mb': info.get('MemAvailable', info.get('MemFree', 0)) // 1024,
                'swap_total_mb': info.get('SwapTotal', 0) // 1024,
                'swap_free_mb': info.get('SwapFree', 0) // 1024}
    except Exception:
        return {'total_mb': 0, 'avail_mb': 0, 'swap_total_mb': 0, 'swap_free_mb': 0}

def read_gpu():
    try:
        import glob
        devs = glob.glob('/dev/nvidia[0-9]*')
        return {'present': len(devs) > 0, 'count': len(devs)}
    except Exception:
        return {'present': False, 'count': 0}

def read_nproc():
    try:
        n = os.cpu_count()
        return n if n and n > 0 else 1
    except Exception:
        return 1

def read_boot_epoch_s():
    try:
        with open('/proc/uptime') as f:
            up = float(f.read().split()[0])
        return int(time.time() - up)
    except Exception:
        return 0

def _run_tail(argv, timeout=5):
    try:
        p = subprocess.run(argv, capture_output=True, text=True,
                           timeout=timeout)
        if p.returncode == 0:
            return p.stdout.split('\n')
    except Exception:
        pass
    return []

def read_logs(source='journal', lines=100):
    try:
        n = max(20, min(500, int(lines)))
    except Exception:
        n = 100
    if source not in ALLOWED_LOG_SOURCES:
        source = 'journal'
    rows = []
    if source == 'journal':
        rows = _run_tail(['journalctl', '--no-pager', '-n', str(n)])
    if not rows:
        for path in ('/var/log/syslog', '/var/log/messages'):
            try:
                with open(path, errors='replace') as f:
                    rows = f.read().split('\n')[-n:]
                if any(r.strip() for r in rows):
                    break
            except Exception:
                continue
    rows = [r for r in rows if r.strip() != '']
    return rows[-n:]

def read_cronruns(limit=50):
    try:
        n = max(1, min(200, int(limit)))
    except Exception:
        n = 50
    try:
        with open(CRONRUNS_LOG, errors='replace') as f:
            content = f.read()
    except Exception:
        return []
    if not content.strip():
        return []
    lines = content.strip().split('\n')[-n:]
    out = []
    for line in lines:
        p = line.split()
        if len(p) < 3:
            continue
        try:
            at, code = int(p[0]), int(p[2])
        except ValueError:
            continue
        dur = None
        if len(p) > 3 and p[3].isdigit():
            dur = int(p[3])
        out.append({'at': at, 'name': p[1][:80], 'exit': code,
                    'dur_s': dur})
    out.reverse()
    return out

def _proc_snapshot():
    procs = {}
    try:
        for pid in os.listdir('/proc'):
            if not pid.isdigit():
                continue
            try:
                with open('/proc/%s/stat' % pid) as f:
                    p = f.read().rsplit(')', 1)[1].split()
                utime, stime = int(p[11]), int(p[12])
                with open('/proc/%s/status' % pid) as f:
                    txt = f.read()
                name, rss = pid, 0
                for line in txt.split('\n'):
                    if line.startswith('Name:'): name = line.split(':', 1)[1].strip()
                    elif line.startswith('VmRSS:'): rss = int(line.split()[1]) // 1024
                procs[int(pid)] = [utime + stime, name, rss]
            except Exception:
                continue
    except Exception:
        pass
    return procs

def read_top_processes(n=12):
    try:
        with open('/proc/stat') as f:
            total1 = sum(map(int, f.readline().split()[1:8]))
        s1 = _proc_snapshot()
        time.sleep(0.5)
        with open('/proc/stat') as f:
            total2 = sum(map(int, f.readline().split()[1:8]))
        s2 = _proc_snapshot()
        dt = max(1, total2 - total1)
        out = []
        for pid, (t1, name, rss) in s1.items():
            if pid in s2:
                cpu = max(0.0, min(1.0, (s2[pid][0] - t1) / dt))
                out.append({'pid': pid, 'name': name, 'cpu': round(cpu, 3), 'mem_mb': s2[pid][2]})
        out.sort(key=lambda e: e['cpu'], reverse=True)
        return out[:n]
    except Exception:
        return []

def read_ports():
    ports = {}
    for path in ('/proc/net/tcp', '/proc/net/tcp6'):
        try:
            with open(path) as f:
                lines = f.read().split('\n')[1:]
            for line in lines:
                p = line.split()
                if len(p) < 4:
                    continue
                try:
                    local_port = int(p[1].split(':')[1], 16)
                    state = p[3]
                except Exception:
                    continue
                e = ports.setdefault(str(local_port), {'listening': False, 'established': 0})
                if state == '0A':
                    e['listening'] = True
                elif state == '01':
                    e['established'] += 1
        except Exception:
            continue
    return ports

class H(BaseHTTPRequestHandler):
    def _send(self, code, obj):
        try:
            body = json.dumps(obj).encode()
        except Exception:
            code, body = 500, b'{"error":"encode_failed"}'
        self.send_response(code)
        self.send_header('Content-Type', 'application/json')
        self.send_header('Content-Length', str(len(body)))
        self.end_headers()
        try:
            self.wfile.write(body)
        except Exception:
            pass

    def _authorized(self):
        if not AGENT_TOKEN:
            return True
        got = self.headers.get(TOKEN_HEADER, '')
        return hmac.compare_digest(got, AGENT_TOKEN)

    def do_GET(self):
        if not self._authorized():
            self._send(401, {'error': 'unauthorized',
                             'hint': 'send ' + TOKEN_HEADER})
            return
        parts = urlsplit(self.path)
        path = parts.path.rstrip('/') or '/'
        qs = parse_qs(parts.query)
        if path == '/metrics':
            body = {'cpu': round(read_cpu(), 3), 'ram': round(read_ram(), 3),
                    'disk': round(read_disk(), 3), 'uptime_days': read_uptime_days(),
                    'load1': round(read_loadavg()[0], 2),
                    'version': AGENT_VERSION}
        elif path == '/procstats':
            body = {'version': AGENT_VERSION, 'top': read_top_processes(),
                    'ports': read_ports()}
        elif path == '/sysstats':
            la = read_loadavg()
            body = {'version': AGENT_VERSION,
                    'load1': round(la[0], 2), 'load5': round(la[1], 2),
                    'load15': round(la[2], 2), 'mem': read_mem_detail(),
                    'gpu': read_gpu(),
                    'agent_uptime_s': int(time.time() - START_TIME),
                    'nproc': read_nproc(), 'boot_epoch_s': read_boot_epoch_s()}
        elif path == '/health':
            body = {'status': 'ok', 'version': AGENT_VERSION,
                    'agent_uptime_s': int(time.time() - START_TIME)}
        elif path == '/logs':
            src = (qs.get('source', ['journal'])[0] or 'journal').strip()
            if src not in ALLOWED_LOG_SOURCES:
                self._send(400, {'error': 'bad_source',
                                 'allowed': list(ALLOWED_LOG_SOURCES)})
                return
            try:
                n = int(qs.get('lines', ['100'])[0])
            except Exception:
                n = 100
            body = {'version': AGENT_VERSION, 'source': src,
                    'lines': read_logs(src, n)}
        elif path == '/cronruns':
            try:
                n = int(qs.get('lines', ['50'])[0])
            except Exception:
                n = 50
            body = {'version': AGENT_VERSION, 'runs': read_cronruns(n)}
        else:
            self._send(404, {'error': 'not_found', 'path': path})
            return
        self._send(200, body)

    def _method_not_allowed(self):
        self._send(405, {'error': 'method_not_allowed',
                         'hint': 'use GET'})

    do_POST = _method_not_allowed
    do_PUT = _method_not_allowed
    do_DELETE = _method_not_allowed
    do_PATCH = _method_not_allowed
    do_HEAD = _method_not_allowed
    do_OPTIONS = _method_not_allowed
    def log_message(self, *a): pass

HTTPServer(('0.0.0.0', 9108), H).serve_forever()
''';

  static const String serviceUnit = '''
[Unit]
Description=MyControlPanel metrics agent
After=network.target
[Service]
ExecStart=/usr/bin/python3 /opt/mcp-agent/agent.py
# Optional shared secret for the v4 agent (X-MCP-Agent-Token).
# Absent file = open agent (v2/v3-compatible). To enforce auth:
#   echo 'MCP_AGENT_TOKEN=<secret>' | sudo tee /etc/mcp-agent.env
#   sudo chmod 600 /etc/mcp-agent.env && sudo systemctl restart mcp-agent
EnvironmentFile=-/etc/mcp-agent.env
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
          onVerifyHostKey: SshHostKeys.verifierFor(s.host, s.port),
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
      // v4 token gate (secure default): mint a per-host secret, deploy it as
      // the unit's EnvironmentFile, and keep the same value in the keychain
      // so polling authenticates. Reinstall = rotation (both sides together).
      final agentToken = newAgentToken();
      final envUp = await client.execute(
          'sudo -n tee /etc/mcp-agent.env > /dev/null && sudo -n chmod 600 /etc/mcp-agent.env && echo TOKEN_OK');
      envUp.stdin.add(utf8.encode('MCP_AGENT_TOKEN=$agentToken\n'));
      await envUp.stdin.close().timeout(const Duration(seconds: 30));
      final envOut = await envUp.stdout.cast<List<int>>().transform(utf8.decoder).join().timeout(const Duration(seconds: 30));
      await envUp.done.timeout(const Duration(seconds: 30));
      if (!envOut.contains('TOKEN_OK')) throw Exception('agent token deploy failed');
      await SecureStore.writeAgentToken(s.id, agentToken);
      log('Agent token provisioned (keychain + host env, mode 600).');
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
      final m = await fetch(s.host, serverId: s.id);
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
      client = SSHClient(socket, username: s.username, onPasswordRequest: passwordCb, onVerifyHostKey: SshHostKeys.verifierFor(s.host, s.port), identities: keys ?? const []);
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
      client = SSHClient(socket, username: s.username, onPasswordRequest: passwordCb, onVerifyHostKey: SshHostKeys.verifierFor(s.host, s.port), identities: keys ?? const []);
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
      client = SSHClient(socket, username: s.username, onPasswordRequest: passwordCb, onVerifyHostKey: SshHostKeys.verifierFor(s.host, s.port), identities: keys ?? const []);
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
      client = SSHClient(socket, username: s.username, onPasswordRequest: passwordCb, onVerifyHostKey: SshHostKeys.verifierFor(s.host, s.port), identities: keys ?? const []);
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
      client = SSHClient(socket, username: s.username, onPasswordRequest: passwordCb, onVerifyHostKey: SshHostKeys.verifierFor(s.host, s.port), identities: keys ?? const []);
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
      client = SSHClient(socket, username: s.username, onPasswordRequest: passwordCb, onVerifyHostKey: SshHostKeys.verifierFor(s.host, s.port), identities: keys ?? const []);
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

  /// GET http://host:9108/procstats -> AppStats or null (agent v2+ only).
  /// [agentToken] is sent as X-MCP-Agent-Token when the host enforces
  /// v4 token auth; v2/v3 agents ignore the header. When omitted, the
  /// per-host token is read from the keychain via [serverId].
  Future<AppStats?> fetchAppStats(String host,
      {String? agentToken, String? serverId}) async {
    try {
      agentToken = await _resolveAgentToken(agentToken, serverId);
      final hc = HttpClient()..connectionTimeout = const Duration(seconds: 5);
      final req = await hc.get(host, agentPort, '/procstats');
      _applyAgentToken(req, agentToken);
      final resp = await req.close().timeout(const Duration(seconds: 8));
      if (resp.statusCode != 200) return null;
      final body = await resp.transform(utf8.decoder).join();
      hc.close();
      return AppStats.fromJson(jsonDecode(body) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  /// GET http://host:9108/metrics -> {cpu,ram,disk,uptime_days} or null.
  /// [agentToken] is sent as X-MCP-Agent-Token when the host enforces
  /// v4 token auth; v2/v3 agents ignore the header. When omitted, the
  /// per-host token is read from the keychain via [serverId].
  Future<Map<String, dynamic>?> fetch(String host,
      {String? agentToken, String? serverId}) async {
    try {
      agentToken = await _resolveAgentToken(agentToken, serverId);
      final hc = HttpClient()..connectionTimeout = const Duration(seconds: 5);
      final req = await hc.get(host, agentPort, '/metrics');
      _applyAgentToken(req, agentToken);
      final resp = await req.close().timeout(const Duration(seconds: 6));
      if (resp.statusCode != 200) return null;
      final body = await resp.transform(utf8.decoder).join();
      hc.close();
      return jsonDecode(body) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  /// GET http://host:9108/health -> AgentHealth or null (agent v4+ only).
  /// Null covers unreachable/timeout/non-200/stale-agent — use the typed
  /// pollers in service_locator for failures you must distinguish.
  /// Token resolution matches [fetch]: explicit value or keychain [serverId].
  Future<AgentHealth?> fetchHealth(String host,
      {String? agentToken, String? serverId}) async {
    try {
      agentToken = await _resolveAgentToken(agentToken, serverId);
      final hc = HttpClient()..connectionTimeout = const Duration(seconds: 5);
      final req = await hc.get(host, agentPort, kHealthPath);
      _applyAgentToken(req, agentToken);
      final resp = await req.close().timeout(const Duration(seconds: 5));
      if (resp.statusCode != 200) return null;
      final body = await resp.transform(utf8.decoder).join();
      hc.close();
      return parseAgentHealth(
          decodeAgentBody(body, kHealthPath));
    } catch (_) {
      return null;
    }
  }

  /// GET http://host:9108/sysstats -> decoded map or null (agent v3+ only).
  /// Null covers unreachable/timeout/non-200 — pair with [fetchHealth]
  /// when the caller must distinguish "agent down" from "stale agent".
  /// Token resolution matches [fetch]: explicit value or keychain [serverId].
  Future<Map<String, dynamic>?> fetchSysstats(String host,
      {String? agentToken, String? serverId}) async {
    try {
      agentToken = await _resolveAgentToken(agentToken, serverId);
      final hc = HttpClient()..connectionTimeout = const Duration(seconds: 5);
      final req = await hc.get(host, agentPort, kSysstatsPath);
      _applyAgentToken(req, agentToken);
      final resp = await req.close().timeout(const Duration(seconds: 8));
      if (resp.statusCode != 200) return null;
      final body = await resp.transform(utf8.decoder).join();
      hc.close();
      return jsonDecode(body) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  /// GET http://host:9108/logs?source=&lines= -> raw log lines (agent v4+).
  ///
  /// Throws typed [AgentProtocolException] (never null): `unauthorized`
  /// when the host enforces token auth, `badPayload` on a bad source
  /// (HTTP 400) or schema violation, `staleAgent` below the version
  /// floor. Pair with `LogTailService.parse` / `LogTailService.watch`
  /// to render or stream the lines.
  Future<List<String>> fetchAgentLogs(String host,
      {String source = 'journal',
      int lines = 100,
      String? agentToken,
      String? serverId}) async {
    final src = kAgentLogSources.contains(source) ? source : 'journal';
    final n = lines.clamp(20, 500);
    agentToken = await _resolveAgentToken(agentToken, serverId);
    try {
      final hc = HttpClient()..connectionTimeout = const Duration(seconds: 5);
      final req = await hc.get(host, agentPort, '/logs?source=$src&lines=$n');
      _applyAgentToken(req, agentToken);
      final resp = await req.close().timeout(const Duration(seconds: 8));
      final body = await resp.transform(utf8.decoder).join();
      hc.close();
      if (resp.statusCode != 200) {
        throw agentHttpError(resp.statusCode, '/logs');
      }
      final map = decodeAgentBody(body, '/logs');
      final version = map['version'];
      if (version is! num || version.toInt() < kMinAgentVersion) {
        throw const AgentProtocolException(
            AgentErrorCode.staleAgent, '/logs version missing or stale');
      }
      final raw = map['lines'];
      if (raw is! List) {
        throw const AgentProtocolException(
            AgentErrorCode.badPayload, '"/logs.lines" missing or not a list');
      }
      return raw.map((e) => e.toString()).toList();
    } on AgentProtocolException {
      rethrow;
    } on SocketException catch (e) {
      throw AgentProtocolException(
          AgentErrorCode.unreachable, '/logs unreachable: $e');
    } on TimeoutException {
      throw const AgentProtocolException(
          AgentErrorCode.timeout, '/logs read timed out');
    }
  }

  /// GET http://host:9108/cronruns?lines= -> newest-first run rows (agent
  /// v5+ only). Missing log file = empty list. Throws typed
  /// [AgentProtocolException] (never null): `unauthorized` on token
  /// mismatch, `badPayload` on a schema violation, `staleAgent` below the
  /// version floor. Pre-v5 agents answer 404 -> `badPayload`; callers that
  /// tolerate old agents should catch and fall back to [CronRunStore].
  Future<List<CronRunRecord>> fetchCronRuns(String host,
      {int lines = 50,
      String? agentToken,
      String? serverId}) async {
    final n = lines.clamp(1, 200);
    agentToken = await _resolveAgentToken(agentToken, serverId);
    try {
      final hc = HttpClient()..connectionTimeout = const Duration(seconds: 5);
      final req =
          await hc.get(host, agentPort, '$kCronRunsPath?lines=$n');
      _applyAgentToken(req, agentToken);
      final resp = await req.close().timeout(const Duration(seconds: 8));
      final body = await resp.transform(utf8.decoder).join();
      hc.close();
      if (resp.statusCode != 200) {
        throw agentHttpError(resp.statusCode, kCronRunsPath);
      }
      final map = decodeAgentBody(body, kCronRunsPath);
      final version = map['version'];
      if (version is! num || version.toInt() < kMinAgentVersion) {
        throw const AgentProtocolException(AgentErrorCode.staleAgent,
            '"/cronruns" version missing or stale');
      }
      final raw = map['runs'];
      if (raw is! List) {
        throw const AgentProtocolException(AgentErrorCode.badPayload,
            '"/cronruns.runs" missing or not a list');
      }
      return CronRunTracker.parseAgentRuns(raw);
    } on AgentProtocolException {
      rethrow;
    } on SocketException catch (e) {
      throw AgentProtocolException(
          AgentErrorCode.unreachable, '$kCronRunsPath unreachable: $e');
    } on TimeoutException {
      throw const AgentProtocolException(
          AgentErrorCode.timeout, '"$kCronRunsPath" read timed out');
    }
  }

  /// Attaches the reserved agent token header when configured.
  /// v2/v3 agents ignore unknown headers, so this is safe to always send.
  static void _applyAgentToken(HttpClientRequest req, String? agentToken) {
    for (final e in agentAuthHeaders(agentToken).entries) {
      req.headers.set(e.key, e.value);
    }
  }

  /// Explicit [agentToken] wins; otherwise the per-host token from the
  /// keychain ([serverId]). Null = open agent, header omitted.
  static Future<String?> _resolveAgentToken(
      String? agentToken, String? serverId) async {
    if ((agentToken ?? '').trim().isNotEmpty) return agentToken!.trim();
    if (serverId == null || serverId.isEmpty) return null;
    final stored = await SecureStore.readAgentToken(serverId);
    return (stored ?? '').trim().isEmpty ? null : stored!.trim();
  }

  /// Fresh per-host agent token (256-bit, base64url). The value is written
  /// to the host env file AND the keychain together — never logged.
  static String newAgentToken() {
    final bytes = List<int>.generate(32, (_) => _random.nextInt(256));
    return base64Url.encode(bytes).replaceAll('=', '');
  }

  static final _random = Random.secure();
}
