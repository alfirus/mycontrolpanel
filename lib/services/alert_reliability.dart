// SPDX-License-Identifier: MIT
/// Alert-pipeline reliability harness (Beta.2, Nadia owns).
///
/// End-to-end instrumentation for the tray-mode alert pipeline: every
/// firing signal moves through the lifecycle
/// `scheduled → executed → notified → dismissed`, and this file records
/// each transition with timestamps so SLOs can be evaluated on-device.
///
/// Pure Dart, no plugins — the headless tick, the in-app [AlertPollJob],
/// and the `agent_check --check` harness all share these evaluators.
/// Persistence is a JSONL delivery log (one [AlertDeliveryRecord] per
/// line); rotation policy lives in `alert_log_rotation.dart` (Nadia,
/// operability PR) so this file stays dependency-free.
///
/// SLOs (binding, see `docs/specs/alert-reliability-slos.md`):
/// - Delivery: 99% of scheduled signals notified within 5 min.
/// - Drops: <1% of scheduled signals never notified.
/// - Tick cost: p95 poll-tick wall time <2 s.
/// - Agent footprint: p95 agent RSS <50 MB.
library;

/// Lifecycle stages of one firing signal through the alert pipeline.
enum AlertLifecycleStage {
  /// A poll tick (headless or in-app) produced this signal.
  scheduled,

  /// The signal survived transport + policy (backoff/consent/vault gates
  /// passed) and reached the notify fan-out.
  executed,

  /// The OS notification rail accepted the signal
  /// (`NotificationHook.build` payload shown).
  notified,

  /// The user acted on or cleared the signal (rail dismiss / open).
  dismissed,
}

/// One row of the delivery log: the full lifecycle of a single signal.
///
/// Identity reuses [AlertWatch.keyFor] (`kind::owner::title`) verbatim so
/// headless and in-app rails share one dedup contract — never a second
/// id scheme.
class AlertDeliveryRecord {
  /// Stable signal identity (`kind::owner::title`).
  final String id;

  /// When the signal was scheduled (ms since epoch). Always set.
  final int scheduledMs;

  /// When the signal passed the gates and reached fan-out, if ever.
  final int? executedMs;

  /// When the OS rail accepted the notification, if ever.
  final int? notifiedMs;

  /// When the user dismissed/opened the signal, if ever.
  final int? dismissedMs;

  /// Which transport legs answered (`agent`, `ssh`, `both`, `none`).
  final String transport;

  const AlertDeliveryRecord({
    required this.id,
    required this.scheduledMs,
    this.executedMs,
    this.notifiedMs,
    this.dismissedMs,
    this.transport = 'none',
  });

  /// Furthest lifecycle stage reached so far.
  AlertLifecycleStage get stage {
    if (dismissedMs != null) return AlertLifecycleStage.dismissed;
    if (notifiedMs != null) return AlertLifecycleStage.notified;
    if (executedMs != null) return AlertLifecycleStage.executed;
    return AlertLifecycleStage.scheduled;
  }

  /// Schedule → notify latency in ms, or null while un-notified.
  int? get notifyLatencyMs =>
      notifiedMs == null ? null : notifiedMs! - scheduledMs;

  /// Monotonicity guard: transitions must not run backwards in time.
  /// Returns false for hostile/corrupt rows instead of throwing.
  bool get isChronologySane {
    if (executedMs != null && executedMs! < scheduledMs) return false;
    if (notifiedMs != null &&
        notifiedMs! < (executedMs ?? scheduledMs)) {
      return false;
    }
    if (dismissedMs != null && dismissedMs! < (notifiedMs ?? scheduledMs)) {
      return false;
    }
    return true;
  }

  Map<String, Object?> toJson() => {
        'id': id,
        'scheduledMs': scheduledMs,
        if (executedMs != null) 'executedMs': executedMs,
        if (notifiedMs != null) 'notifiedMs': notifiedMs,
        if (dismissedMs != null) 'dismissedMs': dismissedMs,
        'transport': transport,
      };

  /// Lenient parse: hostile lines yield null (skipped, never fatal).
  static AlertDeliveryRecord? tryFromJson(Map<String, Object?> json) {
    try {
      final id = json['id'];
      final scheduled = json['scheduledMs'];
      if (id is! String || id.isEmpty) return null;
      if (scheduled is! num || !scheduled.isFinite) return null;
      int? optInt(Object? v) =>
          v is num && v.isFinite ? v.toInt() : null;
      final transport = json['transport'];
      return AlertDeliveryRecord(
        id: id,
        scheduledMs: scheduled.toInt(),
        executedMs: optInt(json['executedMs']),
        notifiedMs: optInt(json['notifiedMs']),
        dismissedMs: optInt(json['dismissedMs']),
        transport: transport is String ? transport : 'none',
      );
    } catch (_) {
      return null;
    }
  }
}

/// One agent-footprint sample (CPU/mem/battery at a poll tick).
class AgentResourceSample {
  /// Agent CPU share 0..1 over the tick, if known.
  final double? cpu;

  /// Agent resident set size in MB, if known.
  final double? memMb;

  /// Device battery 0..1, if known (mobile headless ticks).
  final double? battery;

  /// When the sample was taken (ms since epoch).
  final int atMs;

  const AgentResourceSample({
    this.cpu,
    this.memMb,
    this.battery,
    required this.atMs,
  });
}

/// In-memory delivery tracker: records lifecycle transitions and
/// evaluates the Beta.2 alert SLOs over the window it holds.
///
/// The headless tick owns one per process lifetime; the JSONL delivery
/// log (same [AlertDeliveryRecord] rows) is the durable form the
/// `agent_check --check` harness reads back.
class AlertReliabilityTracker {
  final Map<String, AlertDeliveryRecord> _rows = {};

  /// Poll-tick wall times in ms (tick start → fan-out done).
  final List<double> tickDurationsMs = [];

  /// Agent footprint samples parallel to the ticks.
  final List<AgentResourceSample> resourceSamples = [];

  void recordScheduled(
    String id,
    int atMs, {
    String transport = 'none',
  }) {
    if (id.isEmpty) return;
    _rows[id] = AlertDeliveryRecord(
      id: id,
      scheduledMs: atMs,
      transport: transport,
    );
  }

  void recordExecuted(String id, int atMs) {
    final row = _rows[id];
    if (row == null) return;
    _rows[id] = AlertDeliveryRecord(
      id: row.id,
      scheduledMs: row.scheduledMs,
      executedMs: atMs,
      notifiedMs: row.notifiedMs,
      dismissedMs: row.dismissedMs,
      transport: row.transport,
    );
  }

  void recordNotified(String id, int atMs) {
    final row = _rows[id];
    if (row == null) return;
    _rows[id] = AlertDeliveryRecord(
      id: row.id,
      scheduledMs: row.scheduledMs,
      executedMs: row.executedMs ?? atMs,
      notifiedMs: atMs,
      dismissedMs: row.dismissedMs,
      transport: row.transport,
    );
  }

  void recordDismissed(String id, int atMs) {
    final row = _rows[id];
    if (row == null) return;
    _rows[id] = AlertDeliveryRecord(
      id: row.id,
      scheduledMs: row.scheduledMs,
      executedMs: row.executedMs,
      notifiedMs: row.notifiedMs ?? atMs,
      dismissedMs: atMs,
      transport: row.transport,
    );
  }

  void recordTickDurationMs(double ms) {
    if (ms.isFinite && ms >= 0) tickDurationsMs.add(ms);
  }

  void recordResourceSample(AgentResourceSample sample) {
    resourceSamples.add(sample);
  }

  List<AlertDeliveryRecord> get rows => List.unmodifiable(_rows.values);

  int get scheduledCount => _rows.length;

  int get notifiedCount =>
      _rows.values.where((r) => r.notifiedMs != null).length;

  /// Schedule → notify latencies (ms) for notified rows only.
  List<double> get notifyLatenciesMs => _rows.values
      .where((r) => r.notifyLatencyMs != null)
      .map((r) => r.notifyLatencyMs!.toDouble())
      .toList();

  /// Rows scheduled at least [dropAfterMs] ago with no notification:
  /// presumed dropped (transport died, rail rejected, process killed).
  List<AlertDeliveryRecord> drops({
    required int nowMs,
    int dropAfterMs = AlertSlo.deliveryWindowMs,
  }) =>
      _rows.values
          .where((r) =>
              r.notifiedMs == null &&
              nowMs - r.scheduledMs >= dropAfterMs)
          .toList();

  /// Evaluate every Beta.2 alert SLO over the rows held.
  AlertSloReport evaluateSlo({required int nowMs}) {
    final latencies = notifyLatenciesMs;
    final inWindow = latencies.length;
    final inTime = latencies
        .where((l) => l <= AlertSlo.deliveryWindowMs)
        .length;
    final deliveryRate =
        scheduledCount == 0 ? null : inTime / scheduledCount;
    final dropRate = scheduledCount == 0
        ? null
        : drops(nowMs: nowMs).length / scheduledCount;
    final tickP95 = percentile(tickDurationsMs, 0.95);
    final memP95 = percentile(
      resourceSamples
          .where((s) => s.memMb != null)
          .map((s) => s.memMb!)
          .toList(),
      0.95,
    );
    final breaches = <String>[];
    if (deliveryRate != null && deliveryRate < AlertSlo.deliveryTarget) {
      breaches.add('delivery');
    }
    if (dropRate != null && dropRate >= AlertSlo.dropTarget) {
      breaches.add('drops');
    }
    if (tickP95 != null && tickP95 >= AlertSlo.tickP95Ms) {
      breaches.add('tick-p95');
    }
    if (memP95 != null && memP95 >= AlertSlo.agentMemP95Mb) {
      breaches.add('agent-mem-p95');
    }
    return AlertSloReport(
      scheduled: scheduledCount,
      notified: notifiedCount,
      notifiedInWindow: inWindow,
      deliveryRate: deliveryRate,
      dropRate: dropRate,
      tickP95Ms: tickP95,
      agentMemP95Mb: memP95,
      breaches: breaches,
    );
  }
}

/// Frozen Beta.2 alert SLO thresholds (Nadia owns; changes need Rina
/// sign-off — the dashboard spec and `agent_check` pin these values).
abstract class AlertSlo {
  /// 99% of scheduled signals notified within the window.
  static const double deliveryTarget = 0.99;

  /// Delivery window: schedule → notify in 5 min.
  static const int deliveryWindowMs = 5 * 60 * 1000;

  /// Drop budget: strictly below 1% of scheduled signals.
  static const double dropTarget = 0.01;

  /// Tick-cost budget: p95 poll-tick wall time under 2 s.
  static const double tickP95Ms = 2000;

  /// Agent-footprint budget: p95 agent RSS under 50 MB.
  static const double agentMemP95Mb = 50;
}

/// Outcome of one SLO evaluation window.
class AlertSloReport {
  final int scheduled;
  final int notified;
  final int notifiedInWindow;
  final double? deliveryRate;
  final double? dropRate;
  final double? tickP95Ms;
  final double? agentMemP95Mb;

  /// SLO keys in breach: `delivery`, `drops`, `tick-p95`,
  /// `agent-mem-p95`. Empty means all green (or no data).
  final List<String> breaches;

  const AlertSloReport({
    required this.scheduled,
    required this.notified,
    required this.notifiedInWindow,
    required this.deliveryRate,
    required this.dropRate,
    required this.tickP95Ms,
    required this.agentMemP95Mb,
    required this.breaches,
  });

  bool get healthy => breaches.isEmpty;

  Map<String, Object?> toJson() => {
        'scheduled': scheduled,
        'notified': notified,
        'notifiedInWindow': notifiedInWindow,
        'deliveryRate': deliveryRate,
        'dropRate': dropRate,
        'tickP95Ms': tickP95Ms,
        'agentMemP95Mb': agentMemP95Mb,
        'breaches': breaches,
        'healthy': healthy,
      };
}

/// Nearest-rank percentile over [values] (0..1 rank, e.g. 0.95).
/// Returns null when empty; ignores non-finite entries.
double? percentile(List<double> values, double rank) {
  final clean =
      values.where((v) => v.isFinite).toList()..sort();
  if (clean.isEmpty) return null;
  final r = rank.clamp(0.0, 1.0);
  final idx = ((clean.length * r).ceil() - 1)
      .clamp(0, clean.length - 1);
  return clean[idx];
}
