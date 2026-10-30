import 'package:flutter_test/flutter_test.dart';
import 'package:my_control_panel/services/background_alerts.dart';
import 'package:my_control_panel/services/desktop_alerts.dart';
import 'package:my_control_panel/services/polling_alerts.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('DesktopAlerts platform plumbing (beta.1 in-app timer path)', () {
    test('win_toast identity is stable and well-formed', () {
      expect(DesktopAlerts.appName, 'MyControlPanel');
      expect(DesktopAlerts.windowsAppUserModelId, contains('.'));
      expect(DesktopAlerts.windowsAppUserModelId, isNot(contains(' ')));
      // Stable COM guid: 8-4-4-4-12 hex.
      final guid = DesktopAlerts.windowsGuid;
      expect(
        RegExp(r'^[0-9a-fA-F]{8}(-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}$')
            .hasMatch(guid),
        isTrue,
      );
    });

    test('Linux notify-send default action is named', () {
      expect(DesktopAlerts.linuxDefaultActionName.trim(), isNotEmpty);
    });

    test('closed-app stub defers to tray-mode work (no scheduler wiring)',
        () {
      final note = DesktopAlerts.closedAppNote;
      expect(note, contains('tray-mode'));
      expect(note, contains('Task Scheduler'));
      expect(note, contains('systemd'));
      expect(note, contains('LaunchAgent'));
      expect(note, contains('in-app timer'));
    });
  });

  group('DesktopAlerts consent (shared toggle, default OFF)', () {
    test('reuses the mobile pref key — no second desktop toggle', () {
      // There is exactly one consent pref; adding a desktop-only key would
      // fork the contract this test pins.
      expect(BackgroundAlerts.prefEnabledKey, 'background_alerts');
    });

    test('toggle defaults OFF when the pref was never written', () async {
      SharedPreferences.setMockInitialValues({});
      expect(await DesktopAlerts.isEnabled(), isFalse);
    });

    test('opt-in is honored through the shared pref', () async {
      SharedPreferences.setMockInitialValues(
          {BackgroundAlerts.prefEnabledKey: true});
      expect(await DesktopAlerts.isEnabled(), isTrue);
    });

    test('showFresh stays silent while consent is OFF', () async {
      SharedPreferences.setMockInitialValues({});
      expect(await DesktopAlerts.showFresh(['disk / at 97%']), isFalse);
    });

    test('showFresh stays silent with no fresh titles', () async {
      SharedPreferences.setMockInitialValues(
          {BackgroundAlerts.prefEnabledKey: true});
      expect(await DesktopAlerts.showFresh([]), isFalse);
      expect(await DesktopAlerts.showFresh(['  ', '']), isFalse);
    });
  });

  group('buildLocalPayload reuses NotificationHook verbatim', () {
    test('empty list yields empty body (nothing to show)', () {
      final p = DesktopAlerts.buildLocalPayload('t', []);
      expect(p['title'], 't');
      expect(p['body'], '');
    });

    test('blank titles are dropped before the hook', () {
      final p = DesktopAlerts.buildLocalPayload('t', ['  ', '', 'real']);
      expect(p['body'], 'real');
    });

    test('exactly three titles pass through with no overflow note', () {
      final p = DesktopAlerts.buildLocalPayload('t', ['a', 'b', 'c']);
      expect(p['body'], 'a\nb\nc');
      expect(p['body'], isNot(contains('…and')));
    });

    test('four titles truncate to three with a +1 overflow note', () {
      final p = DesktopAlerts.buildLocalPayload('t', ['a', 'b', 'c', 'd']);
      expect(p['body'], contains('a\nb\nc'));
      expect(p['body'], contains('…and 1 more'));
    });

    test('long overflow lists count the remainder, not the shown', () {
      final titles = List.generate(10, (i) => 'alert-$i');
      final p = DesktopAlerts.buildLocalPayload('t', titles);
      expect(p['body'], contains('alert-0\nalert-1\nalert-2'));
      expect(p['body'], contains('…and 7 more'));
    });

    test('matches NotificationHook.build output exactly', () {
      const titles = ['a', 'b', 'c', 'd', 'e'];
      expect(DesktopAlerts.buildLocalPayload('T', titles),
          NotificationHook.build('T', titles));
    });
  });

  group('policy reuse (no new payload formats, no new policy)', () {
    test('PollPolicy backoff contract is unchanged', () {
      const policy = PollPolicy();
      expect(policy.nextDelay(0), const Duration(minutes: 5));
      expect(policy.nextDelay(1), const Duration(minutes: 10));
      expect(policy.nextDelay(99), const Duration(hours: 1));
    });

    test('thresholds evaluate the documented disk tripwires', () {
      const t = Thresholds();
      expect(t.evaluate(0.79), AlertSeverity.ok);
      expect(t.evaluate(0.85), AlertSeverity.warning);
      expect(t.evaluate(0.95), AlertSeverity.critical);
    });
  });
}
