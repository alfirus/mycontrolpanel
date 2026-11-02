// SPDX-License-Identifier: MIT
/// Alert + tray-mode UX tokens (Kira, UI/UX).
///
/// Build-ready contract for Nurul's inbox (t_7ba899fe) and the tray shell
/// (TM-4): severity spec, copy tone, grouping/dedup, quiet-hours,
/// notification actions, tray states, and the a11y acceptance bar.
///
/// Design source of truth: `docs/design/06-alert-tray-ux.md`.
/// This file is the *executable* half of that doc — pure Dart (+ [Color]
/// constants only) so it is unit-testable with no plugins. Policy reuse:
/// thresholds stay in `AlertRules`/`Thresholds`, payloads stay in
/// `NotificationHook.build`; this file only maps those onto user-visible
/// copy, color, and behavior.
library;

import 'package:flutter/material.dart';

import 'app_theme.dart';

/// User-visible alert severity. Maps 1:1 onto `AlertSeverity` in
/// `polling_alerts.dart` plus the CI/infra kinds `AlertRules` emits.
enum TrayAlertSeverity { critical, warning, info }

/// Closed-app tray icon state. The shell never polls by itself — it
/// surfaces headless-tick results (tray-mode plan TM-4).
enum TrayIconState { ok, firing, stale, quiet }

/// OS-notification actions. Ids are stable contract: Lisa (headless CLI)
/// and Elizabeth (tray helper) key deep-link payloads off these strings.
/// Never rename without a migration note in the design doc.
abstract class AlertNotificationActions {
  static const open = 'mcp.open';
  static const acknowledge = 'mcp.ack';
  static const snooze1h = 'mcp.snooze.1h';
  static const muteUntilMorning = 'mcp.mute.till_morning';

  /// Tap on the notification body (not a button) — opens the inbox.
  static const tapDefault = open;

  /// All action ids, for payload validation on both rails.
  static const List<String> all = [
    open,
    acknowledge,
    snooze1h,
    muteUntilMorning,
  ];

  /// Button labels, in display order. Short verbs — OS rails truncate
  /// after ~3 buttons / ~14 chars per label.
  static const Map<String, String> labels = {
    open: 'Open',
    acknowledge: 'Ack',
    snooze1h: 'Snooze 1h',
    muteUntilMorning: 'Mute night',
  };
}

/// Severity → user-visible token mapping.
///
/// Color rule (spec 01): status meaning uses `success/warning/critical/info`
/// ONLY — never the `accent*` brand set. Every pair below is AA (≥4.5:1)
/// on `surface0`, verified in `test/alert_tokens_test.dart`.
abstract class AppAlertTokens {
  /// Status color per severity.
  static const Map<TrayAlertSeverity, Color> color = {
    TrayAlertSeverity.critical: AppColors.critical,
    TrayAlertSeverity.warning: AppColors.warning,
    TrayAlertSeverity.info: AppColors.info,
  };

  /// Material icon per severity (name-stable strings for the inbox + tray).
  static const Map<TrayAlertSeverity, String> icon = {
    TrayAlertSeverity.critical: 'error',
    TrayAlertSeverity.warning: 'warning',
    TrayAlertSeverity.info: 'info',
  };

  /// Short pill label per severity (uppercase in UI via the pill widget).
  static const Map<TrayAlertSeverity, String> pill = {
    TrayAlertSeverity.critical: 'Critical',
    TrayAlertSeverity.warning: 'Warning',
    TrayAlertSeverity.info: 'Info',
  };

  /// Screen-reader label per severity. Never color-only (spec 04 §3.1).
  static const Map<TrayAlertSeverity, String> semanticLabel = {
    TrayAlertSeverity.critical: 'Critical alert',
    TrayAlertSeverity.warning: 'Warning alert',
    TrayAlertSeverity.info: 'Informational alert',
  };

  /// Tray icon state → status color. `quiet` reuses `textSecondary`
  /// (deliberately muted: the app is intentionally silent).
  /// `stale` reuses `warning` (stale is actionable uncertainty, not error).
  static const Map<TrayIconState, Color> trayColor = {
    TrayIconState.ok: AppColors.success,
    TrayIconState.firing: AppColors.critical,
    TrayIconState.stale: AppColors.warning,
    TrayIconState.quiet: AppColors.textSecondary,
  };

  /// Screen-reader label per tray state.
  static const Map<TrayIconState, String> traySemanticLabel = {
    TrayIconState.ok: 'MyControlPanel: all systems normal',
    TrayIconState.firing: 'MyControlPanel: alert firing',
    TrayIconState.stale: 'MyControlPanel: status stale, last check shown',
    TrayIconState.quiet: 'MyControlPanel: quiet hours, alerts paused',
  };
}

/// Copy tone per severity. Verbatim strings — Nurul uses these directly.
/// Tone rule: headlines state WHAT is true (≤48 chars, no blame, no jokes
/// at critical); bodies state WHY + WHAT TO DO (≤140 chars, one action).
abstract class AlertCopy {
  /// OS-notification titles per severity (`NotificationHook.build` title).
  static const Map<TrayAlertSeverity, String> notificationTitle = {
    TrayAlertSeverity.critical: 'MyControlPanel: action needed',
    TrayAlertSeverity.warning: 'MyControlPanel: warning',
    TrayAlertSeverity.info: 'MyControlPanel: back to normal',
  };

  /// Inbox empty-state headline/body (follows StateView pattern, spec 04).
  static const inboxClearHeadline = 'ALL CLEAR';
  static const inboxClearBody =
      'No firing alerts across your servers. New warnings and failures land here.';

  /// Snooze / ack confirmations (snack bar, ≤80 chars).
  static const ackConfirm = 'Acknowledged — removed from the firing list.';
  static const snoozeConfirm = 'Snoozed for 1 hour — fires again if still down.';

  /// First-run / onboarding consent copy. Extends (never replaces)
  /// `BackgroundAlerts.consentCopy` with the tray sentence.
  static const onboardingTitle = 'Stay notified when the app is closed';
  static const onboardingBody =
      'MyControlPanel can minimise to the tray and check your servers '
      'every ~15 min in the background. You choose: toast for critical '
      'only, or all severities — and quiet hours pause everything.';
  static const onboardingPrimary = 'ENABLE BACKGROUND ALERTS';
  static const onboardingSecondary = 'NOT NOW';

  /// Permission-denied (OS notification prompt refused).
  static const permissionDeniedHeadline = 'NOTIFICATIONS BLOCKED';
  static const permissionDeniedBody =
      'The OS declined notification permission. Alerts still collect in '
      'the inbox — re-enable per-app notifications in OS Settings to get '
      'toasts again.';
  static const permissionDeniedAction = 'OPEN OS SETTINGS';

  /// Opt-out (user turns the shared `background_alerts` toggle OFF).
  static const optOutHeadline = 'BACKGROUND ALERTS OFF';
  static const optOutBody =
      'Closed-app checks stop after the current tick. The in-app watcher '
      'keeps working while the app is open. Re-enable anytime in Settings.';
}

/// Quiet-hours window. Pure value type — no prefs/plugin access here;
/// persistence + scheduling stay with Lisa/Zara. Overnight wrap supported
/// (e.g. 22:00 → 07:00). All times local.
class QuietHours {
  final int startHour;
  final int startMinute;
  final int endHour;
  final int endMinute;
  final bool enabled;

  const QuietHours({
    this.startHour = 22,
    this.startMinute = 0,
    this.endHour = 7,
    this.endMinute = 0,
    this.enabled = false,
  });

  /// Shared pref keys (owned by the Settings/tray wiring, declared here
  /// so inbox + tray helper read the same keys). Enforcement lives at the
  /// NOTIFY layer (tray helper suppresses toasts while quiet) — the
  /// headless tick itself always runs to completion per the frozen TM-1
  /// contract (`docs/specs/headless-cli-contract.md`), so the inbox stays
  /// complete and the staleness stamp stays honest.
  static const prefEnabledKey = 'alerts_quiet_hours_enabled';
  static const prefStartKey = 'alerts_quiet_hours_start_minutes';
  static const prefEndKey = 'alerts_quiet_hours_end_minutes';

  /// Default window, minutes-since-midnight form.
  static const defaultStartMinutes = 22 * 60;
  static const defaultEndMinutes = 7 * 60;

  static int toMinutes(int hour, int minute) => hour * 60 + minute;

  int get startMinutes => toMinutes(startHour, startMinute);
  int get endMinutes => toMinutes(endHour, endMinute);

  /// True when [at] (local) falls inside the window. Disabled → false.
  /// Start == end means "never quiet" (zero-length window), never "always".
  bool isQuietAt(DateTime at) {
    if (!enabled) return false;
    if (startMinutes == endMinutes) return false;
    final now = at.hour * 60 + at.minute;
    if (startMinutes < endMinutes) {
      return now >= startMinutes && now < endMinutes;
    }
    return now >= startMinutes || now < endMinutes; // overnight wrap
  }

  /// Settings row summary, e.g. "22:00 – 07:00" or "Off".
  String label() {
    if (!enabled) return 'Off';
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(startHour)}:${two(startMinute)} – '
        '${two(endHour)}:${two(endMinute)}';
  }
}

/// Grouping + dedup contract shared by the inbox and the headless tick.
///
/// Rules (TM-5, exactly-once rail):
/// 1. Identity: `AlertWatch.keyFor` verbatim — one shared last-seen set,
///    never a second inbox-side set.
/// 2. Grouping is PRESENTATION only: group fresh titles by server for the
///    inbox list; the OS toast still goes through `NotificationHook.build`
///    (max 3 + "…and N more") so the headless payload shape never changes.
/// 3. Cap: at most [maxGroups] server groups, [maxPerGroup] items each;
///    overflow folds into a "+N more" tail line.
abstract class AlertGrouping {
  static const int maxGroups = 4;
  static const int maxPerGroup = 5;

  /// Group `host: title` fresh titles by host. Titles without a
  /// ` (host)` suffix (e.g. `CI failed: …`) go under [ungroupedKey].
  static const ungroupedKey = 'Other';

  static final RegExp _hostSuffix = RegExp(r'^(.*) \(([^()]+)\)$');

  static Map<String, List<String>> groupByHost(List<String> freshTitles) {
    final groups = <String, List<String>>{};
    for (final raw in freshTitles) {
      final t = raw.trim();
      if (t.isEmpty) continue;
      final m = _hostSuffix.firstMatch(t);
      final host = m?.group(2) ?? ungroupedKey;
      (groups[host] ??= <String>[]).add(t);
    }
    return groups;
  }

  /// Flatten groups back to a capped display list. Group order follows
  /// first appearance; each group keeps its own order and cap.
  static List<String> flattenForInbox(Map<String, List<String>> groups) {
    final out = <String>[];
    var overflow = 0;
    var groupCount = 0;
    for (final entry in groups.entries) {
      groupCount++;
      if (groupCount > maxGroups) {
        overflow += entry.value.length;
        continue;
      }
      final items = entry.value;
      out.addAll(items.take(maxPerGroup));
      overflow += items.length > maxPerGroup ? items.length - maxPerGroup : 0;
    }
    if (overflow > 0) out.add('…and $overflow more');
    return out;
  }
}

/// Settings IA order for the Alerts section (spec 06 §4). Single source
/// so Settings + onboarding + docs list rows in the same order.
abstract class AlertSettingsOrder {
  static const List<String> rows = [
    'background_alerts', // shared consent toggle (existing, default OFF)
    'severity_filter', // which severities toast: critical-only | all
    'quiet_hours', // QuietHours window (default OFF)
    'per_metric_thresholds', // disk warn/crit, brute-force counts (Nurul)
    'battery_prompt', // Android explainer (existing copy)
    'last_checked', // stale-tolerant status line (existing, read-only)
  ];
}

/// A11y acceptance bar (WCAG 2.2 AA, store readiness). Constants Nurul's
/// widget tests assert against.
abstract class AlertA11y {
  /// Minimum touch target per WCAG 2.5.8 (also spec 04 §3.3).
  static const double minTarget = 48.0;

  /// Minimum body-copy size for alert text (spec 01: muted 9-11px fails).
  static const double minBodySize = 11.0;

  /// Body copy must be `textSecondary` or brighter — never `textMuted`.
  static const Color minBodyColor = AppColors.textSecondary;

  /// Minimum contrast for meaningful text (WCAG AA normal text).
  static const double minTextContrast = 4.5;

  /// Loading + error arrivals announce via a live region (spec 04 §3.2).
  static const String loadingAnnouncement = 'Loading alerts';
  static const String errorAnnouncement = 'Alert sync failed';
}
