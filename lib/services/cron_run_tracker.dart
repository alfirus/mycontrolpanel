import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/cron_entry.dart';

/// Cron last-run tracker (no new plugins).
///
/// Two halves that meet in the Cronjobs screen:
///
/// 1. **Agent-side run log** — the v5 agent serves `/cronruns` from
///    `/var/log/mcp-cronruns.log` (one `<epoch_s> <name> <exit> [dur_s>`
///    line per run; jobs opt in by appending — see the runbook). Missing
///    file / older agent = empty list, never an error.
/// 2. **Client cache + matching** — [CronRunStore] persists the last-good
///    agent response per host (SharedPreferences) so the timeline shows
///    stale-but-real data offline; [CronRunTracker.matchRecord] joins a
///    discovered [CronEntry] to its newest run by program name.
///
/// Matching is by program (first-token basename, `sh -c`/`bash -lc`/`env`
/// wrappers unwrapped — same convention as `fetchCronLogs`), so schedule
/// edits and wrapper changes do not lose a job's history.
enum CronRunStatus { ok, error, unknown }

/// One observed run of a cronjob.
class CronRunRecord {
  /// Program name as the agent logged it (e.g. `backup`, `run.sh`).
  final String name;

  /// When the run finished (null = never observed).
  final DateTime? ranAt;

  /// Process exit code (null = unknown).
  final int? exit;

  /// Run duration in whole seconds (null = unknown).
  final int? durSecs;

  /// Where the record came from: `'agent'` or `'cache'`.
  final String source;

  const CronRunRecord({
    required this.name,
    this.ranAt,
    this.exit,
    this.durSecs,
    this.source = 'agent',
  });

  CronRunStatus get status {
    if (ranAt == null) return CronRunStatus.unknown;
    if (exit == null) return CronRunStatus.ok;
    return exit == 0 ? CronRunStatus.ok : CronRunStatus.error;
  }

  /// Parse one v5 agent `/cronruns` row (`at` is epoch *seconds*).
  /// Returns null for hostile rows (skipped, never fatal).
  static CronRunRecord? fromAgent(Map<String, dynamic> j) {
    try {
      final name = (j['name'] ?? '').toString();
      if (name.isEmpty) return null;
      final at = (j['at'] as num?)?.toInt();
      final exit = (j['exit'] as num?)?.toInt();
      var dur = (j['dur_s'] as num?)?.toInt();
      if (dur != null && dur < 0) dur = null;
      return CronRunRecord(
        name: name,
        ranAt: at == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(at * 1000, isUtc: true)
                .toLocal(),
        exit: exit,
        durSecs: dur,
      );
    } catch (_) {
      return null;
    }
  }

  Map<String, dynamic> toJson() => {
        'name': name,
        'ranAt': ranAt?.millisecondsSinceEpoch,
        'exit': exit,
        'durSecs': durSecs,
        'source': source,
      };

  static CronRunRecord? fromJson(Map<String, dynamic> j) {
    try {
      final name = (j['name'] ?? '').toString();
      if (name.isEmpty) return null;
      final ms = (j['ranAt'] as num?)?.toInt();
      return CronRunRecord(
        name: name,
        ranAt: ms == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true).toLocal(),
        exit: (j['exit'] as num?)?.toInt(),
        durSecs: (j['dur_s'] as num?)?.toInt() ??
            (j['durSecs'] as num?)?.toInt(),
        source: 'cache',
      );
    } catch (_) {
      return null;
    }
  }

  /// `backup` from `/usr/bin/backup --full`; `run.sh` from `bash -lc run.sh`.
  static String programOf(String command) {
    final first = command
        .trim()
        .split(RegExp(r'\s+'))
        .firstWhere((t) => t.isNotEmpty, orElse: () => '');
    if (first.isEmpty) return '';
    final base = first.split('/').last;
    if ((base == 'bash' || base == 'sh' || base == 'env') &&
        command.contains(' ')) {
      final rest =
          command.trim().split(RegExp(r'\s+')).skip(1).join(' ').trim();
      final cleaned =
          rest.replaceAll(RegExp('^[-lc\\s\'"]+'), '').trim();
      final token = cleaned
          .split(RegExp(r'\s+'))
          .firstWhere((t) => t.isNotEmpty && t != '-c' && t != '-lc',
              orElse: () => '');
      if (token.isNotEmpty) {
        return token
            .split('/')
            .last
            .replaceAll(RegExp(r'''['";]'''), '');
      }
    }
    return base;
  }

  /// Short duration for the timeline (`12s`, `3m 4s`, `—` when unknown).
  static String formatDur(int? durSecs) {
    if (durSecs == null) return '—';
    if (durSecs < 60) return '${durSecs}s';
    if (durSecs < 3600) return '${durSecs ~/ 60}m ${durSecs % 60}s';
    return '${durSecs ~/ 3600}h ${(durSecs % 3600) ~/ 60}m';
  }
}

/// Joins discovered crons to their last runs (pure, testable).
class CronRunTracker {
  /// Stable join key: `serverId::<program>`.
  static String jobKey(String serverId, String command) =>
      '$serverId::${CronRunRecord.programOf(command).toLowerCase()}';

  /// Newest run whose logged name matches [entry]'s program, or null.
  /// Name comparison is case-insensitive; ties keep the first row.
  static CronRunRecord? matchRecord(
    List<CronRunRecord> records,
    CronEntry entry,
  ) {
    final program = CronRunRecord.programOf(entry.command).toLowerCase();
    if (program.isEmpty) return null;
    CronRunRecord? best;
    for (final r in records) {
      if (r.name.toLowerCase() != program) continue;
      if (r.ranAt == null) {
        best ??= r;
        continue;
      }
      if (best == null ||
          best.ranAt == null ||
          r.ranAt!.isAfter(best.ranAt!)) {
        best = r;
      }
    }
    return best;
  }

  /// Group agent rows by host for the screen (`serverId -> runs`).
  /// Hostile rows are dropped, never fatal.
  static List<CronRunRecord> parseAgentRuns(List<dynamic> rows) {
    final out = <CronRunRecord>[];
    for (final row in rows) {
      if (row is! Map<String, dynamic>) continue;
      final rec = CronRunRecord.fromAgent(row);
      if (rec != null) out.add(rec);
    }
    return out;
  }
}

/// Last-good `/cronruns` responses, one JSON blob per host.
///
/// Same pattern as [MetricsHistory]: best-effort, silent on failure, so a
/// cache fault can never break the Cronjobs screen.
class CronRunStore {
  static const _prefix = 'cronruns_';
  static const _cap = 200;

  static String _key(String host) =>
      '$_prefix${host.replaceAll(RegExp(r'[^A-Za-z0-9_.\-]'), '_')}';

  static Future<void> save(String host, List<CronRunRecord> runs) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final capped = runs.take(_cap).toList();
      await prefs.setString(
        _key(host),
        jsonEncode({
          'at': DateTime.now().millisecondsSinceEpoch,
          'runs': capped.map((r) => r.toJson()).toList(),
        }),
      );
    } catch (_) {}
  }

  static Future<List<CronRunRecord>> read(String host) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key(host));
      if (raw == null) return [];
      final doc = jsonDecode(raw) as Map<String, dynamic>;
      final rows = (doc['runs'] as List?) ?? [];
      return rows
          .whereType<Map<String, dynamic>>()
          .map(CronRunRecord.fromJson)
          .whereType<CronRunRecord>()
          .toList();
    } catch (_) {
      return [];
    }
  }

  /// When the last-good response for [host] was saved (null = never).
  static Future<DateTime?> savedAt(String host) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key(host));
      if (raw == null) return null;
      final ms = ((jsonDecode(raw) as Map)['at'] as num?)?.toInt();
      return ms == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true).toLocal();
    } catch (_) {
      return null;
    }
  }
}
