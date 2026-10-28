/// Predictive disk/load alerting — trend + p95 forecasts for 80/90% disk
/// usage and load spikes (Metrics & Uptime + Alerts).
///
/// Dependency-light by design: `dart:math` only, no new pubspec entries.
/// Operates on the capped on-device [MetricsHistory] series (or any list
/// of timestamped points):
/// - [DiskForecaster]: least-squares trend on disk usage -> ETA (hours)
///   to the 80% (warning) and 90% (critical) lines. Returns null when the
///   trend is flat/negative (no breach coming).
/// - [LoadSpikeForecaster]: EWMA + median gate — flags when the short EWMA
///   exceeds `max(absoluteFloor, median * ratio)`, i.e. load is spiking
///   relative to its own recent history, not a fixed number.
/// - [percentile]: shared p95/p99 helper (same nearest-rank method as
///   `MetricsHistory.p95`, duplicated here to keep this module import-free
///   of plugins).
///
/// Production wiring (for Nadia): run after each agent poll using the last
/// N points from `MetricsHistory.read(host)`; emit early-warning alerts
/// (`disk 90% in ~Xh`, `load spiking`) with lower severity than firing
/// alerts so the UI can show "upcoming" vs "now".
library;

/// One timestamped sample. `tHours` = hours since any fixed epoch.
class TrendPoint {
  final double tHours;
  final double value;

  const TrendPoint(this.tHours, this.value);
}

/// Nearest-rank percentile over [values] (0..1 ratios or ms — unit-free).
/// Returns null when empty.
double? percentile(List<double> values, double p) {
  if (values.isEmpty) return null;
  final q = p.clamp(0.0, 1.0);
  final sorted = List.of(values)..sort();
  final idx = ((sorted.length * q).ceil() - 1).clamp(0, sorted.length - 1);
  return sorted[idx];
}

/// Forecast of when disk usage crosses warning/critical lines.
class DiskForecast {
  /// Hours until 80% at the current trend; null = no breach coming.
  final double? hoursToWarn;
  /// Hours until 90% at the current trend; null = no breach coming.
  final double? hoursToCritical;
  /// Fitted growth rate in ratio-points per hour (e.g. 0.005 = +0.5%/h).
  final double slopePerHour;
  /// Coefficient of determination — low R² means the trend is noise.
  final double rSquared;

  const DiskForecast({
    required this.hoursToWarn,
    required this.hoursToCritical,
    required this.slopePerHour,
    required this.rSquared,
  });
}

/// Least-squares disk-growth forecaster.
class DiskForecaster {
  static const double warnLine = 0.80;
  static const double criticalLine = 0.90;

  /// Minimum R² to trust the trend; below it, no ETA is emitted.
  final double minRSquared;

  /// Minimum history points for a fit.
  final int minHistory;

  const DiskForecaster({this.minRSquared = 0.5, this.minHistory = 8});

  DiskForecast forecast(List<TrendPoint> points) {
    if (points.length < minHistory) {
      return const DiskForecast(
        hoursToWarn: null, hoursToCritical: null,
        slopePerHour: 0, rSquared: 0,
      );
    }
    final n = points.length;
    var sx = 0.0, sy = 0.0, sxx = 0.0, sxy = 0.0;
    for (final p in points) {
      sx += p.tHours;
      sy += p.value;
    }
    final mx = sx / n, my = sy / n;
    for (final p in points) {
      final dx = p.tHours - mx;
      sxx += dx * dx;
      sxy += dx * (p.value - my);
    }
    if (sxx < 1e-12) {
      return const DiskForecast(
        hoursToWarn: null, hoursToCritical: null,
        slopePerHour: 0, rSquared: 0,
      );
    }
    final slope = sxy / sxx;
    final intercept = my - slope * mx;
    var ssTot = 0.0, ssRes = 0.0;
    for (final p in points) {
      ssTot += (p.value - my) * (p.value - my);
      final f = slope * p.tHours + intercept;
      ssRes += (p.value - f) * (p.value - f);
    }
    final r2 = ssTot < 1e-12 ? 0.0 : (1 - ssRes / ssTot).clamp(0.0, 1.0);
    final last = points.last;
    double? eta(double line) {
      if (slope <= 1e-9 || r2 < minRSquared) return null;
      if (last.value >= line) return 0.0; // already over
      return (line - last.value) / slope;
    }
    return DiskForecast(
      hoursToWarn: eta(warnLine),
      hoursToCritical: eta(criticalLine),
      slopePerHour: slope,
      rSquared: r2,
    );
  }
}

/// Verdict for the latest load sample.
enum LoadVerdict { ok, warmup, spiking }

/// EWMA + median load-spike forecaster.
///
/// `spiking` when `ewmaFast > max(absoluteFloor, median(history) * ratio)`.
/// The median term adapts to each host (a 4-core box idles higher than a
/// 64-core one) yet stays robust while a spike persists — unlike a p95
/// gate, which the spike itself poisons within a few samples. The
/// absolute floor prevents noise-flagging near idle. Pair with
/// [percentile] (p95) for display-ranked "how unusual" context.
class LoadSpikeForecaster {
  final int minHistory;
  final double alphaFast;
  final double ratio;
  final double absoluteFloor;

  double? _ewma;
  final List<double> _hist = [];

  LoadSpikeForecaster({
    this.minHistory = 15,
    this.alphaFast = 0.35,
    this.ratio = 1.8,
    this.absoluteFloor = 1.0,
  });

  LoadVerdict update(double load1) {
    _ewma = _ewma == null ? load1 : alphaFast * load1 + (1 - alphaFast) * _ewma!;
    if (_hist.length < minHistory) {
      _hist.add(load1);
      return LoadVerdict.warmup;
    }
    // Gate from past-only history so the spike being judged cannot move it.
    // Median (not p95): robust while a sustained spike fills the window.
    final med = percentile(_hist, 0.5) ?? 0.0;
    double gate = med * ratio;
    if (gate < absoluteFloor) gate = absoluteFloor;
    final verdict = _ewma! > gate ? LoadVerdict.spiking : LoadVerdict.ok;
    _hist.add(load1);
    return verdict;
  }

  double? get ewma => _ewma;
  int get historyLength => _hist.length;
}
