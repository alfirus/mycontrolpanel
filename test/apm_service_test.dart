import 'package:flutter_test/flutter_test.dart';
import 'package:my_control_panel/services/apm_service.dart';

Map<String, dynamic> pt(int minAgo, double lat,
        {double cpu = 0.2, double ram = 0.3, double disk = 0.4}) =>
    {
      't': DateTime(2026, 10, 28, 12, 0)
          .subtract(Duration(minutes: minAgo))
          .millisecondsSinceEpoch,
      'cpu': cpu,
      'ram': ram,
      'disk': disk,
      'lat': lat,
    };

void main() {
  group('ApmService.summarize', () {
    test('computes latency percentiles over points', () {
      final points = [for (var i = 1; i <= 20; i++) pt(20 - i, i * 10.0)];
      final s = ApmService.summarize('h', points,
          now: DateTime(2026, 10, 28, 12, 0))!;
      expect(s.samples, 20);
      expect(s.p50Ms, 100.0);
      expect(s.p95Ms, 190.0);
      expect(s.maxMs, 200.0);
    });

    test('averages saturation and reports freshness', () {
      final points = [pt(2, 50, cpu: 0.8, ram: 0.9, disk: 0.1)];
      final s = ApmService.summarize('h', points,
          now: DateTime(2026, 10, 28, 12, 0))!;
      expect(s.avgCpu, 0.8);
      expect(s.avgRam, 0.9);
      expect(s.avgDisk, 0.1);
      expect(s.stale, isFalse);
      expect(s.ageMinutes, 2);
    });

    test('flags stale histories', () {
      final points = [pt(60, 50)];
      final s = ApmService.summarize('h', points,
          now: DateTime(2026, 10, 28, 12, 0))!;
      expect(s.stale, isTrue);
      expect(s.headline, contains('stale'));
    });

    test('ignores points without latency', () {
      final s = ApmService.summarize('h', [
        {'t': 1, 'cpu': 0.9},
        pt(1, 40),
      ], now: DateTime(2026, 10, 28, 12, 0))!;
      expect(s.samples, 1);
      expect(s.p50Ms, 40.0);
    });

    test('returns null when nothing is usable', () {
      expect(ApmService.summarize('h', []), isNull);
      expect(
          ApmService.summarize('h', [
            {'t': 1}
          ]),
          isNull);
    });

    test('headline formats sub-second and multi-second tails', () {
      final fast = ApmService.summarize('h', [pt(1, 210)],
          now: DateTime(2026, 10, 28, 12, 0))!;
      expect(fast.headline, contains('p95 210ms'));
      final slow = ApmService.summarize('h', [pt(1, 1500)],
          now: DateTime(2026, 10, 28, 12, 0))!;
      expect(slow.headline, contains('p95 1.50s'));
    });
  });

  group('ApmService.grade', () {
    test('A for healthy hosts', () {
      expect(ApmService.grade(120, 0.3), 'A');
    });

    test('B for warm tails or load', () {
      expect(ApmService.grade(500, 0.3), 'B');
      expect(ApmService.grade(120, 0.75), 'B');
    });

    test('C for hot tails or high saturation', () {
      expect(ApmService.grade(900, 0.3), 'C');
      expect(ApmService.grade(120, 0.9), 'C');
    });

    test('F for paging-worthy states', () {
      expect(ApmService.grade(2500, 0.3), 'F');
      expect(ApmService.grade(120, 0.97), 'F');
    });
  });
}
