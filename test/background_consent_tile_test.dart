import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_control_panel/services/background_alerts.dart';
import 'package:my_control_panel/widgets/background_consent_tile.dart';

Widget _harness({
  required bool value,
  required ValueChanged<bool> onChanged,
  String? lastCheckedLabel,
  bool showBatteryTip = false,
  bool showIosTip = false,
}) {
  return MaterialApp(
    home: Scaffold(
      body: BackgroundAlertConsentTile(
        value: value,
        onChanged: onChanged,
        lastCheckedLabel: lastCheckedLabel,
        showBatteryTip: showBatteryTip,
        showIosTip: showIosTip,
      ),
    ),
  );
}

void main() {
  group('BackgroundAlertConsentTile (consent toggle)', () {
    testWidgets('renders OFF by default with the explicit consent copy',
        (tester) async {
      await tester.pumpWidget(_harness(value: false, onChanged: (_) {}));
      expect(find.text('Background alerts'), findsOneWidget);
      expect(find.text(BackgroundAlerts.consentCopy), findsOneWidget);
      final sw = tester.widget<Switch>(find.byType(Switch));
      expect(sw.value, isFalse);
    });

    testWidgets('toggling ON calls onChanged(true)', (tester) async {
      bool? seen;
      await tester.pumpWidget(
          _harness(value: false, onChanged: (v) => seen = v));
      await tester.tap(find.byType(Switch));
      await tester.pump();
      expect(seen, isTrue);
    });

    testWidgets('toggling OFF calls onChanged(false)', (tester) async {
      bool? seen;
      await tester.pumpWidget(
          _harness(value: true, onChanged: (v) => seen = v));
      await tester.tap(find.byType(Switch));
      await tester.pump();
      expect(seen, isFalse);
    });

    testWidgets('last-checked line shows only when ON', (tester) async {
      const label = 'last checked 16 min ago';
      await tester.pumpWidget(_harness(
          value: false, onChanged: (_) {}, lastCheckedLabel: label));
      expect(find.text(label), findsNothing);

      await tester.pumpWidget(_harness(
          value: true, onChanged: (_) {}, lastCheckedLabel: label));
      expect(find.text(label), findsOneWidget);
    });

    testWidgets('platform explainers show only when ON', (tester) async {
      await tester.pumpWidget(_harness(
        value: false,
        onChanged: (_) {},
        showBatteryTip: true,
        showIosTip: true,
      ));
      expect(find.text(BackgroundAlerts.batteryPromptBody), findsNothing);
      expect(find.text(BackgroundAlerts.iosPromptBody), findsNothing);

      await tester.pumpWidget(_harness(
        value: true,
        onChanged: (_) {},
        showBatteryTip: true,
      ));
      expect(find.text(BackgroundAlerts.batteryPromptBody), findsOneWidget);

      await tester.pumpWidget(_harness(
        value: true,
        onChanged: (_) {},
        showIosTip: true,
      ));
      expect(find.text(BackgroundAlerts.iosPromptBody), findsOneWidget);
    });
  });
}
