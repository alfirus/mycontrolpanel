// SPDX-License-Identifier: MIT
/// Desktop local notifications (beta.1, owner ruling 2026-10-30).
///
/// This file owns the *desktop third* of docs/design/05-background-alerting.md
/// §3: `flutter_local_notifications` show calls on Windows (win_toast path),
/// Linux (notify-send path) and macOS (user-allow on first fire), driven by
/// the existing in-app timer while the app runs (the control center fans
/// fresh titles to this rail on every auto-refresh tick).
///
/// Policy reuse (no new payload formats, no new policy):
/// - Poll/backoff semantics stay in [PollPolicy] verbatim (the in-app
///   [AlertPollJob.tick] path already encodes them; this rail only renders).
/// - Thresholds stay in [Thresholds]/[AlertRules] verbatim.
/// - Every user-visible payload is built by [NotificationHook.build]
///   (`{title, body}`, max 3 + "…and N more"). [buildLocalPayload] is the
///   single choke point, mirroring `BackgroundAlerts.buildLocalPayload`.
///
/// Consent (shared row, not a second toggle): this rail is gated on the
/// SAME `background_alerts` pref as mobile ([BackgroundAlerts.prefEnabledKey],
/// default OFF, [BackgroundAlerts.consentCopy]). The Settings UI is the
/// shared [BackgroundAlertConsentTile] row — desktop shows the toggle with
/// neither the Android battery tip nor the iOS tip.
///
/// Closed-app delivery (Windows Task Scheduler / systemd user timer / macOS
/// LaunchAgent headless poll) is DEFERRED to tray-mode work per the owner
/// ruling — there is deliberately no scheduler wiring here. [closedAppNote]
/// is the single stub entry-point note pointing at that future work; desktop
/// keeps the in-app timer path only in beta.1.
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'alert_inbox_store.dart';
import 'background_alerts.dart';
import 'polling_alerts.dart';

/// Desktop `flutter_local_notifications` rail (Windows/Linux/macOS).
abstract class DesktopAlerts {
  /// App name shown in the Windows toast + Linux notification.
  static const appName = 'MyControlPanel';

  /// Windows (win_toast path): AppUserModelId in
  /// CompanyName.ProductName form — toasts without one are silently dropped.
  static const windowsAppUserModelId = 'Alfirus.MyControlPanel';

  /// Windows (win_toast path): stable GUID identifying the notification
  /// activation callback. Fixed once — changing it orphans dispatched
  /// toasts on upgrade.
  static const windowsGuid = '6f9d2b4a-8c1e-4f3a-b5d6-7e8f9a0b1c2d';

  /// Linux (notify-send path): name of the default action (usually fired by
  /// clicking the notification; servers are free not to display it).
  static const linuxDefaultActionName = 'Open MyControlPanel';

  /// Stub entry-point note for the deferred closed-app work: Windows Task
  /// Scheduler / systemd user timer / macOS LaunchAgent headless poll all
  /// land in tray-mode work, NOT beta.1. Desktop keeps the in-app timer
  /// path only (owner ruling 2026-10-30, binding).
  static const closedAppNote =
      'Closed-app delivery (Windows Task Scheduler / systemd user timer / '
      'macOS LaunchAgent headless poll) is deferred to tray-mode work — '
      'desktop uses the in-app timer path only in beta.1.';

  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  static bool _pluginReady = false;

  /// True only on the platforms this rail serves. Guard every show call
  /// with this (mobile keeps the WorkManager rail in [BackgroundAlerts]).
  static bool get isSupportedPlatform {
    if (kIsWeb) return false;
    return Platform.isWindows || Platform.isLinux || Platform.isMacOS;
  }

  /// Shared consent with mobile: the same `background_alerts` pref, default
  /// OFF. One toggle in Settings, not a second desktop-only pref.
  static Future<bool> isEnabled() => BackgroundAlerts.isEnabled();

  /// Record an in-app check against the shared staleness stamp
  /// ([BackgroundAlerts.prefLastCheckKey]) — on desktop the in-app timer IS
  /// the beta.1 rail, so the alerts-surface "last checked …" line stays
  /// honest while the app runs. Called on every fan-out tick, even with zero
  /// fresh titles (staleness is honest, never silent). Never throws.
  static Future<void> recordCheck([DateTime? at]) =>
      BackgroundAlerts.recordCheck(at);

  /// Call once from `main()` (guarded try/catch there too): inits the
  /// plugin + fires the macOS user-allow prompt on first run when the user
  /// opted in. No-op off desktop / when opted out; never throws.
  static Future<void> ensureInitialized() async {
    if (!isSupportedPlatform) return;
    if (!await isEnabled()) return;
    try {
      await initNotifications();
      await requestPermissions();
    } catch (_) {}
  }

  /// Init the notifications plugin with per-platform settings:
  /// - Windows: win_toast via [windowsAppUserModelId]/[windowsGuid].
  /// - Linux: notify-send path via [linuxDefaultActionName].
  /// - macOS: Darwin settings (user-allow prompt on first fire).
  /// Idempotent; safe to call anywhere (failures stay silent).
  ///
  /// Tap handling mirrors the mobile rail: the response callback stashes
  /// valid `mcp://inbox` payloads for the inbox to consume on
  /// launch/resume (Nurul t_7ba899fe).
  static Future<void> initNotifications() async {
    if (_pluginReady) return;
    try {
      const settings = InitializationSettings(
        macOS: DarwinInitializationSettings(),
        linux: LinuxInitializationSettings(
          defaultActionName: linuxDefaultActionName,
        ),
        windows: WindowsInitializationSettings(
          appName: appName,
          appUserModelId: windowsAppUserModelId,
          guid: windowsGuid,
        ),
      );
      await _plugin.initialize(
        settings: settings,
        onDidReceiveNotificationResponse: _onTapResponse,
      );
      _pluginReady = true;
    } catch (_) {
      _pluginReady = false;
    }
  }

  /// Best-effort permission request. macOS prompts the user on first fire
  /// (allow in System Settings when asked); Windows (win_toast) and Linux
  /// (notify-send) have no runtime permission model, so this is a no-op
  /// there. Never throws.
  static Future<void> requestPermissions() async {
    if (!isSupportedPlatform) return;
    try {
      await initNotifications();
      if (Platform.isMacOS) {
        await _plugin
            .resolvePlatformSpecificImplementation<
                MacOSFlutterLocalNotificationsPlugin>()
            ?.requestPermissions(alert: true, badge: true, sound: true);
      }
    } catch (_) {}
  }

  /// Single funnel for every desktop notification payload: blank titles are
  /// dropped, then [NotificationHook.build] caps at 3 + "…and N more".
  /// Reuses policy/threshold types verbatim — no new payload formats.
  static Map<String, String> buildLocalPayload(
    String title,
    List<String> freshTitles,
  ) {
    final titles =
        freshTitles.where((t) => t.trim().isNotEmpty).toList();
    return NotificationHook.build(title, titles);
  }

  /// Show one OS notification for [freshTitles], driven by the existing
  /// in-app timer while the app runs. Gated on the shared consent toggle
  /// (default OFF); returns true when a notification was shown.
  ///
  /// [payload] is the tap deep link (`AlertDeepLink.build`, `mcp://inbox…`);
  /// the response callback stashes it for the inbox to consume. Optional —
  /// existing callers without a link keep working.
  static Future<bool> showFresh(List<String> freshTitles,
      {String? payload}) async {
    if (!isSupportedPlatform) return false;
    if (!await isEnabled()) return false;
    final built = buildLocalPayload('MyControlPanel alert', freshTitles);
    if ((built['body'] ?? '').isEmpty) return false;
    try {
      await initNotifications();
      if (!_pluginReady) return false;
      const details = NotificationDetails(
        macOS: DarwinNotificationDetails(),
        linux: LinuxNotificationDetails(),
        windows: WindowsNotificationDetails(),
      );
      final id =
          DateTime.now().millisecondsSinceEpoch % 0x7fffffff;
      await _plugin.show(
        id: id,
        title: built['title'],
        body: built['body'],
        notificationDetails: details,
        payload: payload,
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Show one OS notification from an already-built [NotificationHook]
  /// payload. Headless-tick sink (`lib/headless.dart`): the shared pipeline
  /// builds the payload verbatim, this rail only delivers it — no second
  /// payload format. Same guards as [showFresh]; returns true when shown.
  ///
  /// [payload] is the optional tap deep link (`AlertDeepLink.build`) for
  /// Lisa's headless tick to thread once the tray helper owns the closed-app
  /// path.
  static Future<bool> showFreshPayload(String title, String body,
      {String? payload}) async {
    if (!isSupportedPlatform) return false;
    if (!await isEnabled()) return false;
    if (body.trim().isEmpty) return false;
    try {
      await initNotifications();
      if (!_pluginReady) return false;
      const details = NotificationDetails(
        macOS: DarwinNotificationDetails(),
        linux: LinuxNotificationDetails(),
        windows: WindowsNotificationDetails(),
      );
      final id =
          DateTime.now().millisecondsSinceEpoch % 0x7fffffff;
      await _plugin.show(
        id: id,
        title: title,
        body: body,
        notificationDetails: details,
        payload: payload,
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Tap-response sink: stash valid inbox deep links for the inbox to
  /// consume on launch/resume. Foreign/legacy payloads are ignored.
  static void _onTapResponse(NotificationResponse response) {
    final payload = response.payload;
    if (payload == null || payload.isEmpty) return;
    if (AlertDeepLink.parse(payload) == null) return;
    unawaited(AlertDeepLink.storePending(payload));
  }
}
