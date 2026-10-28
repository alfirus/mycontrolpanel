import 'package:flutter_test/flutter_test.dart';
import 'package:my_control_panel/services/llm_reliability.dart';

InferenceAttempt att(String p, double lat, bool ok, [int t = 0]) =>
    InferenceAttempt(
        provider: p, model: 'm', latencyMs: lat, success: ok, atMs: t);

void main() {
  group('InferenceAttempt', () {
    test('estimateTokens scales with length', () {
      expect(InferenceAttempt.estimateTokens(''), 0);
      expect(InferenceAttempt.estimateTokens('abcd'), 1);
      expect(InferenceAttempt.estimateTokens('abcdefgh'), 2);
    });

    test('json round-trips, corrupt input returns null', () {
      final a = att('lmStudio', 120, true, 42);
      final back = InferenceAttempt.fromJson(a.toJson());
      expect(back, isNotNull);
      expect(back!.provider, 'lmStudio');
      expect(back.latencyMs, 120);
      expect(back.atMs, 42);
      expect(InferenceAttempt.fromJson({'p': 'x'}), isNull);
      expect(InferenceAttempt.fromJson({'p': 1, 'm': 'm', 'lat': 1, 't': 1}),
          isNull);
    });
  });

  group('AttemptRing', () {
    test('caps at 200, newest last', () {
      final ring = AttemptRing();
      for (var i = 0; i < 250; i++) {
        ring.add(att('p', i.toDouble(), true, i));
      }
      expect(ring.length, AttemptRing.cap);
      expect(ring.items.first.atMs, 50);
      expect(ring.items.last.atMs, 249);
    });
  });

  group('ProviderHealth + FallbackChain', () {
    test('success clears streak', () {
      final h = ProviderHealth(maxConsecutiveFailures: 2);
      h.record('a', false, 0);
      h.record('a', true, 1);
      expect(h.streak('a'), 0);
      expect(h.inCooldown('a', 2), isFalse);
    });

    test('cooldown trips after N consecutive failures, then expires', () {
      final h = ProviderHealth(
          maxConsecutiveFailures: 3, cooldown: const Duration(minutes: 5));
      h.record('a', false, 0);
      h.record('a', false, 1);
      expect(h.inCooldown('a', 2), isFalse);
      h.record('a', false, 2);
      expect(h.inCooldown('a', 3), isTrue);
      expect(h.inCooldown('a', 2 + 5 * 60 * 1000 + 1), isFalse);
    });

    test('order skips cooled providers but keeps them as last resort', () {
      final h = ProviderHealth(maxConsecutiveFailures: 1);
      h.record('primary', false, 0);
      expect(
          FallbackChain.order(['primary', 'backup'], h, 1),
          ['backup', 'primary']);
      expect(FallbackChain.pick(['primary', 'backup'], h, 1), 'backup');
    });

    test('pick returns null when nothing configured', () {
      expect(FallbackChain.pick([], ProviderHealth(), 0), isNull);
    });
  });
}
