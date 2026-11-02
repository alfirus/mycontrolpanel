// SPDX-License-Identifier: MIT
// Closed-app slice parity tests (Elizabeth): headless verdicts == in-app
// verdicts, incl. stale/no-data. Proves (not asserts) the table in
// `docs/specs/headless-slice-parity.md` over shared fixtures:
//
// - Same inputs → same key sets (`AlertWatch.currentKeys` vs headless
//   signal keys) and same fresh-title strings (`AlertWatch.freshTitles`
//   vs `HeadlessSignal.displayTitle`, both funneled through
//   `NotificationHook.build`).
// - Transition-only on both rails: resolve → re-fire notifies again,
//   steady firing stays silent (seen-set REPLACED, parity with
//   `AlertWatch.markSeen`).
// - No-data (hosts answered, nothing firing) → `ok`, silent, on both.
// - CI half: failed runs notify headless with the exact in-app string;
//   a sick CI leg never sinks the host tick.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:my_control_panel/background/headless_check.dart';
import 'package:my_control_panel/background/headless_state.dart';
import 'package:my_control_panel/headless.dart';
import 'package:my_control_panel/models/alert_entry.dart';
import 'package:my_control_panel/models/mock_data.dart' show DeployItem;
import 'package:my_control_panel/models/server_connection.dart';
import 'package:my_control_panel/services/alert_watch.dart';
import 'package:my_control_panel/services/background_alerts.dart';
import 'package:my_control_panel/services/headless_security.dart';
import 'package:my_control_panel/services/headless_slice.dart';
import 'package:shared_preferences/shared_preferences.dart';

AlertEntry alert(String title, String server,
        {String status = 'firing'}) =>
    AlertEntry(
      title: title,
      source: 'agent',
      severity: 'critical',
      serverId: server,
      serverName: server,
      status: status,
    );

DeployItem run(String app, String version, String env,
        {String status = 'failed'}) =>
    DeployItem(
      app: app,
      version: version,
      env: env,
      actor: 'ci',
      time: DateTime.fromMillisecondsSinceEpoch(1000),
      status: status,
      duration: '1m',
    );

ServerConnection fakeServer() => ServerConnection(
      id: 'web',
      name: 'web',
      host: 'example.com',
      port: 22,
      username: 'deploy',
      authMethod: AuthMethod.password,
      credential: 'secure:srv_cred_web',
      region: 'us-east-1',
      os: 'Ubuntu 24.04',
      env: ServerEnv.prod,
      createdAt: DateTime.fromMillisecondsSinceEpoch(0),
    );

/// Headless key/title view of the same inputs the in-app rail diffs.
({Set<String> keys, List<String> titles}) headlessView(
  List<AlertEntry> alerts,
  List<DeployItem> runs,
) {
  final signals = <HeadlessSignal>[
    ...HeadlessCheck.signalsFromAlerts(alerts),
    ...HeadlessSlice.signalsFromCiRuns(runs),
  ];
  return (
    keys: signals.map((s) => s.key).toSet(),
    titles: signals.map((s) => s.displayTitle).toList(),
  );
}

void main() {
  group('verdict parity: keys', () {
    test('firing alert + failed run agree on both rails', () {
      final alerts = [alert('Disk 82% full on /', 'web')];
      final runs = [run('api', '#41', 'prod')];
      final inApp = AlertWatch.currentKeys(alerts, runs);
      final headless = headlessView(alerts, runs);
      expect(headless.keys, inApp);
      expect(
        inApp,
        {'alert::web::Disk 82% full on /', 'ci::prod::api #41'},
      );
    });

    test('resolved alerts + passing runs vanish on both rails', () {
      final alerts = [
        alert('Disk 82% full on /', 'web', status: 'resolved'),
        // Blank-title edge: producers never emit these (`repoRuns` /
        // `AlertRules` always set titles); the headless rails drop them
        // while `AlertWatch.currentKeys` keeps them — a known, unreachable
        // in-practice divergence owned by the foreground lane, pinned here
        // so it stays visible instead of silently asserted.
        alert('', 'web', status: 'resolved'),
      ];
      final runs = [
        run('api', '#42', 'prod', status: 'success'),
        run('web', '#7', 'staging', status: 'running'),
      ];
      expect(AlertWatch.currentKeys(alerts, runs), isEmpty);
      final headless = headlessView(alerts, runs);
      expect(headless.keys, isEmpty);
    });

    test('blank CI rows are dropped headless (junk suppression)', () {
      // Headless stdout must never carry a content-free line: the slice
      // drops blank CI rows the same way `signalsFromAlerts` drops
      // blank alert titles (producer titles are non-blank in practice —
      // `repoRuns`/`projectPipelines` always set app/version).
      final runs = [run('', '', '')];
      expect(HeadlessSlice.signalsFromCiRuns(runs), isEmpty);
    });
  });

  group('verdict parity: fresh titles', () {
    test('same inputs announce identical strings', () {
      final alerts = [alert('Service failed: nginx', 'web')];
      final runs = [run('api', '#41', 'prod')];
      final keys = AlertWatch.currentKeys(alerts, runs);
      final inAppFresh =
          AlertWatch.freshTitles(keys, {}, alerts, runs);
      final headless = headlessView(alerts, runs);
      expect(headless.titles, inAppFresh);
      expect(
        inAppFresh,
        ['Service failed: nginx (web)', 'CI failed: api #41'],
      );
    });

    test('end-to-end tick payload equals the in-app payload', () async {
      SharedPreferences.setMockInitialValues({});
      final alerts = [alert('Disk 82% full on /', 'web')];
      final runs = [run('api', '#41', 'prod')];
      final keys = AlertWatch.currentKeys(alerts, runs);
      final inAppFresh =
          AlertWatch.freshTitles(keys, {}, alerts, runs);

      final state = HeadlessState();
      final r = await HeadlessCheck.run(
        consentEnabled: true,
        vaultUnlocked: true,
        state: state,
        fetchAll: () async => [
          ...HeadlessCheck.signalsFromAlerts(alerts),
          ...HeadlessSlice.signalsFromCiRuns(runs),
        ],
        now: DateTime.fromMillisecondsSinceEpoch(2000),
      );
      expect(r.status, 'notified');
      expect(r.freshTitles, inAppFresh);
      expect(r.notification?['title'], 'MyControlPanel alert');
    });
  });

  group('verdict parity: transitions (stale / re-fire / no-data)', () {
    test('steady firing stays silent; resolve→re-fire notifies again',
        () async {
      // Short cooldown: the frozen 6 h resend window would suppress the
      // re-fire inside one test (same as the in-app `AlertPollJob`
      // cooldown — parity holds, the test just compresses time).
      const cooldown = Duration(seconds: 1);
      final firing = [alert('Disk 82% full on /', 'web')];
      Future<HeadlessTickResult> tick(
        HeadlessState state,
        List<HeadlessSignal> signals,
        int atMs,
      ) =>
          HeadlessCheck.run(
            consentEnabled: true,
            vaultUnlocked: true,
            state: state,
            fetchAll: () async => signals,
            now: DateTime.fromMillisecondsSinceEpoch(atMs),
            notifyCooldown: cooldown,
          );
      final state = HeadlessState();
      final first = await tick(
          state, HeadlessCheck.signalsFromAlerts(firing), 1000);
      expect(first.status, 'notified');

      // Steady state: same firing set, seen-set replaced → silent.
      final steady = await tick(
          state, HeadlessCheck.signalsFromAlerts(firing), 2000);
      expect(steady.status, 'ok');
      expect(steady.freshTitles, isEmpty);

      // Resolve clears the set (in-app markSeen parity) …
      final cleared = await tick(state, const [], 3000);
      expect(cleared.status, 'ok');

      // … so a re-fire notifies again.
      final refire = await tick(
          state, HeadlessCheck.signalsFromAlerts(firing), 4000);
      expect(refire.status, 'notified');
      expect(refire.freshTitles, ['Disk 82% full on / (web)']);
    });

    test('no-data (answered, nothing firing) is ok + silent', () async {
      final state = HeadlessState();
      final r = await HeadlessCheck.run(
        consentEnabled: true,
        vaultUnlocked: true,
        state: state,
        fetchAll: () async => const <HeadlessSignal>[],
        now: DateTime.fromMillisecondsSinceEpoch(5000),
      );
      expect(r.exitCode, headlessExitOk);
      expect(r.status, 'ok');
      expect(r.notification, isNull);
    });
  });

  group('adapter CI seam', () {
    test('failed runs notify via the adapter seam', () async {
      final dir =
          await Directory.systemTemp.createTemp('mcp-he-ci');
      try {
        var notified = false;
        String? body;
        final code = await runHeadlessIfRequested(
          const ['--poll-headless'],
          stateDir: () => dir,
          readPrefs: () async => {
            BackgroundAlerts.prefEnabledKey: true,
            'biometrics': false,
          },
          loadServersRaw: () async => [fakeServer()],
          fetchFor: (_) async => const <HeadlessSignal>[],
          fetchRuns: () async => [run('api', '#41', 'prod')],
          notify: (title, b) async {
            notified = true;
            body = b;
          },
          onCheckRecorded: () async {},
        );
        expect(code, headlessExitOk);
        expect(notified, isTrue);
        expect(body, contains('CI failed: api #41'));
      } finally {
        await dir.delete(recursive: true);
      }
    });

    test('throwing CI fetch never sinks the host tick', () async {
      final dir =
          await Directory.systemTemp.createTemp('mcp-he-ci-sick');
      try {
        final code = await runHeadlessIfRequested(
          const ['--poll-headless'],
          stateDir: () => dir,
          readPrefs: () async => {
            BackgroundAlerts.prefEnabledKey: true,
            'biometrics': false,
          },
          loadServersRaw: () async => [fakeServer()],
          fetchFor: (_) async => const [
            HeadlessSignal(
                kind: 'alert',
                title: 'Disk 82% full on /',
                owner: 'web'),
          ],
          fetchRuns: () async => throw Exception('ci down'),
          notify: (title, body) async {},
          onCheckRecorded: () async {},
        );
        expect(code, headlessExitOk);
      } finally {
        await dir.delete(recursive: true);
      }
    });

    test('production default with no tokens skips CI without network',
        () async {
      final dir =
          await Directory.systemTemp.createTemp('mcp-he-ci-def');
      try {
        var notifiedTitle = '';
        final code = await runHeadlessIfRequested(
          const ['--poll-headless'],
          stateDir: () => dir,
          readPrefs: () async => {
            BackgroundAlerts.prefEnabledKey: true,
            'biometrics': false,
            'github_repos': ['owner/repo'],
            'gitlab_projects': ['group/proj'],
            'gitlab_base_url': 'https://gitlab.com',
          },
          readVault: (_) async => null,
          loadServersRaw: () async => [fakeServer()],
          fetchFor: (_) async => const <HeadlessSignal>[],
          // No fetchRuns seam: exercises _fetchRunsDefault. Null vault
          // tokens ⇒ both VCS legs skip with zero network I/O.
          notify: (title, body) async => notifiedTitle = title,
          onCheckRecorded: () async {},
        );
        expect(code, headlessExitOk);
        expect(notifiedTitle, isEmpty);
      } finally {
        await dir.delete(recursive: true);
      }
    });
  });
}
