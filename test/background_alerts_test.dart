import 'package:flutter_test/flutter_test.dart';
import 'package:my_control_panel/services/background_alerts.dart';
import 'package:my_control_panel/services/polling_alerts.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('BackgroundAlerts constants (store-review + consent contract)', () {
    test('toggle defaults OFF when the pref was never written', () async {
      SharedPreferences.setMockInitialValues({});
      expect(await BackgroundAlerts.isEnabled(), isFalse);
    });

    test('consent copy carries the binding ~15 min wording', () {
      expect(BackgroundAlerts.consentCopy, contains('~15 min'));
      expect(BackgroundAlerts.consentCopy,
          contains('in the background'));
    });

    test('periodic frequency honors the >=15 min OS minimum', () {
      expect(BackgroundAlerts.pollFrequency,
          const Duration(minutes: 15));
    });

    test('iOS task identifier is a stable reverse-DNS string', () {
      expect(BackgroundAlerts.taskName, contains('.backgroundAlerts'));
      expect(BackgroundAlerts.taskName, isNot(contains(' ')));
    });
  });

  group('buildLocalPayload reuses NotificationHook verbatim', () {
    test('empty list yields empty body (nothing to show)', () {
      final p = BackgroundAlerts.buildLocalPayload('t', []);
      expect(p['title'], 't');
      expect(p['body'], '');
    });

    test('blank titles are dropped before the hook', () {
      final p = BackgroundAlerts.buildLocalPayload('t', ['  ', '', 'real']);
      expect(p['body'], 'real');
    });

    test('exactly three titles pass through with no overflow note', () {
      final p =
          BackgroundAlerts.buildLocalPayload('t', ['a', 'b', 'c']);
      expect(p['body'], 'a\nb\nc');
      expect(p['body'], isNot(contains('…and')));
    });

    test('four titles truncate to three with a +1 overflow note', () {
      final p =
          BackgroundAlerts.buildLocalPayload('t', ['a', 'b', 'c', 'd']);
      expect(p['body'], contains('a\nb\nc'));
      expect(p['body'], contains('…and 1 more'));
    });

    test('long overflow lists count the remainder, not the shown', () {
      final titles = List.generate(10, (i) => 'alert-$i');
      final p = BackgroundAlerts.buildLocalPayload('t', titles);
      expect(p['body'], contains('alert-0\nalert-1\nalert-2'));
      expect(p['body'], contains('…and 7 more'));
    });

    test('matches NotificationHook.build output exactly', () {
      const titles = ['a', 'b', 'c', 'd', 'e'];
      expect(BackgroundAlerts.buildLocalPayload('T', titles),
          NotificationHook.build('T', titles));
    });

    test('long titles are preserved verbatim (no shortening)', () {
      const longTitle =
          'CRITICAL disk / on prod-db-01 at 97% for 12m (server prod-db-01)';
      final p = BackgroundAlerts.buildLocalPayload('t', [longTitle]);
      expect(p['body'], longTitle);
    });
  });

  group('formatLastChecked (stale-tolerant UI)', () {
    final now = DateTime(2026, 10, 30, 12, 0, 0);

    test('never checked reads idle, not failed', () {
      expect(
        BackgroundAlerts.formatLastChecked(now: now),
        contains('never checked'),
      );
    });

    test('sub-minute reads just now', () {
      expect(
        BackgroundAlerts.formatLastChecked(
            now: now, last: now.subtract(const Duration(seconds: 30))),
        'last checked just now',
      );
    });

    test('minutes read Xm ago', () {
      expect(
        BackgroundAlerts.formatLastChecked(
            now: now, last: now.subtract(const Duration(minutes: 16))),
        'last checked 16 min ago',
      );
    });

    test('hours read Xh ago', () {
      expect(
        BackgroundAlerts.formatLastChecked(
            now: now, last: now.subtract(const Duration(hours: 3))),
        'last checked 3 hr ago',
      );
    });

    test('days read Xd ago', () {
      expect(
        BackgroundAlerts.formatLastChecked(
            now: now, last: now.subtract(const Duration(days: 2))),
        'last checked 2 days ago',
      );
    });

    test('future stamps (clock skew) read just now, never negative', () {
      expect(
        BackgroundAlerts.formatLastChecked(
            now: now, last: now.add(const Duration(minutes: 5))),
        'last checked just now',
      );
    });
  });

  group('policy reuse (no new payload formats)', () {
    test('background frequency is >= the PollPolicy base interval', () {
      // The OS minimum (15 min) must never poll hotter than the foreground
      // backoff base (5 min) contract assumes.
      const policy = PollPolicy();
      expect(BackgroundAlerts.pollFrequency.inSeconds,
          greaterThanOrEqualTo(policy.baseInterval.inSeconds));
    });

    test('thresholds evaluate the documented disk tripwires', () {
      const t = Thresholds();
      expect(t.evaluate(0.79), AlertSeverity.ok);
      expect(t.evaluate(0.85), AlertSeverity.warning);
      expect(t.evaluate(0.95), AlertSeverity.critical);
    });
  });
}
