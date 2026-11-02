// SPDX-License-Identifier: MIT
import 'package:flutter_test/flutter_test.dart';
import 'package:my_control_panel/services/alert_reliability.dart';

void main() {
  group('AlertDeliveryRecord', () {
    test('stage advances through the lifecycle', () {
      const row = AlertDeliveryRecord(id: 'alert::web::disk', scheduledMs: 1000);
      expect(row.stage, AlertLifecycleStage.scheduled);

      final tracker = AlertReliabilityTracker()
        ..recordScheduled('alert::web::disk', 1000, transport: 'both');
      expect(tracker.rows.single.stage, AlertLifecycleStage.scheduled);
      tracker.recordExecuted('alert::web::disk', 1100);
      expect(tracker.rows.single.stage, AlertLifecycleStage.executed);
      tracker.recordNotified('alert::web::disk', 1200);
      expect(tracker.rows.single.stage, AlertLifecycleStage.notified);
      expect(tracker.rows.single.notifyLatencyMs, 200);
      tracker.recordDismissed('alert::web::disk', 1300);
      expect(tracker.rows.single.stage, AlertLifecycleStage.dismissed);
    });

    test('unknown ids are ignored, never fatal', () {
      final tracker = AlertReliabilityTracker()
        ..recordExecuted('ghost', 1000)
        ..recordNotified('ghost', 1000)
        ..recordDismissed('ghost', 1000);
      expect(tracker.scheduledCount, 0);
    });

    test('chronology guard rejects backwards rows', () {
      const bad = AlertDeliveryRecord(
        id: 'x',
        scheduledMs: 2000,
        executedMs: 1000,
      );
      expect(bad.isChronologySane, isFalse);
      const good = AlertDeliveryRecord(
        id: 'x',
        scheduledMs: 1000,
        executedMs: 1100,
        notifiedMs: 1200,
        dismissedMs: 1300,
      );
      expect(good.isChronologySane, isTrue);
    });

    test('json round-trip preserves the lifecycle', () {
      const row = AlertDeliveryRecord(
        id: 'ci::prod::api 1.2',
        scheduledMs: 1000,
        executedMs: 1100,
        notifiedMs: 1200,
        transport: 'ssh',
      );
      final back = AlertDeliveryRecord.tryFromJson(row.toJson());
      expect(back?.id, row.id);
      expect(back?.notifyLatencyMs, 200);
      expect(back?.transport, 'ssh');
    });

    test('lenient parse skips hostile rows', () {
      expect(AlertDeliveryRecord.tryFromJson({}), isNull);
      expect(
        AlertDeliveryRecord.tryFromJson({'id': '', 'scheduledMs': 1}),
        isNull,
      );
      expect(
        AlertDeliveryRecord.tryFromJson(
            {'id': 'x', 'scheduledMs': double.nan}),
        isNull,
      );
      expect(
        AlertDeliveryRecord.tryFromJson(
            {'id': 'x', 'scheduledMs': 1, 'transport': 42})?.transport,
        'none',
      );
    });
  });

  group('drops', () {
    test('un-notified rows past the window count as drops', () {
      final tracker = AlertReliabilityTracker()
        ..recordScheduled('a', 0)
        ..recordScheduled('b', 0)
        ..recordScheduled('c', 0);
      tracker.recordNotified('a', 60 * 1000);
      final drops = tracker.drops(nowMs: AlertSlo.deliveryWindowMs + 1);
      expect(drops.map((r) => r.id), containsAll(['b', 'c']));
      expect(drops.map((r) => r.id), isNot(contains('a')));
    });

    test('recent un-notified rows are not drops yet', () {
      final tracker = AlertReliabilityTracker()
        ..recordScheduled('fresh', 590 * 1000);
      expect(
        tracker.drops(nowMs: 600 * 1000),
        isEmpty,
      );
    });
  });

  group('percentile', () {
    test('empty input yields null', () {
      expect(percentile([], 0.95), isNull);
    });

    test('nearest-rank p95 matches MetricsHistory convention', () {
      final values = List.generate(20, (i) => (i + 1).toDouble());
      expect(percentile(values, 0.95), 19.0);
      expect(percentile(values, 0.5), 10.0);
    });

    test('ignores non-finite entries', () {
      expect(
        percentile([1.0, double.nan, double.infinity, 2.0], 0.95),
        2.0,
      );
    });
  });

  group('AlertSlo evaluation', () {
    test('empty window is healthy with null rates', () {
      final report = AlertReliabilityTracker().evaluateSlo(nowMs: 0);
      expect(report.healthy, isTrue);
      expect(report.deliveryRate, isNull);
      expect(report.dropRate, isNull);
    });

    test('perfect delivery is green', () {
      final tracker = AlertReliabilityTracker();
      for (var i = 0; i < 100; i++) {
        tracker
          ..recordScheduled('s$i', 0)
          ..recordNotified('s$i', 60 * 1000);
      }
      tracker.recordTickDurationMs(120);
      tracker.recordResourceSample(
        const AgentResourceSample(memMb: 20, atMs: 1),
      );
      final report = tracker.evaluateSlo(nowMs: 400 * 1000);
      expect(report.deliveryRate, 1.0);
      expect(report.dropRate, 0.0);
      expect(report.healthy, isTrue);
    });

    test('delivery under 99% breaches, drops at 1% breach', () {
      final tracker = AlertReliabilityTracker();
      for (var i = 0; i < 100; i++) {
        tracker.recordScheduled('s$i', 0);
        if (i < 98) tracker.recordNotified('s$i', 60 * 1000);
      }
      final report = tracker.evaluateSlo(nowMs: 400 * 1000);
      expect(report.deliveryRate, closeTo(0.98, 1e-9));
      expect(report.dropRate, closeTo(0.02, 1e-9));
      expect(report.breaches, containsAll(['delivery', 'drops']));
      expect(report.healthy, isFalse);
    });

    test('slow ticks and fat agent breach their budgets', () {
      final tracker = AlertReliabilityTracker()
        ..recordScheduled('s', 0)
        ..recordNotified('s', 1000);
      for (var i = 0; i < 20; i++) {
        tracker.recordTickDurationMs(2500);
        tracker.recordResourceSample(
          AgentResourceSample(memMb: 80, atMs: i),
        );
      }
      final report = tracker.evaluateSlo(nowMs: 400 * 1000);
      expect(report.breaches, containsAll(['tick-p95', 'agent-mem-p95']));
    });

    test('late notify counts against delivery but not as a drop', () {
      final tracker = AlertReliabilityTracker()
        ..recordScheduled('late', 0)
        ..recordNotified('late', AlertSlo.deliveryWindowMs + 1000);
      final report = tracker.evaluateSlo(
        nowMs: AlertSlo.deliveryWindowMs + 2000,
      );
      expect(report.deliveryRate, 0.0);
      expect(report.dropRate, 0.0);
      expect(report.breaches, contains('delivery'));
      expect(report.breaches, isNot(contains('drops')));
    });
  });
}
