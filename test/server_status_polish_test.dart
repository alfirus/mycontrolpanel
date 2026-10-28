import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:my_control_panel/theme/app_theme.dart';
import 'package:my_control_panel/theme/design_tokens.dart';
import 'package:my_control_panel/widgets/pitch_card.dart';

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  group('AppThresholds (spec 02 §2.3)', () {
    test('match the ratified cutoffs', () {
      expect(AppThresholds.cpuCritical, 0.75);
      expect(AppThresholds.ramCritical, 0.85);
      expect(AppThresholds.diskWarn, 0.80);
      expect(AppThresholds.diskCritical, 0.95);
    });
  });

  group('sparklineP95', () {
    test('empty series is 0', () => expect(sparklineP95([]), 0));
    test('single value passes through', () => expect(sparklineP95([42.4]), 42));
    test('picks the p95 of a 9-point demo series', () {
      // Sorted: 20,30,35,38,40,42,45,48,52 → idx ceil(9*.95)-1 = 8 → 52.
      expect(sparklineP95([20, 35, 30, 45, 38, 52, 40, 48, 42]), 52);
    });
  });

  group('trendPoints (spec 02 parity rule)', () {
    test('empty and single-point histories yield no band', () {
      expect(trendPoints([]), isEmpty);
      expect(trendPoints([0.42]), isEmpty);
    });
    test('maps 0..1 polls to the demo percent scale', () {
      expect(trendPoints([0.2, 0.42, 0.78]), [20.0, 42.0, 78.0]);
    });
    test('round-trips through sparklineP95 for the label', () {
      expect(sparklineP95(trendPoints([0.2, 0.35, 0.78])), 78);
    });
  });

  group('MetricBar (spec 02 §2.3)', () {
    testWidgets('label renders in textSecondary, value renders', (tester) async {
      await tester.pumpWidget(_wrap(const MetricBar(
        label: 'CPU',
        value: 0.42,
        color: AppColors.textSecondary,
      )));
      expect(find.text('CPU'), findsOneWidget);
      expect(find.text('42%'), findsOneWidget);
      final label = tester.widget<Text>(find.text('CPU'));
      expect(label.style?.color, AppColors.textSecondary);
    });

    testWidgets('announces "CPU 71 percent, normal" — never color alone (spec 02 §4)', (tester) async {
      await tester.pumpWidget(_wrap(const MetricBar(
        label: 'CPU',
        value: 0.71,
        color: AppColors.textSecondary,
      )));
      final semantics = tester.getSemantics(find.byWidgetPredicate(
        (w) => w is Semantics && (w.properties.label ?? '').startsWith('CPU'),
      ));
      expect(semantics.label, 'CPU 71 percent, normal');
    });

    testWidgets('state word follows the bar hue: warning/critical', (tester) async {
      await tester.pumpWidget(_wrap(const MetricBar(
        label: 'DISK',
        value: 0.82,
        color: AppColors.warning,
      )));
      expect(
        tester.getSemantics(find.byWidgetPredicate(
          (w) => w is Semantics && (w.properties.label ?? '').startsWith('DISK'),
        )).label,
        'DISK 82 percent, warning',
      );

      await tester.pumpWidget(_wrap(const MetricBar(
        label: 'CPU',
        value: 0.91,
        color: AppColors.critical,
      )));
      expect(
        tester.getSemantics(find.byWidgetPredicate(
          (w) => w is Semantics && (w.properties.label ?? '').startsWith('CPU'),
        )).label,
        'CPU 91 percent, critical',
      );
    });
  });

  group('PitchCard (spec 01 rule)', () {
    testWidgets('subtitle renders in textSecondary, not textMuted', (tester) async {
      await tester.pumpWidget(_wrap(const PitchCard(
        title: 'SERVERS',
        subtitle: 'Demo data',
        child: Text('body'),
      )));
      final subtitle = tester.widget<Text>(find.text('Demo data'));
      expect(subtitle.style?.color, AppColors.textSecondary);
    });
  });
}
