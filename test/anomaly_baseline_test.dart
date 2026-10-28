import 'package:flutter_test/flutter_test.dart';
import 'package:my_control_panel/services/anomaly_baseline.dart';

/// Deterministic pseudo-normal series (fixed seed pattern, no randomness).
List<double> steady({int n = 40, double base = 0.30, double amp = 0.02}) {
  return List.generate(n, (i) => base + amp * ((i * 37 % 11) / 11 - 0.5));
}

void main() {
  group('RollingStats', () {
    test('mean and std match textbook values', () {
      final s = RollingStats();
      for (final v in [2.0, 4.0, 4.0, 4.0, 5.0, 5.0, 7.0, 9.0]) {
        s.add(v);
      }
      expect(s.mean, closeTo(5.0, 1e-9));
      expect(s.std, closeTo(2.138, 1e-3));
    });
  });

  group('MadDetector', () {
    test('warmup until minHistory, then ok on steady data', () {
      final d = MadDetector(minHistory: 10);
      var warmups = 0;
      for (final v in steady(n: 10)) {
        if (d.check(v).verdict == AnomalyVerdict.warmup) warmups++;
      }
      expect(warmups, 10);
      expect(d.check(0.30).isAnomaly, isFalse);
    });

    test('flags a cpu spike to 0.95', () {
      final d = MadDetector(minHistory: 10);
      for (final v in steady(n: 30)) {
        d.check(v);
      }
      final r = d.check(0.95);
      expect(r.isAnomaly, isTrue);
      expect(r.baseline, closeTo(0.30, 0.05));
    });

    test('single spike does not poison the baseline (robust)', () {
      final d = MadDetector(minHistory: 10);
      for (final v in steady(n: 30)) {
        d.check(v);
      }
      d.check(0.99); // one-off spike
      // Steady traffic right after must still be ok.
      expect(d.check(0.30).isAnomaly, isFalse);
      expect(d.check(0.31).isAnomaly, isFalse);
    });
  });

  group('ZScoreDetector', () {
    test('flags sustained level shift', () {
      final z = ZScoreDetector(minHistory: 10, zThreshold: 3.0);
      for (final v in steady(n: 30)) {
        z.check(v);
      }
      // A hard level shift far outside jitter should trip z-score.
      final r = z.check(0.90);
      expect(r.isAnomaly, isTrue);
    });
  });

  group('AnomalyBaseline', () {
    test('per-metric wrapper learns then detects', () {
      final b = AnomalyBaseline('prod-core-01/cpu', minHistory: 10);
      for (final v in steady(n: 30)) {
        b.update(v);
      }
      expect(b.update(0.30).isAnomaly, isFalse);
      expect(b.update(0.97).isAnomaly, isTrue);
    });
  });
}
