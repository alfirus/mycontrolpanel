/// A crontab entry discovered on a real server via SSH.
class CronEntry {
  final String schedule; // e.g. "0 * * * *" or "@daily"
  final String command;
  final String source; // e.g. "crontab", "/etc/crontab", "/etc/cron.d/app"
  final String serverId;
  final String serverName;
  final bool enabled;
  final String rawLine; // exact original line (needed for in-place edits)

  const CronEntry({
    required this.schedule,
    required this.command,
    required this.source,
    required this.serverId,
    required this.serverName,
    this.enabled = true,
    this.rawLine = '',
  });

  /// Parse classic 5-field cron lines from crontab output.
  /// System files (/etc/crontab, /etc/cron.d/*) include a user field.
  static List<CronEntry> parse({
    required String output,
    required String source,
    required bool hasUserField,
    required String serverId,
    required String serverName,
  }) {
    final entries = <CronEntry>[];
    for (final raw in output.split('\n')) {
      final line = raw.trim();
      if (line.isEmpty || line.startsWith('#')) continue;
      // env assignments (PATH=..., MAILTO=...) are not jobs
      if (RegExp(r'^[A-Za-z_][A-Za-z0-9_]*\s*=').hasMatch(line)) continue;
      if (line.startsWith('@')) {
        // @reboot / @daily style
        final m = RegExp(r'^(@\w+)\s+(?:(\S+)\s+)?(.+)$').firstMatch(line);
        if (m == null) continue;
        var cmd = m.group(3) ?? '';
        if (hasUserField) {
          final parts = cmd.split(RegExp(r'\s+'));
          if (parts.length > 1) cmd = parts.skip(1).join(' ');
        }
        entries.add(CronEntry(
          schedule: m.group(1)!,
          command: cmd,
          source: source,
          serverId: serverId,
          serverName: serverName,
          rawLine: line,
        ));
        continue;
      }
      final parts = line.split(RegExp(r'\s+'));
      final offset = hasUserField ? 6 : 5;
      if (parts.length <= offset) continue;
      final fields = parts.take(5).toList();
      if (!fields.every((f) => RegExp(r'^[\d*,/\-@a-zA-Z]+$').hasMatch(f))) continue;
      var cmd = parts.skip(offset).join(' ');
      if (hasUserField) {
        // parts[5] is the user — already skipped via offset; nothing extra
      }
      entries.add(CronEntry(
        schedule: fields.join(' '),
        command: cmd,
        source: source,
        serverId: serverId,
        serverName: serverName,
        rawLine: line,
      ));
    }
    return entries;
  }
}
