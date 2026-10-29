import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:my_control_panel/main.dart';
import 'package:my_control_panel/services/app_lock.dart';
import 'package:my_control_panel/widgets/app_lock_screen.dart';

// Fake OS gate: no platform channel involved.
class FakeGate implements AuthGate {
  FakeGate({
    this.supported = true,
    this.result = true,
    this.throws = false,
  });

  bool supported;
  bool result;
  bool throws;
  String? lastReason;

  @override
  Future<bool> isDeviceSupported() async => supported;

  @override
  Future<bool> canCheckBiometrics() async => supported;

  @override
  Future<bool> authenticate({required String reason}) async {
    lastReason = reason;
    if (throws) throw Exception('no plugin (e.g. Linux)');
    return result;
  }
}

void main() {
  group('AppLock unit', () {
    test('toggle off: cold start stays unlocked, unlock is a no-op', () async {
      SharedPreferences.setMockInitialValues({appLockPrefsKey: false});
      final lock = AppLock(gate: FakeGate());
      await lock.load();
      expect(lock.enabled, isFalse);
      expect(lock.locked, isFalse);
      expect(await lock.unlock(), isTrue);
      expect(lock.locked, isFalse);
      expect(lock.message, isNull);
    });

    test('toggle on: cold start engages the lock', () async {
      SharedPreferences.setMockInitialValues({appLockPrefsKey: true});
      final lock = AppLock(gate: FakeGate());
      await lock.load();
      expect(lock.enabled, isTrue);
      expect(lock.locked, isTrue);
    });

    test('successful auth clears the lock', () async {
      SharedPreferences.setMockInitialValues({appLockPrefsKey: true});
      final gate = FakeGate(result: true);
      final lock = AppLock(gate: gate);
      await lock.load();
      expect(await lock.unlock(), isTrue);
      expect(lock.locked, isFalse);
      expect(lock.message, isNull);
      expect(gate.lastReason, isNotEmpty);
    });

    test('cancelled auth keeps the lock with neutral copy', () async {
      SharedPreferences.setMockInitialValues({appLockPrefsKey: true});
      final lock = AppLock(gate: FakeGate(result: false));
      await lock.load();
      expect(await lock.unlock(), isFalse);
      expect(lock.locked, isTrue);
      expect(lock.message, contains('cancelled'));
    });

    test('unsupported device gets clear fallback messaging', () async {
      SharedPreferences.setMockInitialValues({appLockPrefsKey: true});
      final lock = AppLock(gate: FakeGate(supported: false));
      await lock.load();
      expect(await lock.unlock(), isFalse);
      expect(lock.locked, isTrue);
      expect(lock.message, contains('no unlock method'));
    });

    test('platform error (no plugin) gets clear fallback messaging',
        () async {
      SharedPreferences.setMockInitialValues({appLockPrefsKey: true});
      final lock = AppLock(gate: FakeGate(throws: true));
      await lock.load();
      expect(await lock.unlock(), isFalse);
      expect(lock.locked, isTrue);
      expect(lock.message, contains('no unlock method'));
    });

    test('relock re-reads the toggle both ways', () async {
      SharedPreferences.setMockInitialValues({appLockPrefsKey: false});
      final lock = AppLock(gate: FakeGate(result: true));
      await lock.load();
      expect(lock.locked, isFalse);

      // Toggle flipped on in Settings while we were away.
      SharedPreferences.setMockInitialValues({appLockPrefsKey: true});
      await lock.relock();
      expect(lock.enabled, isTrue);
      expect(lock.locked, isTrue);

      // And back off again.
      SharedPreferences.setMockInitialValues({appLockPrefsKey: false});
      await lock.relock();
      expect(lock.locked, isFalse);
    });
  });

  group('AppLock widget', () {
    testWidgets('toggle on: lock screen covers the app until Unlock',
        (tester) async {
      SharedPreferences.setMockInitialValues({appLockPrefsKey: true});
      final lock = AppLock(gate: FakeGate(result: true));
      await lock.load();
      expect(lock.locked, isTrue);

      await tester.pumpWidget(MyControlPanelApp(appLock: lock));
      await tester.pumpAndSettle();

      // Lock screen up, control center hidden.
      expect(find.text('Locked'), findsOneWidget);
      expect(find.text('MY CONTROL PANEL'), findsNothing);

      await tester.tap(find.text('Unlock'));
      await tester.pumpAndSettle();

      // Auth succeeded: control center visible.
      expect(find.text('MY CONTROL PANEL'), findsOneWidget);
      expect(find.text('Locked'), findsNothing);
    });

    testWidgets('toggle off: no lock screen on launch', (tester) async {
      SharedPreferences.setMockInitialValues({appLockPrefsKey: false});
      await tester.pumpWidget(const MyControlPanelApp());
      await tester.pumpAndSettle();

      expect(find.text('Locked'), findsNothing);
      expect(find.text('MY CONTROL PANEL'), findsOneWidget);
    });

    testWidgets('failed auth keeps the lock and shows a message',
        (tester) async {
      SharedPreferences.setMockInitialValues({appLockPrefsKey: true});
      final lock = AppLock(gate: FakeGate(result: false));
      await lock.load();

      await tester.pumpWidget(
        MaterialApp(home: AppLockScreen(lock: lock)),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Unlock'));
      await tester.pumpAndSettle();

      expect(find.text('Locked'), findsOneWidget);
      expect(find.textContaining('cancelled'), findsOneWidget);
    });
  });
}
