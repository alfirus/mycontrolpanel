import 'package:local_notifier/local_notifier.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'polling_alerts.dart';

/// OS-level notifications for fresh alerts + failed CI runs.
///
/// The control center already diffs firing alerts / failed CI runs through
/// [AlertWatch] and shows an in-app SnackBar; this service delivers the
/// same titles as real OS notifications via `local_notifier` (classic
/// MethodChannel plugin on Linux/macOS/Windows — deliberately NOT an FFI
/// plugin: the FFI-based alternative broke `flutter build windows` on CI
/// with a silent flutter_assemble failure, see PR #85 discussion).
/// On mobile (no desktop plugin) the channel call throws and is
/// swallowed — the in-app SnackBar remains the mobile path.
/// Gated on the existing `notifications` preference (Settings, default
/// on). All plugin calls are best-effort: init/show failures are
/// swallowed so a missing platform backend can never crash the app.
/// Unit-tested surface is the pure summary/gate logic below.
class AlertNotifications {
  static const _prefKey = 'notifications';
  static bool _ready = false;

  /// Initialize once (safe to call repeatedly; failures stay silent).
  /// `ignore` avoids writing Start-menu shortcuts on Windows dev boxes.
  static Future<void> init() async {
    if (_ready) return;
    try {
      await LocalNotifier.instance.setup(
        appName: 'MyControlPanel',
        shortcutPolicy: ShortcutPolicy.ignore,
      );
      _ready = true;
    } catch (_) {
      _ready = false;
    }
  }

  /// Fire one OS notification for [freshTitles] when the user opted in.
  /// Returns true when a notification was shown.
  ///
  /// The payload goes through [NotificationHook.build] verbatim — the same
  /// `{title, body}` funnel (max 3 + "…and N more") the background rail
  /// (`BackgroundAlerts.showFresh`) and the snack bar share. No new payload
  /// formats (background-alerting beta.1 contract).
  static Future<bool> showFresh(List<String> freshTitles) async {
    if (!await _enabled()) return false;
    final titles = freshTitles.where((t) => t.trim().isNotEmpty).toList();
    if (titles.isEmpty) return false;
    final payload = NotificationHook.build('MyControlPanel alert', titles);
    if ((payload['body'] ?? '').isEmpty) return false;
    try {
      await init();
      if (!_ready) return false;
      final note = LocalNotification(
        identifier: 'mcp-alert-${DateTime.now().millisecondsSinceEpoch}',
        title: payload['title']!,
        subtitle: 'MyControlPanel',
        body: payload['body']!,
      );
      await LocalNotifier.instance.notify(note);
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
