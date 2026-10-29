import 'package:flutter_test/flutter_test.dart';
import 'package:my_control_panel/models/alert_entry.dart';
import 'package:my_control_panel/services/alert_pipeline.dart';
import 'package:my_control_panel/services/anomaly_baseline.dart';
import 'package:my_control_panel/services/forecast_alerts.dart';

/// Disk filling at +1%/h from 60%: crosses 80% in ~20h, 90% in ~30h.
List<TrendPoint> fillingDisk() =>
    List.generate(48, (i) => TrendPoint(i.toDouble(), 0.60 + 0.01 * i));

List<TrendPoint> flatDisk() =>
    List.generate(48, (i) => TrendPoint(i.toDouble(), 0.40));

AlertPipeline pipeline() => AlertPipeline(
      serverId: 's1',
      serverName: 'prod-core-01',
      loadForecaster: LoadSpikeForecaster(minHistory: 5),
      cpuBaseline: AnomalyBaseline('s1/cpu', window: 10, minHistory: 5),
    );

List<String> _titles(List<AlertEntry> alerts) =>
    alerts.map((a) => a.title).toList();

void main() {
  group('AlertPipeline', () {
    test('filling disk emits critical ETA hook + notify', () {
      final p = pipeline();
      final notes = <String>[];
      final out = p.evaluate(
        diskHistory: fillingDisk(),
        load1: 0.5,
        cpuSample: 0.2,
        nowMs: 0,
        onNotify: (t, b) => notes.add(t),
      );
      expect(_titles(out).any((t) => t.contains('90%')), isTrue);
      expect(notes, isNotEmpty);
    });

    test('quiet host emits nothing', () {
      final p = pipeline();
      final out = p.evaluate(
        diskHistory: flatDisk(),
        load1: 0.5,
        cpuSample: 0.2,
        nowMs: 0,
      );
      expect(out, isEmpty);
    });

    test('load spike emits warning hook', () {
      final p = pipeline();
      for (var i = 0; i < 6; i++) {
        p.evaluate(
            diskHistory: flatDisk(), load1: 0.5, cpuSample: 0.2, nowMs: i);
      }
      final out = p.evaluate(
          diskHistory: flatDisk(), load1: 4.0, cpuSample: 0.2, nowMs: 6);
      expect(_titles(out).any((t) => t.contains('Load spike')), isTrue);
    });

    test('cpu anomaly emits warning hook', () {
      final p = pipeline();
      for (var i = 0; i < 6; i++) {
        p.evaluate(
            diskHistory: flatDisk(), load1: 0.5, cpuSample: 0.2, nowMs: i);
      }
      final out = p.evaluate(
          diskHistory: flatDisk(), load1: 0.5, cpuSample: 0.95, nowMs: 6);
      expect(_titles(out).any((t) => t.contains('CPU anomaly')), isTrue);
    });

    test('cooldown dedups repeats, expiry re-emits', () {
      final p = pipeline();
      final first = p.evaluate(
          diskHistory: fillingDisk(), load1: 0.5, cpuSample: 0.2, nowMs: 0);
      expect(first, isNotEmpty);
      final dup = p.evaluate(
          diskHistory: fillingDisk(), load1: 0.5, cpuSample: 0.2, nowMs: 1000);
      expect(
          dup.where((a) => a.source == 'ml-pipeline/disk'), isEmpty);
      final later = p.evaluate(
        diskHistory: fillingDisk(),
        load1: 0.5,
        cpuSample: 0.2,
        nowMs: 7 * 3600 * 1000,
      );
      expect(later.where((a) => a.source == 'ml-pipeline/disk'), isNotEmpty);
    });
  });
}
