import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// OS-level notifications for fresh alerts + failed CI runs.
///
/// The control center already diffs firing alerts / failed runs through
/// [AlertWatch] and shows an in-app SnackBar; this service delivers the
/// same titles as real OS notifications so they survive when the app is
/// backgrounded. Gated on the existing `notifications` preference
/// (Settings, default on). All plugin calls are best-effort: init/show
/// failures are swallowed so a missing platform backend can never crash
/// the app. Unit-tested surface is the pure summary/gate logic below.
class AlertNotifications {
  static const channelId = 'mcp_alerts';
  static const channelName = 'Critical alerts';
  static const _prefKey = 'notifications';

  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  static bool _ready = false;

  /// Initialize once (safe to call repeatedly; failures stay silent).
  static Future<void> init() async {
    if (_ready) return;
    try {
      const settings = InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(),
        macOS: DarwinInitializationSettings(),
        linux: LinuxInitializationSettings(
            defaultActionName: 'Open MyControlPanel'),
        windows: WindowsInitializationSettings(
          appName: 'MyControlPanel',
          appUserModelId: 'Alfirus.MyControlPanel',
          guid: '{3B4F2A10-8C6D-4E2A-9F1B-7D5C8A0E1234}',
        ),
      );
      await _plugin.initialize(settings: settings);
      _ready = true;
    } catch (_) {
      _ready = false;
    }
  }

  /// Fire one OS notification for [freshTitles] when the user opted in.
  /// Returns true when a notification was shown.
  static Future<bool> showFresh(List<String> freshTitles) async {
    if (!await _enabled()) return false;
    if (freshTitles.isEmpty) return false;
    final summary = buildSummary(freshTitles);
    try {
      await init();
      if (!_ready) return false;
      await _plugin.show(
        id: 0,
        title: summary.title,
        body: summary.body,
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails(
            channelId,
            channelName,
            importance: Importance.high,
            priority: Priority.high,
          ),
          iOS: DarwinNotificationDetails(),
          macOS: DarwinNotificationDetails(),
          linux: LinuxNotificationDetails(),
          windows: WindowsNotificationDetails(),
        ),
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> _enabled() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(_prefKey) ?? true;
    } catch (_) {
      return true;
    }
  }

  /// Pure: collapse fresh titles into one notification (title + body).
  /// Single title shows verbatim; several fold into a count + preview.
  static NotificationSummary buildSummary(List<String> freshTitles) {
    final titles = freshTitles.where((t) => t.trim().isNotEmpty).toList();
    if (titles.length == 1) {
      return NotificationSummary(
          title: 'MyControlPanel alert', body: titles.first);
    }
    return NotificationSummary(
      title: '${titles.length} new alerts',
      body: titles.take(3).join('\n'),
    );
  }

  /// Pure gate shared by the timeline hook and tests.
  static bool shouldNotify(
      {required bool enabled, required List<String> freshTitles}) {
    if (!enabled) return false;
    return freshTitles.any((t) => t.trim().isNotEmpty);
  }
}

/// Value built by [AlertNotifications.buildSummary].
class NotificationSummary {
  final String title;
  final String body;
  const NotificationSummary({required this.title, required this.body});
}
