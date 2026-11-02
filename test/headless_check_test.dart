// SPDX-License-Identifier: MIT
// TM-1 shared pipeline tests (Lina): gates, exit codes, transition-only
// notify, cooldown, backoff, JSON schema, stdout hygiene.
import 'package:flutter_test/flutter_test.dart';
import 'package:my_control_panel/background/headless_check.dart';
import 'package:my_control_panel/background/headless_state.dart';
import 'package:my_control_panel/services/headless_security.dart';
import 'package:my_control_panel/services/polling_alerts.dart';

List<HeadlessSignal> twoAlerts() => const [
      HeadlessSignal(
          kind: 'alert', title: 'Disk 82% full on /', owner: 'web'),
      HeadlessSignal(
          kind: 'alert', title: 'Service failed: nginx', owner: 'web'),
    ];

void main() {
  group('HeadlessCheck.run gates (ADR-003)', () {
    test('consent OFF skips with exit 2, touches nothing', () async {
      var fetched = false;
      var notified = false;
      final state = HeadlessState();
      final r = await HeadlessCheck.run(
        consentEnabled: false,
        vaultUnlocked: true,
        state: state,
        fetchAll: () async {
          fetched = true;
          return twoAlerts();
        },
        now: DateTime.fromMillisecondsSinceEpoch(1000),
        onNotify: (title, body) async => notified = true,
      );
      expect(r.exitCode, headlessExitSkipped);
      expect(r.status, 'skipped');
      expect(fetched, isFalse);
      expect(notified, isFalse);
      expect(state.seenKeys, isEmpty,
          reason: 'skips stamp nothing');
    });

    test('locked vault denies with exit 2 (never prompts headless)',
        () async {
      final state = HeadlessState();
      final r = await HeadlessCheck.run(
        consentEnabled: true,
        vaultUnlocked: false,
        state: state,
        fetchAll: () async => twoAlerts(),
        now: DateTime.fromMillisecondsSinceEpoch(1000),
      );
      expect(r.exitCode, headlessExitSkipped);
      expect(r.status, 'skipped');
      expect(r.reason, contains('denied'));
    });

    test('tainted argv fails loudly with exit 1', () async {
      var fetched = false;
      final state = HeadlessState();
      final r = await HeadlessCheck.run(
        consentEnabled: true,
        vaultUnlocked: true,
        state: state,
        fetchAll: () async {
          fetched = true;
          return twoAlerts();
        },
        now: DateTime.fromMillisecondsSinceEpoch(1000),
        argv: const ['--poll-headless', '--token=hunter2'],
      );
      expect(r.exitCode, headlessExitError);
      expect(r.status, 'error');
      expect(fetched, isFalse,
          reason: 'tampered scheduler must never reach the poller');
    });
  });

  group('transition-only notify', () {
    test('first tick notifies, repeat tick stays silent', () async {
      final state = HeadlessState();
      final at = DateTime.fromMillisecondsSinceEpoch(5000);
      final notified = <String>[];
      final first = await HeadlessCheck.run(
        consentEnabled: true,
        vaultUnlocked: true,
        state: state,
        fetchAll: () async => twoAlerts(),
        now: at,
        onNotify: (t, b) async => notified.add('$t::$b'),
      );
      expect(first.exitCode, headlessExitOk);
      expect(first.status, 'notified');
      expect(first.notified, isTrue);
      expect(first.freshTitles, hasLength(2));
      expect(first.notification, isNotNull);
      expect(first.notification!['title'], 'MyControlPanel alert');
      expect(notified, hasLength(1));

      final second = await HeadlessCheck.run(
        consentEnabled: true,
        vaultUnlocked: true,
        state: state,
        fetchAll: () async => twoAlerts(),
        now: at.add(const Duration(minutes: 15)),
        onNotify: (t, b) async => notified.add('$t::$b'),
      );
      expect(second.exitCode, headlessExitOk);
      expect(second.status, 'ok');
      expect(second.notified, isFalse);
      expect(second.freshTitles, isEmpty);
      expect(notified, hasLength(1),
          reason: 'steady firing state must not re-toast');
    });

    test('resolve then re-fire notifies again', () async {
      final state = HeadlessState();
      Future<HeadlessTickResult> tick(List<HeadlessSignal> s, int ms) =>
          HeadlessCheck.run(
            consentEnabled: true,
            vaultUnlocked: true,
            state: state,
            fetchAll: () async => s,
            now: DateTime.fromMillisecondsSinceEpoch(ms),
          );
      await tick(twoAlerts(), 1000);
      await tick(const [], 2000);
      final refire = await tick(twoAlerts(), 8 * 3600 * 1000);
      expect(refire.status, 'notified',
          reason: 're-fire after resolve is a new transition');
    });

    test('resend cooldown suppresses flapping inside 6h', () async {
      final state = HeadlessState();
      Future<HeadlessTickResult> tick(List<HeadlessSignal> s, int ms) =>
          HeadlessCheck.run(
            consentEnabled: true,
            vaultUnlocked: true,
            state: state,
            fetchAll: () async => s,
            now: DateTime.fromMillisecondsSinceEpoch(ms),
          );
      await tick(twoAlerts(), 1000);
      // Flap: disappear then reappear 1h later — still inside cooldown.
      await tick(const [], 2000);
      final flap = await tick(twoAlerts(), 3600 * 1000);
      expect(flap.notified, isFalse,
          reason: 'same title re-firing inside 6h stays silent');
    });

    test('payload caps at 3 + …and N more (NotificationHook verbatim)',
        () async {
      final state = HeadlessState();
      final many = List.generate(
        5,
        (i) => HeadlessSignal(
            kind: 'alert', title: 'Alert $i', owner: 'web'),
      );
      final r = await HeadlessCheck.run(
        consentEnabled: true,
        vaultUnlocked: true,
        state: state,
        fetchAll: () async => many,
        now: DateTime.fromMillisecondsSinceEpoch(1000),
      );
      expect(r.status, 'notified');
      expect(r.notification!['body'], contains('…and 2 more'));
    });
  });

  group('backoff + errors', () {
    test('total transport failure is exit 1 and counts the streak',
        () async {
      final state = HeadlessState();
      final r = await HeadlessCheck.run(
        consentEnabled: true,
        vaultUnlocked: true,
        state: state,
        fetchAll: () async =>
            throw Exception('agent + SSH both down'),
        now: DateTime.fromMillisecondsSinceEpoch(1000),
      );
      expect(r.exitCode, headlessExitError);
      expect(r.status, 'error');
      expect(state.consecutiveFailures, 1);
      expect(state.lastCheckMs, 0,
          reason: 'failed ticks still do not stamp success state');
    });

    test('active backoff skips with exit 2 without fetching', () async {
      var fetched = false;
      final state = HeadlessState(consecutiveFailures: 1)
          .copyWith(lastCheckMs: 100000);
      final r = await HeadlessCheck.run(
        consentEnabled: true,
        vaultUnlocked: true,
        state: state,
        fetchAll: () async {
          fetched = true;
          return twoAlerts();
        },
        // PollPolicy base 5m → 1 failure = 10m; 5m later is still backing off.
        now: DateTime.fromMillisecondsSinceEpoch(100000 + 5 * 60 * 1000),
        policy: const PollPolicy(),
      );
      expect(r.exitCode, headlessExitSkipped);
      expect(r.status, 'skipped');
      expect(fetched, isFalse);
    });
  });

  group('stdout JSON contract', () {
    test('result JSON carries the frozen schema', () async {
      final state = HeadlessState();
      final r = await HeadlessCheck.run(
        consentEnabled: true,
        vaultUnlocked: true,
        state: state,
        fetchAll: () async => twoAlerts(),
        now: DateTime.fromMillisecondsSinceEpoch(4242),
      );
      final j = r.toJson();
      expect(
          j.keys,
          containsAll([
            'version',
            'status',
            'exitCode',
            'checkedAtMs',
            'freshTitles',
            'notification'
          ]));
      expect(j['version'], 1);
      expect(j['exitCode'], headlessExitOk);
      expect(j['checkedAtMs'], 4242);
    });

    test('stdout carries no secret-shaped material', () async {
      final state = HeadlessState();
      final r = await HeadlessCheck.run(
        consentEnabled: true,
        vaultUnlocked: true,
        state: state,
        fetchAll: () async => twoAlerts(),
        now: DateTime.fromMillisecondsSinceEpoch(1000),
        argv: const ['--poll-headless'],
      );
      final violations = HeadlessSecurity.findSecretMaterialInArgs(
          [r.toJsonString()]);
      expect(violations, isEmpty);
    });
  });
}
