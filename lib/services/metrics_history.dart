import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

/// Foreground metrics history (no new plugins).
///
/// Every successful agent poll appends one point per host
/// (cpu/ram/disk 0..1 + latency ms), capped at 120 points.
/// Powers the real latency chart + p95 KPI in the Metrics segment.
/// Background polling while the app is closed is intentionally out of
/// scope — that needs workmanager + local notifications (next step).
class MetricsHistory {
  static const _prefix = 'metrics_hist_';
  static const _cap = 120;

  static String _key(String host) =>
      '$_prefix${host.replaceAll(RegExp(r'[^A-Za-z0-9_.\-]'), '_')}';

  static Future<void> record(
    String host,
    double cpu,
    double ram,
    double disk,
    double latencyMs,
  ) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = _key(host);
      final raw = prefs.getString(key);
      final List<dynamic> list = raw == null ? [] : jsonDecode(raw) as List;
      list.add({
        't': DateTime.now().millisecondsSinceEpoch,
        'cpu': cpu.clamp(0, 1),
        'ram': ram.clamp(0, 1),
        'disk': disk.clamp(0, 1),
        'lat': latencyMs < 0 ? 0 : latencyMs,
      });
      while (list.length > _cap) {
        list.removeAt(0);
      }
      await prefs.setString(key, jsonEncode(list));
    } catch (_) {}
  }

  static Future<List<Map<String, dynamic>>> read(String host) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key(host));
      if (raw == null) return [];
      return (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
    } catch (_) {
      return [];
    }
  }

  /// p95 of a latency series (ms). Returns null when empty.
  static double? p95(List<double> values) {
    if (values.isEmpty) return null;
    final sorted = List.of(values)..sort();
    final idx = ((sorted.length * 0.95).ceil() - 1).clamp(0, sorted.length - 1);
    return sorted[idx];
  }

  static String formatMs(double? ms) {
    if (ms == null) return '—';
    if (ms < 1000) return '${ms.toStringAsFixed(0)}ms';
    return '${(ms / 1000).toStringAsFixed(2)}s';
  }
}
