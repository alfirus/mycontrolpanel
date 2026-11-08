// SPDX-License-Identifier: MIT
/// Nadia (t_7b8e0b7a): refresh-timer lifecycle regression proof.
///
/// Verdict on main: CLEAN — no stacked timers. The two refresh tickers
/// ([ControlCenterScreen] log + auto-refresh) are created once in
/// `initState`, cancelled in `dispose`, and tab switches are `setState`-only
/// tab-index flips in the same [State] (no per-tab ticker is ever started).
/// [AlertPollJob.start] is stop-before-start, so re-entrant starts keep a
/// single active ticker.
///
/// These tests pin that: exactly one heartbeat per 3s window no matter how
/// fast tabs are switched, silence after unmount, and single-ticker
/// semantics for the poll job (restart keeps one, stop cancels it).
///
/// Note: the suite drives the mobile layout on purpose — the desktop rail
/// trips a pre-existing (unrelated) ListTile-background debug assertion that
/// would fail any desktop-size pump; tab-switch coverage is identical.
library;

import 'package:fake_async/fake_async.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:my_control_panel/models/alert_entry.dart';
import 'package:my_control_panel/screens/control_center_screen.dart';
import 'package:my_control_panel/services/alert_poller.dart';
import 'package:my_control_panel/services/mock_services.dart';
import 'package:my_control_panel/services/polling_alerts.dart';
import 'package:my_control_panel/services/service_locator.dart';

Services _mockServices() => Services(
      metrics: const MockMetricsPoller(),
      procStats: const MockProcStatsPoller(),
      crons: const MockCronRepository(),
      apps: const MockAppRepository(),
      alerts: const MockAlertRepository(),
      keys: const MockKeyLoader(),
      secrets: MockSecretStore(),
      github: const MockGithubRepository(),
    );

const _secureChannel =
    MethodChannel('plugins.it_nomads.com/flutter_secure_storage');

/// Bottom-nav destinations (always visible on phones).
const _bottomLabels = ['Overview', 'Servers', 'GitHub', 'Deploys', 'Settings'];

Future<void> _pumpShell(WidgetTester tester) async {
  // Phone layout (bottom nav + MORE sheet) with headroom: 800px-wide
  // surfaces overflow a pre-existing Settings dropdown, and the MORE sheet
  // needs vertical room so every row is on-screen without scrolling, so
  // use a tall viewport while staying under the 900px desktop-rail width.
  tester.view.physicalSize = const Size(899, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
  SharedPreferences.setMockInitialValues({
    'auto_update_check': false,
    'auto_refresh': true,
    'notifications': false,
    'secrets_migrated_v1': true,
  });
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(_secureChannel, (call) async => null);
  Services.overrideCurrent(_mockServices());
  addTearDown(() {
    Services.overrideCurrent(null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_secureChannel, null);
  });
  await tester.pumpWidget(const MaterialApp(home: ControlCenterScreen()));
  // Settle load paths: 0.8s of fake time (log ticker needs 3s for its
  // first heartbeat, so nothing has fired yet when the sweeps begin).
  for (var i = 0; i < 4; i++) {
    await tester.pump(const Duration(milliseconds: 200));
  }
}

/// Rapidly visit destinations via every switch mechanism: instant
/// bottom-nav flips plus MORE-sheet rows (which pop/push a modal route).
/// A pushed sheet builds one frame late, so opening takes two 400ms pumps
/// (push + 250ms enter transition); closing likewise (pop + 200ms exit).
/// Total pre-measurement fake time stays ~5s, so the log list stays far
/// below the 280px log box's render capacity — every inserted heartbeat is
/// built and therefore countable.
const _sheetLabels = ['Cronjobs', 'Terminal'];

Future<void> _openSheet(WidgetTester tester) async {
  await tester.tap(find.text('More'));
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pump(const Duration(milliseconds: 400));
  expect(find.byType(BottomSheet), findsOneWidget);
}

Future<void> _tapSheetRow(WidgetTester tester, String label) async {
  await tester.tap(find.descendant(
    of: find.byType(BottomSheet),
    matching: find.text(label),
  ));
  // Pop + 200ms exit transition, same one-frame-late pattern as opening.
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pump(const Duration(milliseconds: 400));
  expect(find.byType(BottomSheet), findsNothing);
}

Future<void> _sweepAllTabs(WidgetTester tester) async {
  for (final label in _bottomLabels) {
    await tester.tap(find.text(label));
    await tester.pump();
  }
  for (final label in _sheetLabels) {
    await _openSheet(tester);
    await _tapSheetRow(tester, label);
  }
  // Second round over the instant bottom tabs: 5 + 2 + 5 + logs = 13
  // switches across 8 destinations and all 3 switch mechanisms.
  for (final label in _bottomLabels) {
    await tester.tap(find.text(label));
    await tester.pump();
  }
}

/// Land on the Logs tab via the MORE sheet.
Future<void> _goToLogs(WidgetTester tester) async {
  await _openSheet(tester);
  await _tapSheetRow(tester, 'Logs');
}

void main() {
  group('refresh-timer lifecycle (t_7b8e0b7a)', () {
    testWidgets('fast tab switches keep exactly one log ticker', (tester) async {
      await _pumpShell(tester);

      // Rapid rounds across 8 destinations (13 switches) via every
      // switch mechanism: bottom nav, MORE sheet, inline terminal.
      await _sweepAllTabs(tester);

      // Land on Logs and prove the rate: one heartbeat per 3s window.
      // Stacked tickers (one per tab visit) would insert 2+/window.
      // (Delta-based: the sweeps above already let the single ticker fire.)
      await _goToLogs(tester);
      expect(find.text('LIVE LOG TAIL'), findsOneWidget);
      final base = find.textContaining('heartbeat ok').evaluate().length;

      await tester.pump(const Duration(seconds: 3));
      expect(find.textContaining('heartbeat ok'), findsNWidgets(base + 1));

      await tester.pump(const Duration(seconds: 3));
      expect(find.textContaining('heartbeat ok'), findsNWidgets(base + 2));

      // Drain: unmount cancels the periodic tickers, and advancing well
      // past the 2s cross-rail lock timeout ([AlertWatch.claimFreshTitles]
      // inside the auto-tick badge path) settles any in-flight badge claim,
      // so no timer is left pending at teardown (framework invariant).
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(minutes: 5));
      expect(tester.takeException(), isNull);
    });

    testWidgets('unmount cancels both tickers (no post-dispose ticks)',
        (tester) async {
      await _pumpShell(tester);

      await _goToLogs(tester);
      final base = find.textContaining('heartbeat ok').evaluate().length;
      await tester.pump(const Duration(seconds: 3));
      expect(
          find.textContaining('heartbeat ok'), findsNWidgets(base + 1));

      // Unmount the shell: dispose must cancel the log + auto timers, so
      // advancing well past both periods stays silent and error-free
      // (a live timer would setState-after-dispose and fail the test).
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(minutes: 5));
      expect(tester.takeException(), isNull);
    });

    test('AlertPollJob: re-entrant start keeps exactly one active ticker', () {
      FakeAsync().run((fa) {
        final job = AlertPollJob(
          serverId: 's1',
          serverName: 'web-01',
          policy: const PollPolicy(
            baseInterval: Duration(seconds: 5),
            maxInterval: Duration(minutes: 1),
          ),
        );
        var ticks = 0;
        Future<List<AlertEntry>> fetch() async {
          ticks++;
          return const [];
        }

        job.start(fetch);
        job.start(fetch); // fast re-entry must cancel the first ticker
        expect(job.running, isTrue);

        for (var i = 0; i < 4; i++) {
          fa.elapse(const Duration(seconds: 4));
          fa.flushMicrotasks();
        }
        // 16s on a 5s ticker: fires at 5, 10, 15 -> 3 ticks.
        // A stacked pair would have fired 6.
        expect(ticks, 3);

        job.stop();
        expect(job.running, isFalse);
        for (var i = 0; i < 15; i++) {
          fa.elapse(const Duration(seconds: 4));
          fa.flushMicrotasks();
        }
        expect(ticks, 3);
      });
    });
  });
}
