import 'package:shared_preferences/shared_preferences.dart';
import '../models/alert_entry.dart';
import '../models/mock_data.dart';

/// Foreground alert watcher (no new plugins).
///
/// Diffed on every auto-refresh: compares current firing alerts +
/// failed CI runs against the last-seen set in SharedPreferences.
/// Returns the badge count + newly-appeared critical titles so the
/// control center can badge the bell + snack on arrivals.
/// True push while the app is closed still needs
/// flutter_local_notifications + workmanager (next step).
class AlertWatch {
  static const _seenKey = 'alert_watch_seen_v1';

  /// Stable identity for one alert / failed run.
  static String keyFor(String kind, String title, String owner) =>
      '$kind::$owner::$title';

  static Future<Set<String>> _seen() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getStringList(_seenKey)?.toSet() ?? {};
    } catch (_) {
      return {};
    }
  }

  static Future<void> markSeen(Set<String> keys) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_seenKey, keys.toList());
    } catch (_) {}
  }

  /// Current badge set (firing alerts + failed runs).
  static Set<String> currentKeys(
    List<AlertEntry> alerts,
    List<DeployItem> runs,
  ) {
    final out = <String>{};
    for (final a in alerts) {
      if (a.status == 'firing') {
        out.add(keyFor('alert', a.title, a.serverName));
      }
    }
    for (final r in runs) {
      if (r.status == 'failed') {
        out.add(keyFor('ci', '${r.app} ${r.version}', r.env));
      }
    }
    return out;
  }

  /// Titles that appeared since the last check (for the snack bar).
  static List<String> freshTitles(
    Set<String> current,
    Set<String> seen,
    List<AlertEntry> alerts,
    List<DeployItem> runs,
  ) {
    final fresh = current.difference(seen);
    if (fresh.isEmpty) return [];
    final titles = <String>[];
    for (final a in alerts) {
      final k = keyFor('alert', a.title, a.serverName);
      if (fresh.contains(k)) titles.add('${a.title} (${a.serverName})');
    }
    for (final r in runs) {
      final k = keyFor('ci', '${r.app} ${r.version}', r.env);
      if (fresh.contains(k)) titles.add('CI failed: ${r.app} ${r.version}');
    }
    return titles.take(3).toList();
  }
}
