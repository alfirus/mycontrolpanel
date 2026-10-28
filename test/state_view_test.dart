import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:my_control_panel/widgets/state_view.dart';

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  testWidgets('loading renders label with live region', (tester) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(_wrap(const StateView(
      state: PanelState.loading,
      loadingLabel: 'Syncing GitHub…',
    )));
    expect(find.text('Syncing GitHub…'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    final sems = tester.widgetList<Semantics>(find.byType(Semantics));
    expect(
      sems.any((s) => s.properties.label == 'Syncing GitHub…' && s.properties.liveRegion == true),
      isTrue,
      reason: 'loading frame must expose an exact-label live region',
    );
    semantics.dispose();
  });

  testWidgets('empty renders headline, body and action; tap fires', (tester) async {
    var tapped = false;
    await tester.pumpWidget(_wrap(StateView(
      state: PanelState.empty,
      icon: Icons.check_circle,
      headline: 'QUEUE IS CLEAR',
      body: 'No open issues across 2 repos ✓',
      actionLabel: 'RETRY',
      onAction: () => tapped = true,
      semanticLabel: 'GitHub queue is clear',
    )));
    expect(find.text('QUEUE IS CLEAR'), findsOneWidget);
    expect(find.textContaining('No open issues'), findsOneWidget);
    expect(find.byType(FilledButton), findsOneWidget);
    await tester.tap(find.text('RETRY'));
    expect(tapped, isTrue);
  });

  testWidgets('error without action renders no button', (tester) async {
    await tester.pumpWidget(_wrap(const StateView(
      state: PanelState.error,
      icon: Icons.error_outline,
      headline: 'GITHUB SYNC FAILED',
      body: 'first error line',
    )));
    expect(find.text('GITHUB SYNC FAILED'), findsOneWidget);
    expect(find.text('first error line'), findsOneWidget);
    expect(find.byType(FilledButton), findsNothing);
  });

  testWidgets('data renders nothing', (tester) async {
    await tester.pumpWidget(_wrap(const StateView(state: PanelState.data)));
    expect(find.byType(StateView), findsOneWidget);
    expect(find.byType(Icon), findsNothing);
  });

  testWidgets('reduced motion swaps spinner for static icon', (tester) async {
    await tester.pumpWidget(MediaQuery(
      data: const MediaQueryData(disableAnimations: true),
      child: _wrap(const StateView(
        state: PanelState.loading,
        loadingLabel: 'Syncing pipelines…',
      )),
    ));
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.byIcon(Icons.refresh), findsOneWidget);
    expect(find.text('Syncing pipelines…'), findsOneWidget);
  });
}
