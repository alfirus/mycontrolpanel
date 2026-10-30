/// Mobile background alerting (beta.1, owner green-lit 2026-10-30).
///
/// This file owns the *mobile half* of docs/design/05-background-alerting.md
/// §3: a WorkManager periodic task (≥15 min OS minimum) + local
/// notifications via `flutter_local_notifications`, gated behind the
/// `background_alerts` Settings toggle (default OFF, explicit consent copy).
///
/// Policy reuse (no new payload formats, no FCM/APNs remote push):
/// - Poll/backoff semantics come from [PollPolicy] verbatim (the in-app
///   [AlertPollJob.tick] path already encodes them; the background tick
///   reuses [pollHostAlerts] + [AlertWatch]'s persisted seen-set so the
///   foreground and background rails share one dedup contract).
/// - Thresholds come from [AlertRules]/[Thresholds] verbatim.
/// - Every user-visible payload is built by [NotificationHook.build]
///   (`{title, body}`, max 3 + "…and N more") — the same funnel the snack
///   bar uses today. [buildLocalPayload] is the single choke point.
///
/// Desktop (macOS/Windows/Linux): compiles (CI build-matrix) but never
/// schedules — [isSupportedPlatform] is Android/iOS only. Closed-app desktop
/// delivery stays deferred to tray-mode work per the owner ruling.
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';

import 'agent_service.dart';
import 'alert_poller.dart';
import 'alert_watch.dart';
import '../models/alert_entry.dart';
import '../models/mock_data.dart' show DeployItem;
import '../models/server_connection.dart';
import 'polling_alerts.dart';
import 'secure_store.dart';

/// WorkManager plumbing + pure helpers for mobile background alerting.
abstract class BackgroundAlerts {
  /// Unique periodic-work name (Android WorkManager + cancel handle).
  static const uniqueName = 'mcp-background-alerts-periodic';

  /// Task name delivered to the background entry-point.
  ///
  /// Must EXACTLY match `BGTaskSchedulerPermittedIdentifiers` in
  /// `ios/Runner/Info.plist` and the `registerPeriodicTask(withIdentifier:)`
  /// hint in `ios/Runner/AppDelegate.swift`, or iOS throws
  /// `BGTaskSchedulerErrorDomain Code=3`.
  static const taskName =
      'com.mycontrolpanel.my_control_panel.backgroundAlerts';

  /// Tag attached to the periodic work request (observability only).
  static const taskTag = 'mcp-alerts';

  /// OS-enforced minimum for periodic work. Android clamps anything lower
  /// to 15 min; iOS BGTaskScheduler treats this as a *hint* (system may run
  /// it hours apart — hence the stale-tolerant "last checked" UI).
  static const pollFrequency = Duration(minutes: 15);

  /// Settings pref for the background toggle. Default OFF (owner ruling:
  /// explicit consent required).
  static const prefEnabledKey = 'background_alerts';

  /// When the last background check attempt ran (ms since epoch).
  /// Written even when every host fails — the UI reports honest staleness,
  /// never silent freshness.
  static const prefLastCheckKey = 'background_alerts_last_check_ms';

  /// One-shot flag: the Android battery-optimisation explainer was shown.
  static const prefBatteryPromptKey = 'background_alerts_battery_prompted';

  /// Consent copy shown under the Settings toggle (binding wording).
  static const consentCopy =
      'Polls your servers every ~15 min in the background.';

  /// Android notification channel (created on init).
  static const channelId = 'mcp-alerts';
  static const channelName = 'Server alerts';
  static const channelDescription =
      'Firing server alerts and failed CI runs, polled on-device.';

  /// In-app explainer for the Android "ignore battery optimisations"
  /// exemption. The app deliberately does NOT declare
  /// REQUEST_IGNORE_BATTERY_OPTIMIZATIONS (an unused special permission is
  /// a store-review red flag); the user exempts manually via Settings.
  static const batteryPromptTitle = 'Keep background checks on time';
  static const batteryPromptBody =
      'Android may delay background polls to save power. To keep ~15 min '
      'checks: Settings → Apps → MyControlPanel → Battery → Unrestricted. '
      'MyControlPanel never exempts itself automatically.';

  /// iOS explainer (Background App Refresh + system scheduling).
  static const iosPromptBody =
      'iOS decides when background checks run (typically every ~15 min at '
      'best, sometimes hours apart). Keep Background App Refresh on for '
      'MyControlPanel; the status line always shows how stale the last '
      'check is.';

  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  static bool _pluginReady = false;

  /// True only on the platforms background work is supported on.
  /// Guard every schedule/show call with this (desktop compiles, CI
  /// build-matrix, but never schedules).
  static bool get isSupportedPlatform {
    if (kIsWeb) return false;
    return Platform.isAndroid || Platform.isIOS;
  }

  /// Whether the user opted into background alerting (default OFF).
  static Future<bool> isEnabled() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(prefEnabledKey) ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Persist the toggle and schedule/cancel accordingly. Safe to call on
  /// desktop (persists the pref, skips the scheduler).
  static Future<void> setEnabled(bool enabled) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(prefEnabledKey, enabled);
    } catch (_) {
      return;
    }
    if (enabled) {
      await requestPermissions();
      await schedule();
    } else {
      await cancel();
    }
  }

  /// Call once from `main()` (guarded try/catch there too): re-registers the
  /// dispatcher + periodic work when the user opted in. WorkManager needs
  /// this on every launch; [schedule] is idempotent (replace policy).
  static Future<void> ensureInitialized() async {
    if (!isSupportedPlatform) return;
    if (!await isEnabled()) return;
    try {
      await Workmanager().initialize(backgroundAlertDispatcher);
      await schedule();
      await initNotifications();
    } catch (_) {}
  }

  /// Register (or replace) the periodic poll. No-op off mobile.
  static Future<void> schedule() async {
    if (!isSupportedPlatform) return;
    try {
      await Workmanager().registerPeriodicTask(
        uniqueName,
        taskName,
        frequency: pollFrequency,
        constraints: Constraints(networkType: NetworkType.connected),
        existingWorkPolicy: ExistingPeriodicWorkPolicy.replace,
        backoffPolicy: BackoffPolicy.exponential,
        backoffPolicyDelay: const Duration(minutes: 5),
        tag: taskTag,
      );
    } catch (_) {}
  }

  /// Remove the periodic poll. No-op off mobile.
  static Future<void> cancel() async {
    if (!isSupportedPlatform) return;
    try {
      await Workmanager().cancelByUniqueName(uniqueName);
    } catch (_) {}
  }

  /// Best-effort notification permission request (Android 13+ runtime
  /// prompt + iOS alert/badge/sound). Never throws.
  static Future<void> requestPermissions() async {
    if (!isSupportedPlatform) return;
    try {
      await initNotifications();
      if (Platform.isAndroid) {
        await _plugin
            .resolvePlatformSpecificImplementation<
                AndroidFlutterLocalNotificationsPlugin>()
            ?.requestNotificationsPermission();
      } else if (Platform.isIOS) {
        await _plugin
            .resolvePlatformSpecificImplementation<
                IOSFlutterLocalNotificationsPlugin>()
            ?.requestPermissions(alert: true, badge: true, sound: true);
      }
    } catch (_) {}
  }

  /// Init the notifications plugin + create the Android channel.
  /// Idempotent; safe on any platform (failures stay silent).
  static Future<void> initNotifications() async {
    if (_pluginReady) return;
    try {
      const androidInit =
          AndroidInitializationSettings('@mipmap/ic_launcher');
      const darwinInit = DarwinInitializationSettings();
      const settings = InitializationSettings(
        android: androidInit,
        iOS: darwinInit,
        macOS: darwinInit,
      );
      await _plugin.initialize(settings: settings);
      const channel = AndroidNotificationChannel(
        channelId,
        channelName,
        description: channelDescription,
        importance: Importance.high,
      );
      await _plugin
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(channel);
      _pluginReady = true;
    } catch (_) {
      _pluginReady = false;
    }
  }

  /// Single funnel for every local-notification payload: blank titles are
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

  /// Show one local notification for [freshTitles]. Mobile-only (desktop
  /// keeps the `local_notifier` rail in [AlertNotifications]); returns true
  /// when a notification was shown.
  static Future<bool> showFresh(List<String> freshTitles) async {
    if (!isSupportedPlatform) return false;
    final payload = buildLocalPayload('MyControlPanel alert', freshTitles);
    if ((payload['body'] ?? '').isEmpty) return false;
    try {
      await initNotifications();
      if (!_pluginReady) return false;
      const details = NotificationDetails(
        android: AndroidNotificationDetails(
          channelId,
          channelName,
          channelDescription: channelDescription,
          importance: Importance.high,
          priority: Priority.high,
        ),
        iOS: DarwinNotificationDetails(),
        macOS: DarwinNotificationDetails(),
      );
      final id =
          DateTime.now().millisecondsSinceEpoch % 0x7fffffff;
      await _plugin.show(
        id: id,
        title: payload['title'],
        body: payload['body'],
        notificationDetails: details,
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Record a background check attempt (called by the worker; the UI reads
  /// it via [lastCheckedLabel]).
  static Future<void> recordCheck([DateTime? at]) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final ms = (at ?? DateTime.now()).millisecondsSinceEpoch;
      await prefs.setInt(prefLastCheckKey, ms);
    } catch (_) {}
  }

  /// Last check timestamp, or null when no check has run yet.
  static Future<DateTime?> readLastCheck() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final ms = prefs.getInt(prefLastCheckKey);
      if (ms == null) return null;
      return DateTime.fromMillisecondsSinceEpoch(ms);
    } catch (_) {
      return null;
    }
  }

  /// Stale-tolerant status line for the Settings toggle + alerts UI.
  /// Pure (inject [now] in tests).
  static String formatLastChecked({required DateTime now, DateTime? last}) {
    if (last == null) return 'Background alerts idle — never checked yet';
    final age = now.difference(last);
    if (age.isNegative || age.inSeconds < 60) return 'last checked just now';
    if (age.inMinutes < 60) {
      final m = age.inMinutes;
      return 'last checked $m min ago';
    }
    if (age.inHours < 24) {
      final h = age.inHours;
      return 'last checked $h hr ago';
    }
    final d = age.inDays;
    return 'last checked $d day${d == 1 ? '' : 's'} ago';
  }

  /// Convenience for the UI: "last checked Xm ago" for the stored stamp.
  static Future<String> lastCheckedLabel({DateTime? now}) async {
    final last = await readLastCheck();
    return formatLastChecked(now: now ?? DateTime.now(), last: last);
  }

  /// One background run: agent-HTTP leg only (no SSH sweep — keys/host-key
  /// UI stay foreground-only), diffed through the shared [AlertWatch]
  /// seen-set so the foreground and background rails never double-notify.
  /// Always records the check; never throws (a crashing worker costs more
  /// battery than a missed poll).
  ///
  /// [fetchAlertsFor] is injectable for tests; production passes null to
  /// use [pollHostAlerts] with `sshSweep: false`.
  static Future<void> runBackgroundTick({
    Future<List<AlertEntry>> Function(ServerConnection server)?
        fetchAlertsFor,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!(prefs.getBool(prefEnabledKey) ?? false)) return;
      final servers = await SecureStore.readServers();
      final agent = AgentService();
      for (final s in servers.take(10)) {
        try {
          final alerts = fetchAlertsFor != null
              ? await fetchAlertsFor(s)
              : await pollHostAlerts(
                  agent,
                  s,
                  agentToken: await SecureStore.readSecret(
                    SecureStore.agentTokenKey(s.id),
                  ),
                  sshSweep: false,
                ).timeout(const Duration(seconds: 15));
          // Reuse the foreground diff verbatim (titles only — the worker
          // never touches widgets). The seen-set is shared with the
          // foreground rail, so neither rail double-notifies.
          final keys = AlertWatch.currentKeys(alerts, const <DeployItem>[]);
          final seen = await _readSeenKeys(prefs);
          final fresh = AlertWatch.freshTitles(
              keys, seen, alerts, const <DeployItem>[]);
          await AlertWatch.markSeen(keys);
          if (fresh.isNotEmpty) {
            await showFresh(fresh);
          }
        } catch (_) {
          // One sick host never sinks the run.
        }
      }
    } catch (_) {
      // Total failure still counts as an attempt (stale UI stays honest).
    } finally {
      await recordCheck();
    }
  }

  static Future<Set<String>> _readSeenKeys(SharedPreferences prefs) async {
    try {
      return prefs.getStringList('alert_watch_seen_v1')?.toSet() ?? {};
    } catch (_) {
      return {};
    }
  }
}

/// Background isolate entry-point (WorkManager + iOS BGTaskScheduler).
/// Must be top-level with the entry-point pragma so tree-shaking keeps it.
@pragma('vm:entry-point')
void backgroundAlertDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    if (task != BackgroundAlerts.taskName &&
        task != Workmanager.iOSBackgroundTask) {
      return Future.value(true);
    }
    try {
      await BackgroundAlerts.runBackgroundTick();
    } catch (_) {}
    return Future.value(true);
  });
}
