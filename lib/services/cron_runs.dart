/// Cron last-run parsing over SSH log tails.
///
/// `AgentService.fetchCronLogs` greps journal + syslog for a job's program
/// name and returns the raw text (newest first, capped). This parser finds
/// the newest execution of [command] in that text: syslog/journal CRON
/// lines (`Oct 28 06:30:01 host CRON[123]: (user) CMD (...)`) plus an
/// optional `[exit N]` marker, which the agent prepends when it knows the
/// outcome. Pure logic — no SSH, no plugins, safe for CI.
class CronRuns {
  static const _months = {
    'Jan': 1, 'Feb': 2, 'Mar': 3, 'Apr': 4, 'May': 5, 'Jun': 6,
    'Jul': 7, 'Aug': 8, 'Sep': 9, 'Oct': 10, 'Nov': 11, 'Dec': 12,
  };

  /// Parse the last run of [command] from [logText].
  /// Matches on the program name (first-token basename) so schedule
  /// wrappers (`/usr/bin/env`, `bash -lc`) still hit. [now] anchors the
  /// year rollover for syslog timestamps (Dec log in Jan => last year).
  static CronLastRun parse({
    required String command,
    required String logText,
    DateTime? now,
  }) {
    final ref = now ?? DateTime.now();
    final program = _programOf(command);
    var exitCode = _headExit(logText);

    CronLastRun? best;
    for (final line in logText.split('\n')) {
      if (!_mentionsCron(line)) continue;
      if (!_mentionsProgram(line, program, command)) continue;
      final at = _parseTime(line, ref);
      if (at == null) continue;
      final failed = _looksFailed(line);
      final candidate = CronLastRun(
        ranAt: at,
        status: failed ? CronRunStatus.error : CronRunStatus.ok,
        exitCode: failed ? exitCode : (exitCode == 0 ? 0 : exitCode),
      );
      if (best == null ||
          best.ranAt == null ||
          candidate.ranAt!.isAfter(best.ranAt!)) {
        best = candidate;
      }
    }
    if (best == null) return const CronLastRun(status: CronRunStatus.unknown);
    if (exitCode != null && best.status == CronRunStatus.error) {
      return CronLastRun(ranAt: best.ranAt, status: best.status, exitCode: exitCode);
    }
    return best;
  }

  /// `foo` from `/usr/bin/foo --bar`, `run.sh` from `bash -lc run.sh`.
  static String _programOf(String command) {
    final first = command.trim().split(RegExp(r'\s+')).firstWhere(
        (t) => t.isNotEmpty,
        orElse: () => '');
    if (first.isEmpty) return '';
    // Unwrap common interpreter prefixes: bash -lc 'cmd', sh -c cmd.
    if ((first == 'bash' || first == 'sh' || first == 'env') &&
        command.contains(' ')) {
      final rest = command.trim().split(RegExp(r'\s+')).skip(1).join(' ');
      final cleaned = rest.replaceAll(RegExp("^[-lc\\s'\"]+"), '');
      final token = cleaned.split(RegExp(r'\s+')).firstWhere(
          (t) => t.isNotEmpty && t != '-c' && t != '-lc',
          orElse: () => '');
      if (token.isNotEmpty) return token.split('/').last;
    }
    return first.split('/').last;
  }

  static bool _mentionsCron(String line) {
    final l = line.toLowerCase();
    return l.contains('cron');
  }

  static bool _mentionsProgram(String line, String program, String command) {
    if (program.isEmpty) return false;
    if (line.contains(program)) return true;
    // Fallback: distinctive long token from the command itself.
    for (final tok in command.split(RegExp(r'\s+'))) {
      if (tok.length >= 8 && line.contains(tok)) return true;
    }
    return false;
  }

  /// `[exit N]` marker on the first line, when the agent knows it.
  static int? _headExit(String logText) {
    final first = logText.trimLeft().split('\n').first;
    final m = RegExp(r'^\[exit (\d+)\]').firstMatch(first);
    return m == null ? null : int.tryParse(m.group(1)!);
  }

  static DateTime? _parseTime(String line, DateTime ref) {
    // Syslog: `Oct 28 06:30:01` (no year); journal: `2026-10-28 06:30:01`
    // or `Oct 28 06:30:01.123456`; ISO: `2026-10-28T06:30:01`.
    var m = RegExp(
            r'^(\d{4})-(\d{2})-(\d{2})[T ](\d{2}):(\d{2}):(\d{2})')
        .firstMatch(line);
    if (m != null) {
      return DateTime(
        int.parse(m.group(1)!), int.parse(m.group(2)!),
        int.parse(m.group(3)!), int.parse(m.group(4)!),
        int.parse(m.group(5)!), int.parse(m.group(6)!));
    }
    m = RegExp(r'^([A-Z][a-z]{2})\s+(\d{1,2}) (\d{2}):(\d{2}):(\d{2})')
        .firstMatch(line);
    if (m == null) return null;
    final mon = _months[m.group(1)!];
    if (mon == null) return null;
    var year = ref.year;
    if (mon == 12 && ref.month == 1) year -= 1; // Dec log read in Jan
    return DateTime(year, mon, int.parse(m.group(2)!),
        int.parse(m.group(3)!), int.parse(m.group(4)!),
        int.parse(m.group(5)!));
  }

  static bool _looksFailed(String line) {
    final l = line.toLowerCase();
    return l.contains('failed') ||
        l.contains('error') ||
        l.contains('exit 1') ||
        l.contains('non-zero') ||
        l.contains('no such file') ||
        l.contains('permission denied');
  }
}

/// One parsed cron execution.
class CronLastRun {
  final DateTime? ranAt;
  final CronRunStatus status;
  final int? exitCode;

  const CronLastRun(
      {this.ranAt, this.status = CronRunStatus.ok, this.exitCode});

  const CronLastRun.unknown() : this(status: CronRunStatus.unknown);

  bool get known => status != CronRunStatus.unknown && ranAt != null;

  /// One-line caption for dialogs, e.g. `last run Oct 28 06:30 ✓`
  /// or `last run unknown — no matching log lines`.
  String caption(DateTime now) {
    if (!known) return 'last run unknown — no matching log lines';
    final d = ranAt!;
    final sameDay = d.year == now.year && d.month == now.month && d.day == now.day;
    final when = sameDay
        ? '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')} today'
        : '${_mon(d.month)} ${d.day} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
    final mark = status == CronRunStatus.ok ? '✓' : '✗';
    final exit = exitCode == null ? '' : ' (exit $exitCode)';
    return 'last run $when $mark$exit';
  }

  static String _mon(int m) => const [
        '', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
        'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
      ][m];
}

enum CronRunStatus { ok, error, unknown }
