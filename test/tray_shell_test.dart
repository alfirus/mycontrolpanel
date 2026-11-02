// SPDX-License-Identifier: MIT
// Tray shell tests (Elizabeth): Kira §7 states/menu/restore/rate-limit.
// All plugin I/O flows through fakes — zero `tray_manager` /
// `window_manager` calls in `flutter test`.
import 'package:flutter_test/flutter_test.dart';
import 'package:my_control_panel/theme/alert_tokens.dart'
    show TrayIconState;
import 'package:my_control_panel/tray/tray_shell.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FakeTray implements TrayOps {
  TrayIconState? icon;
  String? tooltip;
  List<TrayMenuRow>? menu;
  var sets = 0;

  @override
  Future<void> setIcon(TrayIconState state) async {
    icon = state;
    sets++;
  }

  @override
  Future<void> setMenu(List<TrayMenuRow> rows) async {
    menu = rows;
  }

  @override
  Future<void> setTooltip(String t) async => tooltip = t;
}

class FakeWindow implements WindowOps {
  var hidden = 0;
  var shown = 0;
  var focused = 0;
  var preventCloseCalls = <bool>[];
  var destroyed = 0;

  @override
  Future<void> destroy() async => destroyed++;

  @override
  Future<void> focus() async => focused++;

  @override
  Future<void> hide() async => hidden++;

  @override
  Future<void> setPreventClose(bool prevent) async =>
      preventCloseCalls.add(prevent);

  @override
  Future<void> show() async => shown++;
}

void main() {
  group('resolveState precedence (stale > quiet > firing > ok)', () {
    TrayIconState s({
      bool quiet = false,
      int firing = 0,
      int failures = 0,
      bool consent = true,
    }) =>
        TrayShell.resolveState(
          quietActive: quiet,
          firingCount: firing,
          consecutiveFailures: failures,
          consentOn: consent,
        );

    test('ok when clean + consent on', () {
      expect(s(), TrayIconState.ok);
    });

    test('consent OFF is ok (no icon alarm without polling)', () {
      expect(s(firing: 3, failures: 5, consent: false),
          TrayIconState.ok);
    });

    test('firing beats clean', () {
      expect(s(firing: 2), TrayIconState.firing);
    });

    test('quiet beats firing (user choice)', () {
      expect(s(quiet: true, firing: 2), TrayIconState.quiet);
    });

    test('stale beats everything (crash honesty)', () {
      expect(s(quiet: true, firing: 2, failures: 2),
          TrayIconState.stale);
      expect(s(failures: 3), TrayIconState.stale);
      expect(s(failures: 1, firing: 1), TrayIconState.firing,
          reason: 'single failure is not stale yet (§7.4: twice)');
    });
  });

  group('tooltips + status header name the state (§7.1)', () {
    test('every state carries a semantic label', () {
      expect(TrayShell.tooltipFor(TrayIconState.ok),
          'MyControlPanel — all clear');
      expect(TrayShell.tooltipFor(TrayIconState.firing, firingCount: 2),
          'MyControlPanel — 2 alerts firing');
      expect(TrayShell.tooltipFor(TrayIconState.firing, firingCount: 1),
          'MyControlPanel — 1 alert firing');
      expect(
          TrayShell.tooltipFor(TrayIconState.stale,
              staleDetail: 'last checked 42m ago'),
          'MyControlPanel — last checked 42m ago');
      expect(
          TrayShell.tooltipFor(TrayIconState.quiet,
              quietUntil: '07:00'),
          'MyControlPanel — quiet until 07:00');
    });

    test('status header reads firing + staleness', () {
      expect(
          TrayShell.statusHeader(
              firingCount: 2, staleLabel: 'last checked 3m ago'),
          '● 2 firing · last checked 3m ago');
      expect(
          TrayShell.statusHeader(
              firingCount: 0, staleLabel: 'last checked just now'),
          '● all clear · last checked just now');
    });
  });

  group('menu order (§7.2)', () {
    test('status → open → mute → check → settings → quit', () {
      final rows = TrayShell.menuRows(
          statusLine: '● all clear · now', muted: false);
      expect(
          rows.map((r) => r.id),
          [
            TrayMenuIds.status,
            TrayMenuIds.open,
            TrayMenuIds.muteToggle,
            TrayMenuIds.checkNow,
            TrayMenuIds.settings,
            TrayMenuIds.quit,
          ]);
      expect(rows.first.enabled, isFalse,
          reason: 'status header is read-only');
      expect(rows[2].label, 'Mute until morning');
      expect(
          TrayShell.menuRows(statusLine: 'x', muted: true)[2].label,
          'Unmute');
    });
  });

  group('routing + check-now rate limit', () {
    test('open/settings/quit/mute dispatch; check-now 1/min', () async {
      final seen = <String>[];
      var now = DateTime(2026, 5, 4, 12, 0);
      final shell = TrayShell(
        tray: FakeTray(),
        window: FakeWindow(),
        clock: () => now,
        callbacks: TrayCallbacks(
          onOpen: () async => seen.add('open'),
          onCheckNow: () async => seen.add('check'),
          onToggleMute: () async => seen.add('mute'),
          onOpenSettings: () async => seen.add('settings'),
          onQuit: () async => seen.add('quit'),
        ),
      );
      expect(await shell.route(TrayMenuIds.open), isTrue);
      expect(await shell.route(TrayMenuIds.settings), isTrue);
      expect(await shell.route(TrayMenuIds.muteToggle), isTrue);
      expect(await shell.route(TrayMenuIds.checkNow), isTrue);
      // Second check within the minute is dropped (§7.2).
      expect(await shell.route(TrayMenuIds.checkNow), isFalse);
      now = now.add(const Duration(seconds: 61));
      expect(await shell.route(TrayMenuIds.checkNow), isTrue);
      expect(await shell.route(TrayMenuIds.quit), isTrue);
      expect(await shell.route('mcp.bogus'), isFalse);
      expect(seen,
          ['open', 'settings', 'mute', 'check', 'check', 'quit']);
    });

    test('refresh paints icon + tooltip + menu through the seam', () async {
      final tray = FakeTray();
      final shell = TrayShell(tray: tray, window: FakeWindow());
      await shell.refresh(
        firingCount: 2,
        consecutiveFailures: 0,
        quietActive: false,
        quietUntil: '',
        staleDetail: 'last checked 3m ago',
        muted: false,
        consentOn: true,
      );
      expect(shell.state, TrayIconState.firing);
      expect(tray.icon, TrayIconState.firing);
      expect(tray.tooltip, contains('2 alerts firing'));
      expect(tray.menu!.map((r) => r.id).length, 6);
      expect(tray.menu!.first.label, contains('2 firing'));
    });
  });

  group('close-box policy (§7.4)', () {
    test('consent ON hides + shows the hint exactly once', () async {
      SharedPreferences.setMockInitialValues({});
      final window = FakeWindow();
      final shell = TrayShell(tray: FakeTray(), window: window);
      final first = await shell.handleClose(consentOn: true);
      expect(first.hide, isTrue);
      expect(first.showHint, isTrue);
      expect(window.hidden, 1);
      final second = await shell.handleClose(consentOn: true);
      expect(second.hide, isTrue);
      expect(second.showHint, isFalse,
          reason: 'one-time explainer toast');
    });

    test('consent OFF closes for real', () async {
      SharedPreferences.setMockInitialValues({});
      final window = FakeWindow();
      final shell = TrayShell(tray: FakeTray(), window: window);
      final d = await shell.handleClose(consentOn: false);
      expect(d.hide, isFalse);
      expect(window.hidden, 0);
    });

    test('restoreWindow shows + focuses', () async {
      final window = FakeWindow();
      final shell = TrayShell(tray: FakeTray(), window: window);
      await shell.restoreWindow();
      expect(window.shown, 1);
      expect(window.focused, 1);
    });
  });
}
