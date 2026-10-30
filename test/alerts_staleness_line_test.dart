import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_control_panel/widgets/alerts_staleness_line.dart';

Widget _harness(String label) {
  return MaterialApp(
    home: Scaffold(body: AlertsStalenessLine(label: label)),
  );
}

void main() {
  group('AlertsStalenessLine (alerts-surface stale state)', () {
    testWidgets('renders the last-checked label verbatim', (tester) async {
      const label = 'last checked 16 min ago';
      await tester.pumpWidget(_harness(label));
      expect(find.text(label), findsOneWidget);
    });

    testWidgets('shows the idle copy before any background check',
        (tester) async {
      const label = 'Background alerts idle — never checked yet';
      await tester.pumpWidget(_harness(label));
      expect(find.text(label), findsOneWidget);
    });

    testWidgets('carries a schedule icon + status semantics (names, not colors)',
        (tester) async {
      const label = 'last checked just now';
      await tester.pumpWidget(_harness(label));
      expect(find.byIcon(Icons.schedule), findsOneWidget);
      final sems = tester.widgetList<Semantics>(find.byType(Semantics));
      expect(
        sems.any((s) =>
            s.properties.label == 'Background check status: $label'),
        isTrue,
        reason: 'stale line must expose an exact-label status node',
      );
    });

    testWidgets('updates when the label refreshes (stale → fresh)',
        (tester) async {
      await tester.pumpWidget(_harness('last checked 2 hr ago'));
      expect(find.text('last checked 2 hr ago'), findsOneWidget);

      await tester.pumpWidget(_harness('last checked just now'));
      expect(find.text('last checked just now'), findsOneWidget);
      expect(find.text('last checked 2 hr ago'), findsNothing);
    });

    testWidgets('uses the muted mono footnote style', (tester) async {
      const label = 'last checked 1 day ago';
      await tester.pumpWidget(_harness(label));
      final text = tester.widget<Text>(find.text(label));
      expect(text.style?.fontSize, 10);
      expect(text.style?.fontFamily, 'JetBrainsMono');
    });
  });
}
