import 'package:flutter_test/flutter_test.dart';
import 'package:my_control_panel/services/llm_reliability.dart';
import 'package:my_control_panel/services/model_reliability.dart';

InferenceAttempt att(String p, double lat, bool ok, int t,
        [int pt = 0, int ct = 0]) =>
    InferenceAttempt(
        provider: p,
        model: 'm',
        latencyMs: lat,
        success: ok,
        atMs: t,
        estPromptTokens: pt,
        estCompletionTokens: ct);

void main() {
  group('percentile', () {
    test('empty is null, p50/p95 nearest-rank', () {
      expect(ModelReliability.percentile([], 0.5), isNull);
      final xs = List.generate(100, (i) => (i + 1).toDouble());
      expect(ModelReliability.percentile(xs, 0.5), 50);
      expect(ModelReliability.percentile(xs, 0.95), 95);
    });
  });

  group('summarize', () {
    test('empty history yields empty KPIs', () {
      final k = ModelReliability.summarize([]);
      expect(k.attempts, 0);
      expect(k.errorRate, 0);
      expect(k.latencyP95Ms, isNull);
      expect(k.grade, '—');
    });

    test('latency, error rate and cost roll up', () {
      final now = 1000000000000;
      final rows = <InferenceAttempt>[
        att('openai', 100, true, now - 3000, 1000, 500),
        att('openai', 200, true, now - 2000, 1000, 500),
        att('openai', 300, false, now - 1000, 1000, 0),
      ];
      final k = ModelReliability.summarize(rows, nowMs: now);
      expect(k.attempts, 3);
      expect(k.errors, 1);
      expect(k.errorRate, closeTo(1 / 3, 1e-9));
      expect(k.latencyP50Ms, 200);
      expect(k.latencyP95Ms, 300);
      expect(k.estPromptTokens, 3000);
      expect(k.estCompletionTokens, 1000);
      // (3000/1000*0.005) + (1000/1000*0.015) = 0.03
      expect(k.estCostUsd, closeTo(0.03, 1e-9));
      expect(k.hasUnknownPricing, isFalse);
    });

    test('local providers cost zero without unknown-pricing flag', () {
      final now = 1000000000000;
      final k = ModelReliability.summarize(
          [att('lmStudio', 800, true, now - 1000, 4000, 2000)],
          nowMs: now);
      expect(k.estCostUsd, 0);
      expect(k.hasUnknownPricing, isFalse);
    });

    test('unpriced remote provider flags unknown pricing', () {
      final now = 1000000000000;
      final k = ModelReliability.summarize(
          [att('mystery-cloud', 100, true, now - 1000, 100, 100)],
          nowMs: now);
      expect(k.hasUnknownPricing, isTrue);
    });
  });

  group('capacityScore + grade', () {
    test('perfect health scores 1 / grade A', () {
      final s = ModelReliability.capacityScore(
          errorRate: 0, p95Ms: 500, load1: 0.5);
      expect(s, greaterThan(0.9));
      expect(ModelReliability.reliabilityGrade(s), 'A');
    });

    test('total errors collapse the score to F', () {
      final s =
          ModelReliability.capacityScore(errorRate: 1, p95Ms: 500, load1: 0.5);
      expect(ModelReliability.reliabilityGrade(s), 'F');
    });

    test('grade bands descend monotonically', () {
      expect(ModelReliability.reliabilityGrade(0.9), 'A');
      expect(ModelReliability.reliabilityGrade(0.75), 'B');
      expect(ModelReliability.reliabilityGrade(0.6), 'C');
      expect(ModelReliability.reliabilityGrade(0.4), 'D');
      expect(ModelReliability.reliabilityGrade(0.39), 'F');
    });
  });
}
