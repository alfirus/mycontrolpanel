import 'package:flutter_test/flutter_test.dart';
import 'package:my_control_panel/services/polling_alerts.dart';

void main() {
  group('PollPolicy', () {
    const policy = PollPolicy(
      baseInterval: Duration(minutes: 5),
      maxInterval: Duration(hours: 1),
    );

    test('success streak polls at base interval', () {
      expect(policy.nextDelay(0), const Duration(minutes: 5));
      expect(policy.nextDelay(-2), const Duration(minutes: 5));
    });

    test('failures double the wait', () {
      expect(policy.nextDelay(1), const Duration(minutes: 10));
      expect(policy.nextDelay(2), const Duration(minutes: 20));
      expect(policy.nextDelay(3), const Duration(minutes: 40));
    });

    test('wait caps at maxInterval', () {
      expect(policy.nextDelay(4), const Duration(hours: 1));
      expect(policy.nextDelay(99), const Duration(hours: 1));
    });
  });

  group('Thresholds', () {
    const t = Thresholds();

    test('boundaries map to ok/warning/critical', () {
      expect(t.evaluate(0.5), AlertSeverity.ok);
      expect(t.evaluate(0.849), AlertSeverity.ok);
      expect(t.evaluate(0.85), AlertSeverity.warning);
      expect(t.evaluate(0.949), AlertSeverity.warning);
      expect(t.evaluate(0.95), AlertSeverity.critical);
      expect(t.evaluate(1.0), AlertSeverity.critical);
    });
  });

  group('Slo', () {
    test('uptime fraction over a window', () {
      expect(Slo.uptimePct(99, 100), closeTo(0.99, 1e-9));
      expect(Slo.uptimePct(0, 10), 0.0);
      expect(Slo.uptimePct(10, 10), 1.0);
    });

    test('empty window and clamping', () {
      expect(Slo.uptimePct(0, 0), isNull);
      expect(Slo.uptimePct(12, 10), 1.0);
      expect(Slo.uptimePct(-3, 10), 0.0);
    });

    test('breach evaluation', () {
      expect(Slo.breaches(0.989, 0.99), isTrue);
      expect(Slo.breaches(0.99, 0.99), isFalse);
      expect(Slo.breaches(null, 0.99), isFalse);
    });
  });

  group('NotificationHook', () {
    test('empty list yields empty body', () {
      final p = NotificationHook.build('Alerts', []);
      expect(p['body'], '');
    });

    test('caps at three items with overflow note', () {
      final p = NotificationHook.build('Alerts', ['a', 'b', 'c', 'd', 'e']);
      expect(p['body'], contains('a\nb\nc'));
      expect(p['body'], contains('…and 2 more'));
    });

    test('short lists pass through untouched', () {
      final p = NotificationHook.build('Alerts', ['a', 'b']);
      expect(p['body'], 'a\nb');
    });
  });
}
