import '../models/mock_data.dart';
import '../models/server_connection.dart';
import 'agent_protocol.dart';
import 'agent_service.dart';

/// Real log tail over SSH (replaces the simulated heartbeat in
/// control_center_screen.dart when real servers are configured).
///
/// Sources are read-only and allowlisted:
/// - journal:  journalctl --no-pager -n <lines> (newest last)
/// - syslog:   tail of /var/log/syslog|messages|*.log
/// - docker:   docker logs --tail=<lines> <container>
///
/// [allowedSources] is the subset the v4 agent serves over HTTP `/logs`
/// (see [kAgentLogSources]); `docker` has no agent equivalent and stays
/// SSH-only via [sshOnlySources].
class LogTailService {
  static const allowedSources = kAgentLogSources;
  static const sshOnlySources = ['docker'];

  /// All sources the SSH path accepts (agent subset + SSH-only extras).
  static const sshSources = [...kAgentLogSources, 'docker'];

  Future<List<LogLine>> fetch(
    AgentService agent,
    ServerConnection server,
    String container, {
    String source = 'journal',
    int lines = 100,
    String? keyPassphrase,
  }) async {
    if (!sshSources.contains(source)) {
      throw Exception('Unknown log source "$source" (try journal/syslog).');
    }
    final n = lines.clamp(20, 500);
    late final String cmd;
    if (source == 'docker') {
      final c = container.trim().replaceAll(RegExp(r'[^A-Za-z0-9_.\-]'), '');
      if (c.isEmpty) throw Exception('Pick a Docker container first.');
      cmd = 'docker logs --tail=$n $c 2>&1 | tail -n $n';
    } else if (source == 'syslog') {
      cmd =
          '(sudo -n tail -n $n /var/log/syslog /var/log/messages 2>/dev/null || tail -n $n /var/log/syslog /var/log/messages 2>/dev/null || journalctl --no-pager -n $n 2>/dev/null)';
    } else {
      cmd = 'journalctl --no-pager -n $n 2>/dev/null || sudo -n journalctl --no-pager -n $n 2>/dev/null';
    }
    final raw = await agent.runCommand(server, cmd, keyPassphrase: keyPassphrase);
    return parse(raw, fallbackSource: server.name);
  }

  /// Poll [poll] every [interval], yielding a fresh [LogLine] list only
  /// when the content signature changes (dedupe by level+message).
  /// Poll errors are swallowed — the previous snapshot stands and the
  /// next tick retries. Pass [maxPolls] in tests to bound the stream.
  static Stream<List<LogLine>> watch(
    Future<List<LogLine>> Function() poll, {
    Duration interval = const Duration(seconds: 5),
    int? maxPolls,
  }) async* {
    List<String>? last;
    var n = 0;
    while (maxPolls == null || n < maxPolls) {
      n++;
      try {
        final lines = await poll();
        final sig = lines.map((l) => '${l.level}:${l.message}').toList();
        if (!_sameSig(sig, last)) {
          last = sig;
          yield lines;
        }
      } catch (_) {
        // Keep the previous snapshot; retry next tick.
      }
      if (maxPolls != null && n >= maxPolls) break;
      await Future<void>.delayed(interval);
    }
  }

  /// Stream the v4 agent's HTTP `/logs` endpoint (no SSH session needed).
  /// Same contract as [watch]: yields only on content change.
  static Stream<List<LogLine>> watchAgent(
    AgentService agent,
    String host, {
    String source = 'journal',
    int lines = 100,
    String? agentToken,
    Duration interval = const Duration(seconds: 5),
    int? maxPolls,
  }) {
    return watch(
      () async {
        final raw = await agent.fetchAgentLogs(host,
            source: source, lines: lines, agentToken: agentToken);
        return parse(raw.join('\n'), fallbackSource: host);
      },
      interval: interval,
      maxPolls: maxPolls,
    );
  }

  static bool _sameSig(List<String> a, List<String>? b) {
    if (b == null || a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  /// Parse raw `runCommand` output (`[exit N]\n<body>`) into LogLines.
  /// Never throws — unparseable lines become INFO lines.
  static List<LogLine> parse(String raw, {String fallbackSource = 'server'}) {
    final body = raw.startsWith('[exit')
        ? raw.split('\n').skip(1).join('\n')
        : raw;
    final out = <LogLine>[];
    final now = DateTime.now();
    for (final line in body.split('\n')) {
      final t = line.trimRight();
      if (t.trim().isEmpty) continue;
      if (t.startsWith('[stderr]') && t.trim() == '[stderr]') continue;
      out.add(LogLine(
        time: now,
        level: _guessLevel(t),
        source: fallbackSource,
        message: t.length > 300 ? '${t.substring(0, 300)}…' : t,
      ));
    }
    return out.reversed.toList();
  }

  static String _guessLevel(String line) {
    final l = line.toLowerCase();
    if (l.contains('error') || l.contains('fail') || l.contains('fatal') || l.contains('exception') || l.contains('denied')) {
      return 'ERROR';
    }
    if (l.contains('warn') || l.contains('retry') || l.contains('timeout') || l.contains('deprecated')) {
      return 'WARN';
    }
    if (l.contains('debug') || l.contains('trace')) return 'DEBUG';
    return 'INFO';
  }
}
