// SPDX-License-Identifier: MIT
// Parallel host polling (Zara): slow-host fixture proving one stalled host
// never stalls the others, ordering is stable for UI merge, and backoff
// stays per-host with PollPolicy semantics.
import 'package:flutter_test/flutter_test.dart';
import 'package:my_control_panel/services/polling_alerts.dart';

const _policy = PollPolicy(
  baseInterval: Duration(minutes: 5),
  maxInterval: Duration(hours: 1),
);

void main() {
  group('pollHostsConcurrently', () {
    test('slow host times out alone; others still refresh', () async {
      final sw = Stopwatch()..start();
      final out = await pollHostsConcurrently<String>(
        hostIds: const ['fast-a', 'slow', 'fast-b'],
        policy: _policy,
        perHostTimeout: const Duration(milliseconds: 300),
        fetch: (id) async {
          if (id == 'slow') {
            // Hung SSH handshake that would stall a sequential loop.
            await Future.delayed(const Duration(seconds: 5));
            return 'slow-value';
          }
          await Future.delayed(const Duration(milliseconds: 10));
          return '$id-value';
        },
      );
      sw.stop();

      // The 5 s stall is cut to the 300 ms per-host timeout.
      expect(sw.elapsed, lessThan(const Duration(seconds: 4)));
      // Healthy hosts still refresh despite the stalled sibling.
      expect(out.map((o) => o.hostId), ['fast-a', 'slow', 'fast-b']);
      expect(out[0].answered, isTrue);
      expect(out[0].value, 'fast-a-value');
      expect(out[2].answered, isTrue);
      expect(out[2].value, 'fast-b-value');
      // The stalled host is recorded as a first failure, not a sink.
      expect(out[1].answered, isFalse);
      expect(out[1].value, isNull);
      expect(out[1].consecutiveFailures, 1);
      expect(out[1].nextDelay, const Duration(minutes: 10));
      // Successes reset to the base interval (AlertPollJob.tick parity).
      expect(out[0].consecutiveFailures, 0);
      expect(out[0].nextDelay, const Duration(minutes: 5));
    });

    test('overlapping slow hosts finish together, not stacked', () async {
      final sw = Stopwatch()..start();
      final out = await pollHostsConcurrently<String>(
        hostIds: const ['h1', 'h2', 'h3'],
        policy: _policy,
        perHostTimeout: const Duration(seconds: 10),
        fetch: (_) async {
          await Future.delayed(const Duration(milliseconds: 600));
          return 'ok';
        },
      );
      sw.stop();

      expect(out.where((o) => o.answered), hasLength(3));
      // Sequential polling would stack to >= 1800 ms; concurrent fan-out
      // finishes in ~one leg. The bound is generous so loaded CI stays
      // green — sequential code can never pass it (the delays are real).
      expect(sw.elapsed, lessThan(const Duration(milliseconds: 1500)));
    });

    test('ordering follows input order, not answer order', () async {
      final out = await pollHostsConcurrently<String>(
        hostIds: const ['a', 'b', 'c'],
        policy: _policy,
        fetch: (id) async {
          switch (id) {
            case 'a':
              await Future.delayed(const Duration(milliseconds: 300));
            case 'b':
              await Future.delayed(const Duration(milliseconds: 150));
            default:
              await Future.delayed(const Duration(milliseconds: 10));
          }
          return 'v-$id';
        },
      );
      expect(out.map((o) => o.hostId), ['a', 'b', 'c']);
      expect(out.map((o) => o.value), ['v-a', 'v-b', 'v-c']);
      expect(out.map((o) => o.index), [0, 1, 2]);
    });

    test('backoff is per-host: streaks continue, successes reset', () async {
      final out = await pollHostsConcurrently<String>(
        hostIds: const ['bad', 'good'],
        policy: _policy,
        previousFailures: const {'bad': 2, 'good': 4},
        fetch: (id) async {
          if (id == 'bad') throw Exception('agent + SSH down');
          return 'ok';
        },
      );
      final bad = out.firstWhere((o) => o.hostId == 'bad');
      expect(bad.answered, isFalse);
      expect(bad.consecutiveFailures, 3);
      expect(bad.nextDelay, const Duration(minutes: 40));
      final good = out.firstWhere((o) => o.hostId == 'good');
      expect(good.answered, isTrue);
      expect(good.consecutiveFailures, 0);
      expect(good.nextDelay, const Duration(minutes: 5));
    });

    test('total outage yields all-unanswered outcomes, never throws', () async {
      final out = await pollHostsConcurrently<String>(
        hostIds: const ['h1', 'h2'],
        policy: _policy,
        fetch: (_) async => throw Exception('everything down'),
      );
      expect(out, hasLength(2));
      expect(out.every((o) => !o.answered), isTrue);
      expect(out.map((o) => o.consecutiveFailures), [1, 1]);
    });

    test('empty input yields empty output without calling fetch', () async {
      var calls = 0;
      final out = await pollHostsConcurrently<String>(
        hostIds: const [],
        policy: _policy,
        fetch: (_) async {
          calls++;
          return 'x';
        },
      );
      expect(out, isEmpty);
      expect(calls, 0);
    });
  });
}
