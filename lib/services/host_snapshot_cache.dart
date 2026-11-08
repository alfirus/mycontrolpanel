// SPDX-License-Identifier: MIT
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'background_alerts.dart';

/// Last-good per-host metrics snapshot (offline mode, no new plugins).
///
/// When a host is unreachable, the UI shows the last-good cached snapshot
/// with the established stale banner (`BackgroundAlerts.formatLastChecked`
/// → `AlertsStalenessLine`, "last checked Xm ago") instead of error
/// screens. On reconnect the next successful poll overwrites the snapshot
/// and the live rail resumes transparently.
///
/// SecureStore boundary: the cache stores ONLY the allowlisted numeric
/// metric fields below. Credentials, tokens, passphrases, keys — anything
/// outside the allowlist — are stripped by [sanitize] before anything is
/// persisted, so a hostile/buggy caller can never smuggle secrets into
/// SharedPreferences through this cache.
class HostSnapshotCache {
  static const _prefix = 'host_snapshot_';

  /// Numeric metric fields allowed into the cache. Everything else is
  /// dropped — in particular no `credential`, `password`, `token`,
  /// `secret`, `key`, `passphrase` field can survive [sanitize].
  static const allowedKeys = {
    'cpu',
    'ram',
    'disk',
    'uptime_days',
    'version',
    'load1',
    'load5',
    'load15',
    'nproc',
  };

  static String _key(String host) =>
      '$_prefix${host.replaceAll(RegExp(r'[^A-Za-z0-9_.\-]'), '_')}';

  /// Strip anything outside [allowedKeys] and coerce to num.
  /// Returns an empty map when nothing cacheable survives.
  static Map<String, dynamic> sanitize(Map<String, dynamic> metrics) {
    final out = <String, dynamic>{};
    for (final entry in metrics.entries) {
      if (!allowedKeys.contains(entry.key)) continue;
      final v = entry.value;
      if (v is num) {
        out[entry.key] = v;
      } else if (v is String) {
        final parsed = num.tryParse(v);
        if (parsed != null) out[entry.key] = parsed;
      }
    }
    // Clamp the 0..1 resource ratios so a corrupt cache can never
    // render an absurd bar.
    for (final k in ['cpu', 'ram', 'disk']) {
      final v = out[k];
      if (v is num) out[k] = v.toDouble().clamp(0.0, 1.0).toDouble();
    }
    return out;
  }

  /// Persist the last-good snapshot for [host] (best-effort, never throws).
  /// Anything outside the allowlist is dropped before the write.
  static Future<void> save(String host, Map<String, dynamic> metrics) async {
    try {
      final clean = sanitize(metrics);
      if (clean.isEmpty) return;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _key(host),
        jsonEncode({
          'at': DateTime.now().millisecondsSinceEpoch,
          'data': clean,
        }),
      );
    } catch (_) {}
  }

  /// Last-good snapshot for [host], or null when never cached / corrupt.
  static Future<Map<String, dynamic>?> read(String host) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key(host));
      if (raw == null) return null;
      final doc = jsonDecode(raw) as Map<String, dynamic>;
      final data = doc['data'];
      if (data is! Map<String, dynamic>) return null;
      final clean = sanitize(data);
      return clean.isEmpty ? null : clean;
    } catch (_) {
      return null;
    }
  }

  /// When the last-good snapshot for [host] was saved (null = never).
  static Future<DateTime?> savedAt(String host) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key(host));
      if (raw == null) return null;
      final ms = ((jsonDecode(raw) as Map)['at'] as num?)?.toInt();
      return ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms);
    } catch (_) {
      return null;
    }
  }

  /// Stale banner copy for [host] — the established "last checked Xm ago"
  /// line, shared with the background rail. Pure except for the prefs read.
  static Future<String> staleLabel(String host, {DateTime? now}) async {
    final last = await savedAt(host);
    return BackgroundAlerts.formatLastChecked(
      now: now ?? DateTime.now(),
      last: last,
    );
  }
}
