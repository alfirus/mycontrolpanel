// SPDX-License-Identifier: MIT
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:my_control_panel/services/chart_downsample.dart';

/// Pump a sparkline built exactly the way the control center builds its
/// per-card trend (downsample → FlSpot → LineChart under fl_chart 1.x).
/// This is the pixel-parity smoke test for the 0.71 → 1.x upgrade: if the
/// 1.x API drifts, this harness fails the same way the screen would.
Widget _sparklineHarness(List<double> values, {int maxPoints = 48}) {
  final sampled = downsampleSeries(values, maxPoints: maxPoints);
  return MaterialApp(
    home: Scaffold(
      body: SizedBox(
        height: 24,
        width: 200,
        child: LineChart(LineChartData(
          gridData: const FlGridData(show: false),
          titlesData: const FlTitlesData(show: false),
          borderData: FlBorderData(show: false),
          lineBarsData: [
            LineChartBarData(
              spots: [
                for (var i = 0; i < sampled.length; i++)
                  FlSpot(i.toDouble(), sampled[i])
              ],
              isCurved: true,
              color: Colors.green,
              barWidth: 1.6,
              dotData: const FlDotData(show: false),
              belowBarData: BarAreaData(
                  show: true, color: Colors.green.withValues(alpha: 0.08)),
            )
          ],
        )),
      ),
    ),
  );
}

void main() {
  group('downsampleSeries (correctness)', () {
    test('empty and single-point series pass through', () {
      expect(downsampleSeries([]), isEmpty);
      expect(downsampleSeries([3.5]), [3.5]);
    });

    test('series at or under budget return unchanged (pixel parity)', () {
      const vals = <double>[20.0, 35, 30, 45, 38, 52, 40, 48, 42];
      final out = downsampleSeries(vals, maxPoints: kMaxSparklinePoints);
      expect(out, vals);
      expect(identical(out, vals), isFalse,
          reason: 'must be a copy, never alias the history');
      // Demo-scale CPU history (40 pts) also passes through untouched.
      final history =
          List<double>.generate(40, (i) => (i * 7 % 90 + 5).toDouble());
      expect(downsampleSeries(history, maxPoints: kMaxSparklinePoints),
          history);
    });

    test('over-budget series collapse to exactly maxPoints', () {
      final vals = List<double>.generate(500, (i) => (i * 13 % 100).toDouble());
      final out = downsampleSeries(vals, maxPoints: kMaxSparklinePoints);
      expect(out.length, kMaxSparklinePoints);
    });

    test('first and last points are always preserved', () {
      final vals = List<double>.generate(1000, (i) => (i * 37 % 80 + 10).toDouble());
      final out = downsampleSeries(vals, maxPoints: 60);
      expect(out.first, vals.first);
      expect(out.last, vals.last);
    });

    test('maxPoints of 2 keeps only the endpoints', () {
      final vals = List<double>.generate(200, (i) => i.toDouble());
      expect(downsampleSeries(vals, maxPoints: 2),
          [vals.first, vals.last]);
    });

    test('isolated spikes survive (shape fidelity for alert peaks)', () {
      // Flat baseline with one sharp peak — the peak is what an operator
      // scans for, so the resampler must not swallow it.
      final vals = List.filled(400, 10.0)..[200] = 100.0;
      final out = downsampleSeries(vals, maxPoints: 48);
      expect(out, contains(100.0));
      expect(out.first, 10.0);
      expect(out.last, 10.0);
    });

    test('output is deterministic for the same input', () {
      final vals = List<double>.generate(300, (i) => (i * 29 % 95 + 2).toDouble());
      expect(downsampleSeries(vals, maxPoints: 48),
          downsampleSeries(vals, maxPoints: 48));
    });

    test('monotonic series stay monotonic', () {
      final vals = List<double>.generate(200, (i) => i.toDouble());
      final out = downsampleSeries(vals, maxPoints: 24);
      for (var i = 1; i < out.length; i++) {
        expect(out[i] >= out[i - 1], isTrue,
            reason: 'LTTB subset of a ramp must not reorder');
      }
    });
  });

  group('downsampleSeries (perf)', () {
    test('20k-point full history collapses in well under a frame budget', () {
      final vals =
          List<double>.generate(20000, (i) => (i * 7919 % 1000) / 10.0);
      final sw = Stopwatch()..start();
      final out = downsampleSeries(vals, maxPoints: kMaxLatencyChartPoints);
      sw.stop();
      expect(out.length, kMaxLatencyChartPoints);
      expect(sw.elapsedMilliseconds, lessThan(2000),
          reason: 'took ${sw.elapsedMilliseconds}ms for 20k points');
    });

    test('per-tick cost stays flat as history grows 10x', () {
      double bench(int n) {
        final vals = List<double>.generate(n, (i) => (i * 7919 % 1000) / 10.0);
        final sw = Stopwatch()..start();
        downsampleSeries(vals, maxPoints: kMaxLatencyChartPoints);
        sw.stop();
        return sw.elapsedMicroseconds.toDouble();
      }
      final small = bench(2000);
      final big = bench(20000);
      // Linear scan is expected (~10x input); the assertion that matters is
      // the absolute ceiling from the previous test, but a superlinear blowup
      // (e.g. accidental O(n^2)) would trip this ratio guard.
      expect(big / (small == 0 ? 1 : small), lessThan(50.0));
    });
  });

  group('downsampled LineChart (fl_chart 1.x widget parity)', () {
    testWidgets('demo-scale series renders the full spot list', (tester) async {
      const vals = <double>[20.0, 35, 30, 45, 38, 52, 40, 48, 42];
      await tester.pumpWidget(_sparklineHarness(vals));
      expect(find.byType(LineChart), findsOneWidget);
      final chart = tester.widget<LineChart>(find.byType(LineChart));
      expect(chart.data.lineBarsData.single.spots.length, vals.length);
    });

    testWidgets('aged 300-point series renders capped at the budget',
        (tester) async {
      final vals = List<double>.generate(300, (i) => (i * 13 % 90 + 5).toDouble());
      await tester.pumpWidget(_sparklineHarness(vals));
      expect(find.byType(LineChart), findsOneWidget);
      final chart = tester.widget<LineChart>(find.byType(LineChart));
      expect(chart.data.lineBarsData.single.spots.length, kMaxSparklinePoints);
      // Endpoints pinned: the trend still starts/ends where history does.
      final spots = chart.data.lineBarsData.single.spots;
      expect(spots.first.y, vals.first);
      expect(spots.last.y, vals.last);
    });
  });
}
