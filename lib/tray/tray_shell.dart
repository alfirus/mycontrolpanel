// SPDX-License-Identifier: MIT
/// Desktop tray shell (Elizabeth, TM-3/TM-4 slice).
///
/// Owns the tray icon + menu + minimize-to-tray behavior per Kira's
/// `docs/design/06-alert-tray-ux.md` §7 (states, menu order, restore,
/// denied/opt-out), while the headless tick keeps polling underneath.
/// The shell never polls by itself — it surfaces tick results
/// (`updateFromTick`) and enforces quiet-hours at the notify layer.
///
/// Plugin I/O is sealed behind [TrayOps]/[WindowOps] seams (production
/// impls use `tray_manager`/`window_manager`; tests use fakes — zero
/// plugin calls in `flutter test`). All decisions are pure and pinned in
/// `test/tray_shell_test.dart`:
///
/// - Icon precedence: `stale > quiet > firing > ok` (crash honesty first:
///   never a green icon on a dead poller; quiet is a user choice, stale
///   is system state).
/// - Menu order (§7.2): status header (read-only) → Open → Mute/Unmute →
///   Check now → Settings… → Quit.
/// - Close box (§7.4): consent ON ⇒ hide to tray (+ one-time hint);
///   consent OFF ⇒ real quit.
/// - Check-now rate limit: 1/min ([checkNowCooldown]).
/// - Stale flip: `consecutiveFailures >= 2` ⇒ stale icon (§7.4).
///
/// Notification action ids (§6, stable — Lisa/Nurul key deep-link payloads
/// off these; never rename without a migration note).
library;

// NOTE: both tray packages moved to a nativeapi core in their 0.6/0.8
// rewrites; the `legacy.dart` bridges below are the deliberate choice for
// this slice (stable async API, desktop CI builds green). The
// `deprecated_member_use` ignore is scoped to this file — migrate to the
// native API when the ecosystem settles (follow-up, not Beta.2 scope).
// ignore_for_file: deprecated_member_use
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tray_manager/legacy.dart';
import 'package:window_manager/legacy.dart';

import '../theme/alert_tokens.dart'
    show AlertNotificationActions, TrayIconState;

/// Tray icon states live in Kira's `lib/theme/alert_tokens.dart`
/// (`TrayIconState` — dot + shape + tooltip, never color-only). The shell
/// consumes them; icon assets (`iconAssetFor`) and tooltips stay here.

/// Menu row ids (stable; mirror the §6 action ids where they overlap).
abstract class TrayMenuIds {
  static const status = 'mcp.status';
  static const open = 'mcp.open';
  static const muteToggle = 'mcp.mute.till_morning';
  static const checkNow = 'mcp.check_now';
  static const settings = 'mcp.settings';
  static const quit = 'mcp.quit';
}

/// OS-toast action ids live in Kira's `lib/theme/alert_tokens.dart`
/// (`AlertNotificationActions` — stable, §6; Lisa/Nurul key deep-link
/// payloads off them; never rename without a migration note).
typedef TrayNotifyActions = AlertNotificationActions;

/// One tray menu row.
class TrayMenuRow {
  final String id;
  final String label;
  final bool enabled;

  const TrayMenuRow({
    required this.id,
    required this.label,
    this.enabled = true,
  });
}

/// Seam: tray icon/menu/tooltip sink (production = `tray_manager`).
abstract class TrayOps {
  Future<void> setIcon(TrayIconState state);
  Future<void> setTooltip(String tooltip);
  Future<void> setMenu(List<TrayMenuRow> rows);
}

/// Seam: window sink (production = `window_manager`).
abstract class WindowOps {
  Future<void> hide();
  Future<void> show();
  Future<void> focus();
  Future<void> setPreventClose(bool prevent);
  Future<void> destroy();
}

/// Production [TrayOps] over `tray_manager` (desktop only; guarded).
class TrayManagerOps implements TrayOps {
  @override
  Future<void> setIcon(TrayIconState state) async {
    try {
      await TrayManager.instance.setIcon(TrayShell.iconAssetFor(state));
    } catch (_) {}
  }

  @override
  Future<void> setTooltip(String tooltip) async {
    try {
      await TrayManager.instance.setToolTip(tooltip);
    } catch (_) {}
  }

  @override
  Future<void> setMenu(List<TrayMenuRow> rows) async {
    try {
      await TrayManager.instance.setContextMenu(Menu(items: [
        for (final r in rows)
          MenuItem(
            key: r.id,
            label: r.label,
            disabled: !r.enabled,
            onClick: (_) {
              TrayShell.onMenuClicked(r.id);
            },
          ),
      ]));
    } catch (_) {}
  }
}

/// Production [WindowOps] over `window_manager` (desktop only; guarded).
class WindowManagerOps implements WindowOps {
  @override
  Future<void> hide() async {
    try {
      await windowManager.hide();
    } catch (_) {}
  }

  @override
  Future<void> show() async {
    try {
      await windowManager.show();
    } catch (_) {}
  }

  @override
  Future<void> focus() async {
    try {
      await windowManager.focus();
    } catch (_) {}
  }

  @override
  Future<void> setPreventClose(bool prevent) async {
    try {
      await windowManager.setPreventClose(prevent);
    } catch (_) {}
  }

  @override
  Future<void> destroy() async {
    try {
      await windowManager.destroy();
    } catch (_) {}
  }
}

/// Menu callbacks (wired by `main()`; recorded by fakes in tests).
class TrayCallbacks {
  final Future<void> Function()? onOpen;
  final Future<void> Function()? onCheckNow;
  final Future<void> Function()? onToggleMute;
  final Future<void> Function()? onOpenSettings;
  final Future<void> Function()? onQuit;

  const TrayCallbacks({
    this.onOpen,
    this.onCheckNow,
    this.onToggleMute,
    this.onOpenSettings,
    this.onQuit,
  });
}

/// Tray shell: icon state + menu + close-box policy. All plugin I/O flows
/// through the injected [tray]/[window] seams.
class TrayShell with WindowListener {
  static const minimizeHintKey = 'tray_minimize_hint_shown';

  /// Minimum gap between manual "Check now" ticks (Kira §7.2).
  static const checkNowCooldown = Duration(minutes: 1);

  /// Consecutive tick failures before the icon flips stale (§7.4).
  static const staleAfterFailures = 2;

  final TrayOps tray;
  final WindowOps window;
  final TrayCallbacks callbacks;
  final DateTime Function() clock;

  int _lastCheckNowMs = 0;
  TrayIconState _state = TrayIconState.ok;
  bool _muted = false;

  // Last refresh facts (repaint after a mute toggle reuses them).
  int _firingCount = 0;
  int _consecutiveFailures = 0;
  bool _quietActive = false;
  String _quietUntil = '';
  String _staleDetail = '';
  bool _consentOn = false;

  /// Last menu-row id clicked (test hook; production routes via [route]).
  static String? lastClickedForTests;

  TrayIconState get state => _state;
  bool get muted => _muted;

  TrayShell({
    required this.tray,
    required this.window,
    this.callbacks = const TrayCallbacks(),
    DateTime Function()? clock,
  }) : clock = clock ?? DateTime.now;

  /// Tray icon asset per state (16px canvas, shape + color per Kira §7.1;
  /// Linux monochrome trays still read the glyph).
  static String iconAssetFor(TrayIconState state) =>
      'assets/tray/tray-${state.name}.png';

  /// Pure: icon state from tick facts. Precedence
  /// stale > quiet > firing > ok.
  static TrayIconState resolveState({
    required bool quietActive,
    required int firingCount,
    required int consecutiveFailures,
    required bool consentOn,
  }) {
    if (!consentOn) return TrayIconState.ok;
    if (consecutiveFailures >= staleAfterFailures) {
      return TrayIconState.stale;
    }
    if (quietActive) return TrayIconState.quiet;
    if (firingCount > 0) return TrayIconState.firing;
    return TrayIconState.ok;
  }

  /// Pure: tooltip per state (Kira §7.1 — always names the state).
  static String tooltipFor(
    TrayIconState state, {
    int firingCount = 0,
    String staleDetail = '',
    String quietUntil = '',
  }) {
    switch (state) {
      case TrayIconState.ok:
        return 'MyControlPanel — all clear';
      case TrayIconState.firing:
        return 'MyControlPanel — $firingCount alert${firingCount == 1 ? '' : 's'} firing';
      case TrayIconState.stale:
        final detail =
            staleDetail.isEmpty ? 'check failed' : staleDetail;
        return 'MyControlPanel — $detail';
      case TrayIconState.quiet:
        final until =
            quietUntil.isEmpty ? '' : ' until $quietUntil';
        return 'MyControlPanel — quiet$until';
    }
  }

  /// Pure: status-header row (read-only, Kira §7.2 row 1).
  static String statusHeader({
    required int firingCount,
    required String staleLabel,
  }) {
    final firing =
        firingCount == 0 ? 'all clear' : '$firingCount firing';
    return '● $firing · $staleLabel';
  }

  /// Pure: menu rows in §7.2 order (mute row toggles with [muted]).
  static List<TrayMenuRow> menuRows({
    required String statusLine,
    required bool muted,
  }) =>
      [
        TrayMenuRow(
            id: TrayMenuIds.status, label: statusLine, enabled: false),
        const TrayMenuRow(
            id: TrayMenuIds.open, label: 'Open MyControlPanel'),
        TrayMenuRow(
          id: TrayMenuIds.muteToggle,
          label: muted ? 'Unmute' : 'Mute until morning',
        ),
        const TrayMenuRow(
            id: TrayMenuIds.checkNow, label: 'Check now'),
        const TrayMenuRow(
            id: TrayMenuIds.settings, label: 'Settings…'),
        const TrayMenuRow(id: TrayMenuIds.quit, label: 'Quit'),
      ];

  /// Init the tray (call once from `main()` on desktop): prevent-close,
  /// default icon + menu, first paint from [initial].
  Future<void> init({
    required bool consentOn,
    int firingCount = 0,
    String staleLabel = 'never checked',
  }) async {
    live = this;
    try {
      await window.setPreventClose(true);
      windowManager.addListener(this);
    } catch (_) {}
    await refresh(
      firingCount: firingCount,
      consecutiveFailures: 0,
      quietActive: false,
      quietUntil: '',
      staleDetail: staleLabel,
      muted: false,
      consentOn: consentOn,
    );
  }

  /// Repaint icon + tooltip + menu from fresh tick facts.
  Future<void> refresh({
    required int firingCount,
    required int consecutiveFailures,
    required bool quietActive,
    required String quietUntil,
    required String staleDetail,
    required bool muted,
    required bool consentOn,
  }) async {
    _firingCount = firingCount;
    _consecutiveFailures = consecutiveFailures;
    _quietActive = quietActive;
    _quietUntil = quietUntil;
    _staleDetail = staleDetail;
    _muted = muted;
    _consentOn = consentOn;
    _state = resolveState(
      quietActive: quietActive,
      firingCount: firingCount,
      consecutiveFailures: consecutiveFailures,
      consentOn: consentOn,
    );
    await tray.setIcon(_state);
    await tray.setTooltip(tooltipFor(
      _state,
      firingCount: firingCount,
      staleDetail: staleDetail,
      quietUntil: quietUntil,
    ));
    await tray.setMenu(menuRows(
      statusLine: statusHeader(
        firingCount: firingCount,
        staleLabel: staleDetail,
      ),
      muted: muted,
    ));
  }

  /// Repaint from the last refresh facts (e.g. after a mute toggle flips
  /// quiet state without a new tick). No-op before the first [refresh].
  Future<void> repaint() => refresh(
        firingCount: _firingCount,
        consecutiveFailures: _consecutiveFailures,
        quietActive: _quietActive,
        quietUntil: _quietUntil,
        staleDetail: _staleDetail,
        muted: _muted,
        consentOn: _consentOn,
      );

  /// Route one menu click (production calls this from `MenuItem.onClick`
  /// via [onMenuClicked]; rate-limits check-now; never throws).
  Future<bool> route(String id) async {
    lastClickedForTests = id;
    try {
      switch (id) {
        case TrayMenuIds.open:
          await callbacks.onOpen?.call();
          return true;
        case TrayMenuIds.checkNow:
          final nowMs = clock().millisecondsSinceEpoch;
          if (nowMs - _lastCheckNowMs <
              checkNowCooldown.inMilliseconds) {
            return false;
          }
          _lastCheckNowMs = nowMs;
          await callbacks.onCheckNow?.call();
          return true;
        case TrayMenuIds.muteToggle:
          await callbacks.onToggleMute?.call();
          return true;
        case TrayMenuIds.settings:
          await callbacks.onOpenSettings?.call();
          return true;
        case TrayMenuIds.quit:
          await callbacks.onQuit?.call();
          return true;
        default:
          return false;
      }
    } catch (_) {
      return false;
    }
  }

  /// Menu-click entry point (static so `MenuItem.onClick` closures stay
  /// tiny). The live shell is registered by [init] in `main()`.
  static TrayShell? live;
  static Future<void> onMenuClicked(String id) async {
    try {
      await live?.route(id);
    } catch (_) {}
  }

  /// Close-box policy (§7.4): consent ON ⇒ hide to tray (returns true and
  /// whether the one-time hint should show); consent OFF ⇒ real quit
  /// (returns false — caller destroys the window). Never throws.
  Future<({bool hide, bool showHint})> handleClose({
    required bool consentOn,
  }) async {
    if (!consentOn) return (hide: false, showHint: false);
    try {
      await window.hide();
    } catch (_) {}
    var showHint = false;
    try {
      final prefs = await SharedPreferences.getInstance();
      showHint = !(prefs.getBool(minimizeHintKey) ?? false);
      if (showHint) {
        await prefs.setBool(minimizeHintKey, true);
      }
    } catch (_) {}
    return (hide: true, showHint: showHint);
  }

  /// Restore + focus the existing window (§7.4 window-restore).
  Future<void> restoreWindow() async {
    try {
      await window.show();
    } catch (_) {}
    try {
      await window.focus();
    } catch (_) {}
  }

  /// `window_manager` close interception: hide-to-tray per [handleClose].
  @override
  Future<void> onWindowClose() async {
    if (kIsWeb) return;
    var consent = false;
    try {
      final prefs = await SharedPreferences.getInstance();
      consent = prefs.getBool('background_alerts') ?? false;
    } catch (_) {}
    final decision = await handleClose(consentOn: consent);
    if (!decision.hide) {
      try {
        await window.destroy();
      } catch (_) {}
    }
  }
}
