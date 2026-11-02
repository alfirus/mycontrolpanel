// SPDX-License-Identifier: MIT
/// Quiet-hours evaluation for the tray shell (Elizabeth, TM-4 support).
///
/// Window math + pref keys are Kira's `QuietHours`
/// (`lib/theme/alert_tokens.dart`, `feat/alert-tray-ux` #135 — converged,
/// not forked): this file adds only what the tray shell needs on top —
/// the one-shot "mute until morning" pref (menu §7.2 row 3, which never
/// rewrites the user's window), prefs I/O, and the shared suppress
/// decision. Kira's contract (§5) stays verbatim:
///
/// - Pref keys `alerts_quiet_hours_enabled/_start_minutes/_end_minutes`.
/// - Default OFF; default window 22:00–07:00 local.
/// - Overnight wrap supported; `start == end` means "never quiet".
/// - Critical does NOT punch through in Beta.2.
///
/// Pure logic ([isQuietAt]) delegates to `QuietHours.isQuietAt`; the
/// prefs shell is a thin async layer over `SharedPreferences` (mocked in
/// tests via `setMockInitialValues`).
library;

import 'package:shared_preferences/shared_preferences.dart';

import '../theme/alert_tokens.dart' show QuietHours;

/// Quiet-hours prefs + one-shot mute (tray notify-layer enforcement).
abstract class TrayQuietHours {
  /// Shared pref keys (Kira's `QuietHours` — aliases, never forks).
  static const enabledKey = QuietHours.prefEnabledKey;
  static const startMinutesKey = QuietHours.prefStartKey;
  static const endMinutesKey = QuietHours.prefEndKey;

  /// One-shot mute (slice interpretation of the §7.2 "Mute until morning"
  /// menu row): epoch ms until which toasts stay suppressed. Kept separate
  /// from the quiet window so one tap never rewrites the user's window.
  static const mutedUntilMsKey = 'tray_muted_until_ms';

  /// Default window 22:00–07:00 local (Kira §5).
  static const defaultStartMinutes = QuietHours.defaultStartMinutes;
  static const defaultEndMinutes = QuietHours.defaultEndMinutes;

  static QuietHours _window({
    required bool enabled,
    required int startMinutes,
    required int endMinutes,
  }) =>
      QuietHours(
        enabled: enabled,
        startHour: (startMinutes ~/ 60) % 24,
        startMinute: startMinutes % 60,
        endHour: (endMinutes ~/ 60) % 24,
        endMinute: endMinutes % 60,
      );

  /// Pure: true when [now] falls inside the quiet window.
  /// [startMinutes]/[endMinutes] are minutes-since-midnight local.
  /// `start == end` ⇒ never quiet (never "always").
  static bool isQuietAt({
    required DateTime now,
    required bool enabled,
    required int startMinutes,
    required int endMinutes,
  }) =>
      _window(
        enabled: enabled,
        startMinutes: startMinutes,
        endMinutes: endMinutes,
      ).isQuietAt(now);

  /// Pure: one-shot mute active at [now] given the stored epoch-ms stamp.
  static bool isMutedAt({required DateTime now, required int? mutedUntilMs}) {
    if (mutedUntilMs == null || mutedUntilMs <= 0) return false;
    return now.millisecondsSinceEpoch < mutedUntilMs;
  }

  /// Pure: next 07:00 local after [now] (the "Mute until morning" target).
  static DateTime nextMorning(DateTime now) {
    var morning =
        DateTime(now.year, now.month, now.day, 7);
    if (!morning.isAfter(now)) {
      morning = morning.add(const Duration(days: 1));
    }
    return morning;
  }

  /// Shared decision: suppress toasts at [now] (quiet window OR one-shot).
  static bool shouldSuppress({
    required DateTime now,
    required bool quietEnabled,
    required int startMinutes,
    required int endMinutes,
    required int? mutedUntilMs,
  }) {
    if (isMutedAt(now: now, mutedUntilMs: mutedUntilMs)) return true;
    return isQuietAt(
      now: now,
      enabled: quietEnabled,
      startMinutes: startMinutes,
      endMinutes: endMinutes,
    );
  }

  /// Shared decision for "now": quiet window OR one-shot mute active.
  /// Best-effort (prefs failure ⇒ not suppressed); never throws.
  static Future<bool> suppressedNow({DateTime? now}) async {
    try {
      final q = await read();
      return shouldSuppress(
        now: now ?? DateTime.now(),
        quietEnabled: q.enabled,
        startMinutes: q.start,
        endMinutes: q.end,
        mutedUntilMs: q.mutedUntil,
      );
    } catch (_) {
      return false;
    }
  }

  /// Read the current quiet state from prefs (best-effort, never throws).
  static Future<({bool enabled, int start, int end, int? mutedUntil})>
      read() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return (
        enabled: prefs.getBool(enabledKey) ?? false,
        start: prefs.getInt(startMinutesKey) ?? defaultStartMinutes,
        end: prefs.getInt(endMinutesKey) ?? defaultEndMinutes,
        mutedUntil: prefs.getInt(mutedUntilMsKey),
      );
    } catch (_) {
      return (
        enabled: false,
        start: defaultStartMinutes,
        end: defaultEndMinutes,
        mutedUntil: null,
      );
    }
  }

  /// One-tap "Mute until morning": stamp the one-shot mute (never touches
  /// the quiet window). Returns the mute target.
  static Future<DateTime> muteUntilMorning({DateTime? now}) async {
    final at = now ?? DateTime.now();
    final target = nextMorning(at);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(
          mutedUntilMsKey, target.millisecondsSinceEpoch);
    } catch (_) {}
    return target;
  }

  /// Clear the one-shot mute ("Unmute").
  static Future<void> clearMute() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(mutedUntilMsKey);
    } catch (_) {}
  }
}
