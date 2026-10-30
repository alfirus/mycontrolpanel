import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_control_panel/services/background_alerts.dart';
import 'package:my_control_panel/widgets/background_consent_tile.dart';

/// Desktop configuration of the SHARED consent toggle (beta.1).
///
/// There is no second desktop-only toggle: desktop shows the same
/// [BackgroundAlertConsentTile] row with neither the Android battery tip
/// nor the iOS tip. These tests lock that configuration so a future edit
/// cannot silently fork the consent contract per platform.
Widget _desktopHarness({
  required bool value,
  required ValueChanged<bool> onChanged,
  String? lastCheckedLabel,
}) {
  return MaterialApp(
    home: Scaffold(
      body: BackgroundAlertConsentTile(
        value: value,
        onChanged: onChanged,
        lastCheckedLabel: lastCheckedLabel,
        showBatteryTip: false,
        showIosTip: false,
      ),
    ),
  );
}

void main() {
  group('BackgroundAlertConsentTile on desktop (shared row)', () {
    testWidgets('renders OFF by default with the explicit consent copy',
        (tester) async {
      await tester
          .pumpWidget(_desktopHarness(value: false, onChanged: (_) {}));
      expect(find.text('Background alerts'), findsOneWidget);
      expect(find.text(BackgroundAlerts.consentCopy), findsOneWidget);
      final sw = tester.widget<Switch>(find.byType(Switch));
      expect(sw.value, isFalse);
    });

    testWidgets('shows no mobile platform explainers', (tester) async {
      await tester.pumpWidget(
          _desktopHarness(value: true, onChanged: (_) {}));
      expect(find.text(BackgroundAlerts.batteryPromptBody), findsNothing);
      expect(find.text(BackgroundAlerts.iosPromptBody), findsNothing);
    });

    testWidgets('toggling ON calls onChanged(true)', (tester) async {
      bool? seen;
      await tester.pumpWidget(
          _desktopHarness(value: false, onChanged: (v) => seen = v));
      await tester.tap(find.byType(Switch));
      await tester.pump();
      expect(seen, isTrue);
    });

    testWidgets('toggling OFF calls onChanged(false)', (tester) async {
      bool? seen;
      await tester.pumpWidget(
          _desktopHarness(value: true, onChanged: (v) => seen = v));
      await tester.tap(find.byType(Switch));
      await tester.pump();
      expect(seen, isFalse);
    });

    testWidgets('last-checked line shows only when ON', (tester) async {
      const label = 'last checked 16 min ago';
      await tester.pumpWidget(_desktopHarness(
          value: false, onChanged: (_) {}, lastCheckedLabel: label));
      expect(find.text(label), findsNothing);

      await tester.pumpWidget(_desktopHarness(
          value: true, onChanged: (_) {}, lastCheckedLabel: label));
      expect(find.text(label), findsOneWidget);
    });
  });
}
