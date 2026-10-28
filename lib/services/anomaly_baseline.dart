/// Metrics anomaly detection — unsupervised baselines for
/// cpu/ram/disk/load/latency to replace static thresholds.
///
/// Dependency-light by design: `dart:math` only, no new pubspec entries.
/// Two complementary detectors run over the on-device [MetricsHistory]
/// series (or any list of doubles):
/// - [ZScoreDetector]: Welford rolling mean/std, flags |z| >= threshold.
/// - [MadDetector]: robust median/MAD baseline, immune to single spikes
///   poisoning the mean — the preferred default for bursty server metrics.
///
/// [AnomalyBaseline] wraps one named metric with warmup gating so alerts
/// only fire after enough history exists. Pure functions + tiny state:
/// trivially unit-testable, no timers, no I/O.
///
/// Production wiring (for Nadia): feed each agent poll into
/// `AnomalyBaseline.update`, and route `check()` results into the Alerts
/// engine alongside the existing static-threshold rules.
library;

import 'dart:math';

/// Verdict for one fresh sample.
enum AnomalyVerdict { ok, warmup, anomaly }

/// Result of checking one sample against a baseline.
class AnomalyResult {
  final AnomalyVerdict verdict;
  final double score;
  final double baseline;
  final double deviation;

  const AnomalyResult(this.verdict, this.score, this.baseline, this.deviation);

  bool get isAnomaly => verdict == AnomalyVerdict.anomaly;
}

/// Rolling mean/variance via Welford's online algorithm.
class RollingStats {
  int n = 0;
  double mean = 0.0;
  double _m2 = 0.0;

  void add(double x) {
    n++;
    final d = x - mean;
    mean += d / n;
    _m2 += d * (x - mean);
  }

  double get variance => n < 2 ? 0.0 : _m2 / (n - 1);
  double get std => sqrt(max(0.0, variance));
}

/// Z-score detector over a sliding window.
class ZScoreDetector {
  final int window;
  final double zThreshold;
  final int minHistory;
  final List<double> _hist = [];

  ZScoreDetector({this.window = 60, this.zThreshold = 3.0, this.minHistory = 15});

  AnomalyResult check(double value) {
    if (_hist.length < minHistory) {
      _hist.add(value);
      return AnomalyResult(AnomalyVerdict.warmup, 0, value, 0);
    }
    final stats = RollingStats();
    for (final v in _hist) {
      stats.add(v);
    }
    final std = stats.std;
    final z = std < 1e-9 ? 0.0 : (value - stats.mean) / std;
    _hist.add(value);
    if (_hist.length > window) _hist.removeAt(0);
    if (z.abs() >= zThreshold) {
      return AnomalyResult(AnomalyVerdict.anomaly, z.abs(), stats.mean, z);
    }
    return AnomalyResult(AnomalyVerdict.ok, z.abs(), stats.mean, z);
  }

  int get historyLength => _hist.length;
}

/// Median/MAD robust detector — flags modified z-score outliers.
class MadDetector {
  final int window;
  final double threshold;
  final int minHistory;
  final List<double> _hist = [];

  MadDetector({this.window = 60, this.threshold = 3.5, this.minHistory = 15});

  static double median(List<double> xs) {
    if (xs.isEmpty) return 0;
    final s = List.of(xs)..sort();
    final m = s.length ~/ 2;
    return s.length.isOdd ? s[m] : (s[m - 1] + s[m]) / 2;
  }

  AnomalyResult check(double value) {
    if (_hist.length < minHistory) {
      _hist.add(value);
      return AnomalyResult(AnomalyVerdict.warmup, 0, value, 0);
    }
    final med = median(_hist);
    final deviations = _hist.map((v) => (v - med).abs()).toList();
    final mad = median(deviations);
    // Modified z-score (Iglewicz & Hoaglin): 0.6745*(x-med)/MAD.
    final denom = mad < 1e-9 ? 1e-9 : mad;
    final mz = 0.6745 * (value - med) / denom;
    _hist.add(value);
    if (_hist.length > window) _hist.removeAt(0);
    if (mz.abs() >= threshold) {
      return AnomalyResult(AnomalyVerdict.anomaly, mz.abs(), med, mz);
    }
    return AnomalyResult(AnomalyVerdict.ok, mz.abs(), med, mz);
  }

  int get historyLength => _hist.length;
}

/// One named metric (e.g. `prod-core-01/cpu`) with a robust default.
///
/// Combines both detectors: MAD is authoritative (robust to spike
/// poisoning); the z-score detector is consulted and its score is exposed
/// for ranking/surfacing in the Alerts UI.
class AnomalyBaseline {
  final String name;
  final MadDetector mad;
  final ZScoreDetector zscore;

  AnomalyBaseline(this.name, {int window = 60, int minHistory = 15})
      : mad = MadDetector(window: window, minHistory: minHistory),
        zscore = ZScoreDetector(window: window, minHistory: minHistory);

  AnomalyResult update(double value) {
    final m = mad.check(value);
    zscore.check(value);
    return m;
  }
}
