/// APM-lite rollups over per-host metrics history.
///
/// The control center already records one point per poll per host via
/// `MetricsHistory` (cpu/ram/disk 0..1 + latency ms, capped at 120).
/// This service turns those raw points into the tiny APM summary the
/// server detail screen shows: latency p50/p95/max, average saturation,
/// sample count, staleness, and a single A–F grade. Pure logic — no
/// network, no plugins, safe for CI.
class ApmService {
  /// Summarize [points] (maps as written by `MetricsHistory.record`).
  /// Returns null when there are no usable points.
  static ApmSummary? summarize(
    String host,
    List<Map<String, dynamic>> points, {
    DateTime? now,
  }) {
    final lat = <double>[];
    double cpu = 0, ram = 0, disk = 0;
    var usable = 0;
    var newest = 0;
    for (final p in points) {
      final l = (p['lat'] as num?)?.toDouble();
      if (l == null) continue;
      lat.add(l < 0 ? 0 : l);
      cpu += ((p['cpu'] as num?)?.toDouble() ?? 0).clamp(0, 1);
      ram += ((p['ram'] as num?)?.toDouble() ?? 0).clamp(0, 1);
      disk += ((p['disk'] as num?)?.toDouble() ?? 0).clamp(0, 1);
      final t = (p['t'] as num?)?.toInt() ?? 0;
      if (t > newest) newest = t;
      usable++;
    }
    if (usable == 0) return null;
    lat.sort();
    double pct(double q) {
      final idx = ((lat.length * q).ceil() - 1).clamp(0, lat.length - 1);
      return lat[idx];
    }

    final ref = (now ?? DateTime.now()).millisecondsSinceEpoch;
    final ageMin =
        newest <= 0 ? -1 : ((ref - newest) / 60000).floor();
    return ApmSummary(
      host: host,
      samples: usable,
      p50Ms: pct(0.50),
      p95Ms: pct(0.95),
      maxMs: lat.last,
      avgCpu: cpu / usable,
      avgRam: ram / usable,
      avgDisk: disk / usable,
      ageMinutes: ageMin,
      grade: grade(pct(0.95), cpu / usable),
    );
  }

  /// A–F grade from tail latency + average CPU saturation.
  /// F = paging-worthy (p95 > 2s or CPU pinned); C or worse deserves a look.
  static String grade(double p95Ms, double avgCpu) {
    if (p95Ms > 2000 || avgCpu >= 0.95) return 'F';
    if (p95Ms > 800 || avgCpu >= 0.85) return 'C';
    if (p95Ms > 300 || avgCpu >= 0.70) return 'B';
    return 'A';
  }
}

/// Value built by [ApmService.summarize].
class ApmSummary {
  final String host;
  final int samples;
  final double p50Ms;
  final double p95Ms;
  final double maxMs;
  final double avgCpu;
  final double avgRam;
  final double avgDisk;

  /// Minutes since the newest point; -1 when points carry no timestamp.
  final int ageMinutes;
  final String grade;

  /// Stale when the newest point is older than 15 minutes.
  bool get stale => ageMinutes > 15;

  const ApmSummary({
    required this.host,
    required this.samples,
    required this.p50Ms,
    required this.p95Ms,
    required this.maxMs,
    required this.avgCpu,
    required this.avgRam,
    required this.avgDisk,
    required this.ageMinutes,
    required this.grade,
  });

  /// One-line subtitle for the metrics card, e.g. `APM-lite B • p95 210ms`.
  String get headline =>
      'APM-lite $grade • p95 ${_fmt(p95Ms)}${stale ? ' • stale' : ''}';

  static String _fmt(double ms) {
    if (ms < 1000) return '${ms.toStringAsFixed(0)}ms';
    return '${(ms / 1000).toStringAsFixed(2)}s';
  }
}
