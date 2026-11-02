// SPDX-License-Identifier: MIT
/// `agent_check` report builder (Beta.2, Nadia owns).
///
/// Pure-Dart half of the `bin/agent_check.dart` entry-point: parse the
/// JSONL delivery log (delivery rows + `tick`/`mem` sample lines),
/// evaluate the frozen [AlertSlo]s, and build the machine-readable
/// check report. No I/O here — the bin wrapper owns files/exit codes —
/// so `flutter test` covers every branch.
///
/// Log line shapes (all optional except delivery rows; hostile lines
/// are skipped, never fatal):
/// - delivery: `AlertDeliveryRecord.toJson()` verbatim.
/// - tick cost: `{"tickMs": 123.4, "atMs": ...}`.
/// - agent footprint: `{"memMb": 20.5, "atMs": ..., "cpu": 0.1,
///   "battery": 0.8}` (cpu/battery best-effort, mem carries the SLO).
///
/// Privacy: the report carries signal titles + aggregate rates only —
/// never credentials, markers, or paths (same rule as the
/// `--poll-headless` stdout contract).
library;

import 'dart:convert';

import 'alert_log_rotation.dart';
import 'alert_reliability.dart';

/// Parsed content of one JSONL delivery log (all live generations).
class AgentCheckLog {
  final List<AlertDeliveryRecord> rows;
  final List<double> tickDurationsMs;
  final List<AgentResourceSample> samples;

  const AgentCheckLog({
    this.rows = const [],
    this.tickDurationsMs = const [],
    this.samples = const [],
  });

  bool get isEmpty =>
      rows.isEmpty && tickDurationsMs.isEmpty && samples.isEmpty;
}

/// `agent_check` exit codes mirror the headless TM-1 contract:
/// `0` = healthy, `2` = skipped/no data, `1` = breach or error.
abstract class AgentCheckExit {
  static const int ok = 0;
  static const int error = 1;
  static const int skipped = 2;
}

/// One `agent_check --check` evaluation outcome.
class AgentCheckReport {
  /// Report schema version (1).
  final int version;

  /// `healthy` | `breach` | `no-data`.
  final String status;

  /// Mirrors [AgentCheckExit].
  final int exitCode;

  /// When the check ran (ms since epoch).
  final int checkedAtMs;

  /// SLO evaluation over the parsed window.
  final AlertSloReport slo;

  /// Delivery-log path checked (base generation).
  final String logPath;

  /// Total bytes across live generations at check time.
  final int logBytes;

  /// True when the live log reached [AlertLogRotation.maxBytes].
  final bool rotationDue;

  /// Set only on `no-data` (why there was nothing to evaluate).
  final String? reason;

  const AgentCheckReport({
    this.version = 1,
    required this.status,
    required this.exitCode,
    required this.checkedAtMs,
    required this.slo,
    required this.logPath,
    required this.logBytes,
    required this.rotationDue,
    this.reason,
  });

  bool get healthy => status == 'healthy';

  Map<String, Object?> toJson() => {
        'version': version,
        'tool': 'agent_check',
        'status': status,
        'exitCode': exitCode,
        'checkedAtMs': checkedAtMs,
        'slo': slo.toJson(),
        'log': {
          'path': logPath,
          'bytes': logBytes,
          'rotationDue': rotationDue,
        },
        if (reason != null) 'reason': reason,
      };
}

/// Parse one JSONL line. Returns the delivery row, tick ms, or sample
/// via the out-params pattern below — see [parseLogLines] for the
/// batch form. Hostile lines yield null (skipped, never fatal).
Object? tryParseLogLine(String line) {
  dynamic decoded;
  try {
    decoded = jsonDecode(line);
  } catch (_) {
    return null;
  }
  if (decoded is! Map) return null;
  final map = decoded.cast<String, Object?>();
  if (map.containsKey('tickMs')) {
    final ms = map['tickMs'];
    final at = map['atMs'];
    if (ms is num && ms.isFinite && ms >= 0) {
      return _TickSample(ms.toDouble(), at is num ? at.toInt() : 0);
    }
    return null;
  }
  if (map.containsKey('memMb')) {
    final mem = map['memMb'];
    if (mem is num && mem.isFinite && mem >= 0) {
      double? optDouble(Object? v) =>
          v is num && v.isFinite ? v.toDouble() : null;
      int at = 0;
      if (map['atMs'] is num) at = (map['atMs']! as num).toInt();
      return AgentResourceSample(
        cpu: optDouble(map['cpu']),
        memMb: mem.toDouble(),
        battery: optDouble(map['battery']),
        atMs: at,
      );
    }
    return null;
  }
  return AlertDeliveryRecord.tryFromJson(map);
}

/// Batch-parse log lines (all live generations, any order).
AgentCheckLog parseLogLines(Iterable<String> lines) {
  final rows = <AlertDeliveryRecord>[];
  final ticks = <double>[];
  final samples = <AgentResourceSample>[];
  for (final line in lines) {
    if (line.trim().isEmpty) continue;
    final parsed = tryParseLogLine(line);
    if (parsed is AlertDeliveryRecord) {
      rows.add(parsed);
    } else if (parsed is _TickSample) {
      ticks.add(parsed.ms);
    } else if (parsed is AgentResourceSample) {
      samples.add(parsed);
    }
  }
  return AgentCheckLog(rows: rows, tickDurationsMs: ticks, samples: samples);
}

/// Build the check report from parsed log content.
AgentCheckReport buildCheckReport({
  required AgentCheckLog log,
  required int nowMs,
  required String logPath,
  required int logBytes,
}) {
  final tracker = AlertReliabilityTracker();
  for (final row in log.rows) {
    tracker.recordScheduled(row.id, row.scheduledMs,
        transport: row.transport);
    if (row.executedMs != null) {
      tracker.recordExecuted(row.id, row.executedMs!);
    }
    if (row.notifiedMs != null) {
      tracker.recordNotified(row.id, row.notifiedMs!);
    }
    if (row.dismissedMs != null) {
      tracker.recordDismissed(row.id, row.dismissedMs!);
    }
  }
  for (final ms in log.tickDurationsMs) {
    tracker.recordTickDurationMs(ms);
  }
  for (final sample in log.samples) {
    tracker.recordResourceSample(sample);
  }
  final slo = tracker.evaluateSlo(nowMs: nowMs);
  final rotationDue = AlertLogRotation.rotationDue(logBytes);
  if (log.isEmpty) {
    return AgentCheckReport(
      status: 'no-data',
      exitCode: AgentCheckExit.skipped,
      checkedAtMs: nowMs,
      slo: slo,
      logPath: logPath,
      logBytes: logBytes,
      rotationDue: rotationDue,
      reason: 'delivery log holds no rows, ticks, or samples yet',
    );
  }
  final breached = slo.breaches.isNotEmpty;
  return AgentCheckReport(
    status: breached ? 'breach' : 'healthy',
    exitCode: breached ? AgentCheckExit.error : AgentCheckExit.ok,
    checkedAtMs: nowMs,
    slo: slo,
    logPath: logPath,
    logBytes: logBytes,
    rotationDue: rotationDue,
    reason: breached ? 'SLO breach: ${slo.breaches.join(', ')}' : null,
  );
}

class _TickSample {
  final double ms;
  final int atMs;
  const _TickSample(this.ms, this.atMs);
}
