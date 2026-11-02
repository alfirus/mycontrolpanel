// SPDX-License-Identifier: MIT
/// Alerts Inbox model + deep-link contract (Nurul, frontend).
///
/// Build-ready half of `docs/design/06-alert-tray-ux.md` §4/§6/§8:
/// filterable history (all/unread/critical), swipe ack/snooze state,
/// stale detection (2 poll intervals without re-fire), and the
/// notification-tap deep-link payload both rails share.
///
/// Policy reuse (no new payload formats, no new thresholds):
/// - identity is `AlertWatch.keyFor` verbatim — one shared last-seen set,
///   never a second inbox-side set (spec §4.1);
/// - severities/actions/copy come from `alert_tokens.dart` verbatim;
/// - toast bodies still go through `NotificationHook.build` — this file
///   only adds the tap `payload` string beside that `{title, body}`.
library;

import 'package:shared_preferences/shared_preferences.dart';

import '../models/alert_entry.dart';
import '../theme/alert_tokens.dart';
import 'alert_rules.dart';
import 'alert_watch.dart';

/// Inbox filter chips (spec 06 §10: All / Unread / Critical).
enum InboxFilter { all, unread, critical }

/// Display labels for the filter chips (sentence case in UI).
extension InboxFilterLabel on InboxFilter {
  String get label => switch (this) {
        InboxFilter.all => 'All',
        InboxFilter.unread => 'Unread',
        InboxFilter.critical => 'Critical',
      };

  /// Screen-reader name (never color/filter-state only, spec §9.1).
  String get semanticLabel => switch (this) {
        InboxFilter.all => 'Show all alerts',
        InboxFilter.unread => 'Show unread alerts',
        InboxFilter.critical => 'Show critical alerts',
      };
}

/// One inbox row: the harvested [AlertEntry] plus triage state.
///
/// [seen] comes from the shared `AlertWatch` last-seen set; [snoozedUntilMs]
/// from the inbox snooze prefs; [stale] is derived per tick via [isStaleItem].
class InboxItem {
  final AlertEntry entry;
  final String key;
  final bool seen;
  final int? snoozedUntilMs;
  final bool stale;
  final int? firedAtMs;

  const InboxItem({
    required this.entry,
    required this.key,
    this.seen = false,
    this.snoozedUntilMs,
    this.stale = false,
    this.firedAtMs,
  });

  /// Snoozed and the snooze window has not elapsed yet.
  bool isSnoozedAt(int nowMs) =>
      snoozedUntilMs != null && nowMs < snoozedUntilMs!;

  /// Severity mapped onto the token set (unknown strings fall to info —
  /// never a crash, never silent).
  TrayAlertSeverity get traySeverity => switch (entry.severity) {
        'critical' => TrayAlertSeverity.critical,
        'warning' => TrayAlertSeverity.warning,
        _ => TrayAlertSeverity.info,
      };

  InboxItem copyWith({bool? seen, int? snoozedUntilMs, bool? stale}) =>
      InboxItem(
        entry: entry,
        key: key,
        seen: seen ?? this.seen,
        snoozedUntilMs: snoozedUntilMs,
        stale: stale ?? this.stale,
        firedAtMs: firedAtMs,
      );
}

/// Build inbox rows from harvested alerts.
///
/// Identity uses `AlertWatch.keyFor('alert', title, serverName)` verbatim so
/// the inbox and the headless tick share ONE last-seen set (spec §4.1).
/// [seenKeys] is that shared set; [snoozedMs] maps key → snooze-until
/// (epoch ms); [staleKeys] marks entries older than 2 poll intervals
/// without re-fire (spec §4.4 — they sink, never vanish).
List<InboxItem> buildInboxItems({
  required List<AlertEntry> alerts,
  Set<String> seenKeys = const {},
  Map<String, int> snoozedMs = const {},
  Set<String> staleKeys = const {},
  Map<String, int> firedAtMs = const {},
}) {
  final items = <InboxItem>[];
  for (final a in alerts) {
    final key = AlertWatch.keyFor('alert', a.title, a.serverName);
    items.add(InboxItem(
      entry: a,
      key: key,
      seen: seenKeys.contains(key),
      snoozedUntilMs: snoozedMs[key],
      stale: staleKeys.contains(key),
      firedAtMs: firedAtMs[key],
    ));
  }
  // Ordering (spec §4.4): critical first, then warning, then info;
  // within a severity, newest first (firedAtMs desc, unknown last).
  // Stale entries sink below fresh ones of the same severity.
  int rank(TrayAlertSeverity s) => switch (s) {
        TrayAlertSeverity.critical => 0,
        TrayAlertSeverity.warning => 1,
        TrayAlertSeverity.info => 2,
      };
  items.sort((a, b) {
    final r = rank(a.traySeverity).compareTo(rank(b.traySeverity));
    if (r != 0) return r;
    if (a.stale != b.stale) return a.stale ? 1 : -1;
    final fa = a.firedAtMs ?? -1;
    final fb = b.firedAtMs ?? -1;
    return fb.compareTo(fa);
  });
  return items;
}

/// Filter rows for the active chip. Snoozed rows stay visible (the row
/// keeps its snooze badge) — snooze suppresses re-toast, not the row
/// (spec §6 `mcp.snooze.1h`).
List<InboxItem> filterInbox(List<InboxItem> items, InboxFilter filter) =>
    switch (filter) {
      InboxFilter.all => List.of(items),
      InboxFilter.unread => items.where((i) => !i.seen).toList(),
      InboxFilter.critical =>
        items.where((i) => i.traySeverity == TrayAlertSeverity.critical).toList(),
    };

/// Counts for the filter-chip badges.
int unreadCount(List<InboxItem> items) => items.where((i) => !i.seen).length;

/// Stale when the last fire is older than 2 poll intervals (spec §4.4).
/// Null [firedAtMs] (never recorded) is never stale — unknown, not old.
bool isStaleItem({
  required int? firedAtMs,
  required int nowMs,
  required int pollIntervalMs,
}) {
  if (firedAtMs == null) return false;
  return nowMs - firedAtMs > 2 * pollIntervalMs;
}

/// Snooze state (per-key until-epoch-ms, prefs-backed).
///
/// Stored as `key=untilMs` strings under one pref key so ack (the shared
/// seen-set) and snooze (this inbox-side map) never collide.
abstract class AlertSnooze {
  static const prefKey = 'alert_inbox_snoozed_v1';

  /// One hour, matching `AlertNotificationActions.snooze1h` / `snoozeConfirm`.
  static const snoozeDuration = Duration(hours: 1);

  static Map<String, int> parse(List<String> raw) {
    final out = <String, int>{};
    for (final line in raw) {
      final idx = line.lastIndexOf('=');
      if (idx <= 0) continue;
      final until = int.tryParse(line.substring(idx + 1));
      if (until == null) continue;
      out[line.substring(0, idx)] = until;
    }
    return out;
  }

  static List<String> encode(Map<String, int> map) =>
      [for (final e in map.entries) '${e.key}=${e.value}'];

  /// Mark [keys] snoozed for [duration] from [nowMs]; drops elapsed entries.
  static Map<String, int> snooze(
    Map<String, int> current,
    Set<String> keys,
    int nowMs, [
    Duration duration = snoozeDuration,
  ]) {
    final out = Map<String, int>.of(current)
      ..removeWhere((_, until) => until <= nowMs);
    for (final k in keys) {
      out[k] = nowMs + duration.inMilliseconds;
    }
    return out;
  }

  static Future<Map<String, int>> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return parse(prefs.getStringList(prefKey) ?? []);
    } catch (_) {
      return {};
    }
  }

  static Future<void> save(Map<String, int> map) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(prefKey, encode(map));
    } catch (_) {}
  }
}

/// Ack = mark seen in the SHARED last-seen set (spec §6: ack-on-one-rail
/// clears all rails). Thin wrapper so the inbox never owns a second set.
abstract class AlertAck {
  /// Union [keys] into the shared set and persist via `AlertWatch`.
  static Future<Set<String>> ack(Set<String> seen, Set<String> keys) async {
    final out = {...seen, ...keys};
    await AlertWatch.markSeen(out);
    return out;
  }
}

/// Notification-tap deep-link contract (spec §6).
///
/// Both rails (mobile WorkManager + desktop tray helper, owned by
/// Lisa/Elizabeth) attach this `payload` string beside the
/// `NotificationHook.build` `{title, body}`; the inbox parses it back and
/// lands on the tapped alert. Format: `mcp://inbox?action=<id>&key=<k>…`
/// - `action` is one of `AlertNotificationActions.all` (stable ids);
/// - `key` repeats per alert (`AlertWatch.keyFor` values), may be absent
///   (body tap with no keys ⇒ open the inbox unfiltered);
/// - secrets are never carried (Alya ADR-003): keys are opaque identity
///   strings, nothing credential-adjacent.
abstract class AlertDeepLink {
  static const scheme = 'mcp';
  static const host = 'inbox';

  /// Pref key for a tap that arrived while the app was closed: the rail
  /// stashes the payload here, the inbox consumes it on next launch.
  static const pendingKey = 'alert_inbox_pending_tap_v1';

  /// Build a tap payload. Unknown actions fall back to `mcp.open`.
  static String build({
    String action = AlertNotificationActions.tapDefault,
    List<String> keys = const [],
  }) {
    final a = AlertNotificationActions.all.contains(action)
        ? action
        : AlertNotificationActions.tapDefault;
    final buf = StringBuffer('$scheme://$host?action=${Uri.encodeComponent(a)}');
    for (final k in keys) {
      if (k.trim().isEmpty) continue;
      buf.write('&key=${Uri.encodeComponent(k)}');
    }
    return buf.toString();
  }

  /// Parsed deep link: the action plus any alert keys. Null when [payload]
  /// is not an inbox link (wrong scheme/host, unparsable, null/blank).
  static ({String action, List<String> keys})? parse(String? payload) {
    final raw = (payload ?? '').trim();
    if (raw.isEmpty) return null;
    final uri = Uri.tryParse(raw);
    if (uri == null) return null;
    if (uri.scheme != scheme || uri.host != host) return null;
    final action = uri.queryParameters['action'] ?? '';
    if (!AlertNotificationActions.all.contains(action)) return null;
    final keys = uri.queryParametersAll['key']
            ?.map((k) => k.trim())
            .where((k) => k.isNotEmpty)
            .toList() ??
        [];
    return (action: action, keys: keys);
  }

  /// Stash a tap payload for the next cold start (best-effort, never throws).
  static Future<void> storePending(String payload) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(pendingKey, payload);
    } catch (_) {}
  }

  /// Read + clear the stashed tap payload. Null when none was stored.
  static Future<String?> consumePending() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(pendingKey);
      if (raw == null) return null;
      await prefs.remove(pendingKey);
      return raw;
    } catch (_) {
      return null;
    }
  }
}

/// Alerts-section Settings prefs (spec §8 IA order lives in
/// `AlertSettingsOrder.rows`; this class owns the new keys that section
/// introduces — consent/last-checked keys stay with `BackgroundAlerts`,
/// quiet-hours keys stay with `QuietHours`).
abstract class AlertSettingsPrefs {
  /// Which severities toast: `critical_only` (default) | `all`.
  /// Toasts only — the inbox always collects everything (spec §8.2).
  static const prefSeverityKey = 'alerts_severity_filter';
  static const severityCriticalOnly = 'critical_only';
  static const severityAll = 'all';

  /// Per-metric threshold overrides. Null = `AlertRules` default.
  static const prefDiskWarnKey = 'alerts_disk_warn';
  static const prefDiskCritKey = 'alerts_disk_crit';
  static const prefBruteWarnKey = 'alerts_brute_warn';
  static const prefBruteCritKey = 'alerts_brute_crit';

  static String sanitizeSeverity(String? raw) =>
      raw == severityAll ? severityAll : severityCriticalOnly;

  static Future<String> loadSeverity() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return sanitizeSeverity(prefs.getString(prefSeverityKey));
    } catch (_) {
      return severityCriticalOnly;
    }
  }

  static Future<void> saveSeverity(String value) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(prefSeverityKey, sanitizeSeverity(value));
    } catch (_) {}
  }

  /// Load threshold overrides onto `AlertRules` defaults. Clamps +
  /// repairs (warn < crit) so a corrupt pref can never invert a rule.
  static Future<AlertRules> loadThresholds([AlertRules fallback = const AlertRules()]) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      var diskWarn = prefs.getDouble(prefDiskWarnKey) ?? fallback.diskWarnAt;
      var diskCrit = prefs.getDouble(prefDiskCritKey) ?? fallback.diskCritAt;
      var bruteWarn = prefs.getInt(prefBruteWarnKey) ?? fallback.bruteWarnAt;
      var bruteCrit = prefs.getInt(prefBruteCritKey) ?? fallback.bruteCritAt;
      diskWarn = diskWarn.clamp(0.05, 0.95).toDouble();
      diskCrit = diskCrit.clamp(0.05, 0.99).toDouble();
      if (diskWarn >= diskCrit) {
        diskWarn = fallback.diskWarnAt;
        diskCrit = fallback.diskCritAt;
      }
      bruteWarn = bruteWarn.clamp(1, 999);
      bruteCrit = bruteCrit.clamp(1, 9999);
      if (bruteWarn >= bruteCrit) {
        bruteWarn = fallback.bruteWarnAt;
        bruteCrit = fallback.bruteCritAt;
      }
      return AlertRules(
        diskWarnAt: diskWarn,
        diskCritAt: diskCrit,
        bruteWarnAt: bruteWarn,
        bruteCritAt: bruteCrit,
      );
    } catch (_) {
      return fallback;
    }
  }

  static Future<void> saveThresholds(AlertRules rules) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble(prefDiskWarnKey, rules.diskWarnAt);
      await prefs.setDouble(prefDiskCritKey, rules.diskCritAt);
      await prefs.setInt(prefBruteWarnKey, rules.bruteWarnAt);
      await prefs.setInt(prefBruteCritKey, rules.bruteCritAt);
    } catch (_) {}
  }
}
