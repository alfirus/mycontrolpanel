import '../models/mock_data.dart';
import '../models/server_connection.dart';
import 'agent_service.dart';

/// Real log tail over SSH (replaces the simulated heartbeat in
/// control_center_screen.dart when real servers are configured).
///
/// Sources are read-only and allowlisted:
/// - journal:  journalctl --no-pager -n <lines> (newest last)
/// - syslog:   tail of /var/log/syslog|messages|*.log
/// - docker:   docker logs --tail=<lines> <container>
class LogTailService {
  static const allowedSources = ['journal', 'syslog', 'docker'];

  Future<List<LogLine>> fetch(
    AgentService agent,
    ServerConnection server,
    String container, {
    String source = 'journal',
    int lines = 100,
    String? keyPassphrase,
  }) async {
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
