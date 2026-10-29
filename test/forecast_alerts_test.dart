import 'package:flutter_test/flutter_test.dart';
import 'package:my_control_panel/services/forecast_alerts.dart';

/// Disk filling at +1%/h starting from 60%: crosses 80% in ~20h, 90% in ~30h.
List<TrendPoint> fillingDisk() {
  return List.generate(48, (i) => TrendPoint(i.toDouble(), 0.60 + 0.01 * i));
}

void main() {
  group('percentile', () {
    test('p95 matches nearest-rank', () {
      final xs = List.generate(100, (i) => (i + 1).toDouble());
      expect(percentile(xs, 0.95), 95.0);
    });
    test('empty returns null', () {
      expect(percentile(const [], 0.95), isNull);
    });
  });

  group('DiskForecaster', () {
    test('predicts ETA to 80/90% on a steady fill', () {
      const f = DiskForecaster();
      final fc = f.forecast(fillingDisk());
      expect(fc.slopePerHour, closeTo(0.01, 1e-9));
      expect(fc.rSquared, closeTo(1.0, 1e-9));
      // Last point: 0.60+0.47=1.07 — already over both lines.
      expect(fc.hoursToWarn, 0.0);
      expect(fc.hoursToCritical, 0.0);
    });

    test('mid-fill ETA is roughly right', () {
      const f = DiskForecaster();
      final pts = List.generate(24, (i) => TrendPoint(i.toDouble(), 0.60 + 0.005 * i));
      final fc = f.forecast(pts);
      // Last value 0.715; 0.085 to go at 0.005/h -> ~17h to 80%.
      expect(fc.hoursToWarn, closeTo(17.0, 0.5));
      // 0.185 to 90% -> ~37h.
      expect(fc.hoursToCritical, closeTo(37.0, 0.5));
    });

    test('flat disk emits no ETA', () {
      const f = DiskForecaster();
      final pts = List.generate(24, (i) => TrendPoint(i.toDouble(), 0.42));
      final fc = f.forecast(pts);
      expect(fc.hoursToWarn, isNull);
      expect(fc.hoursToCritical, isNull);
    });

    test('shrinking disk emits no ETA', () {
      const f = DiskForecaster();
      final pts = List.generate(24, (i) => TrendPoint(i.toDouble(), 0.70 - 0.002 * i));
      final fc = f.forecast(pts);
      expect(fc.hoursToWarn, isNull);
      expect(fc.hoursToCritical, isNull);
    });

    test('too little history yields null ETAs', () {
      const f = DiskForecaster();
      final fc = f.forecast(const [TrendPoint(0, 0.5), TrendPoint(1, 0.6)]);
      expect(fc.hoursToWarn, isNull);
    });
  });

  group('LoadSpikeForecaster', () {
    test('warmup then ok on steady load', () {
      final f = LoadSpikeForecaster(minHistory: 10);
      var warm = 0;
      for (var i = 0; i < 10; i++) {
        if (f.update(0.4) == LoadVerdict.warmup) warm++;
      }
      expect(warm, 10);
      expect(f.update(0.4), LoadVerdict.ok);
    });

    test('flags a sudden 8x spike', () {
      final f = LoadSpikeForecaster(minHistory: 10);
      for (var i = 0; i < 20; i++) {
        f.update(0.5);
      }
      // median ~0.5 -> gate max(1.0, 0.9)=1.0; EWMA climbs toward 4.
      var verdict = LoadVerdict.ok;
      for (var i = 0; i < 6; i++) {
        verdict = f.update(4.0);
      }
      expect(verdict, LoadVerdict.spiking);
    });

    test('idle jitter does not spike', () {
      final f = LoadSpikeForecaster(minHistory: 10);
      for (var i = 0; i < 20; i++) {
        f.update(0.1 + (i % 3) * 0.05);
      }
      expect(f.update(0.2), LoadVerdict.ok);
    });
  });
}
