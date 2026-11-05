// SPDX-License-Identifier: MIT
import 'dart:async';
import 'dart:io';

import 'package:shared_preferences/shared_preferences.dart';
import '../background/headless_state.dart';
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

  /// Injectable cross-process lock for the shared seen-set transaction.
  /// Tests / device-lab point it at a temp dir; production resolves the
  /// per-user default (ADR-003: per-user locations only).
  static File? dedupLockFileOverride;

  /// Per-user lock file guarding the shared `alert_watch_seen_v1`
  /// transaction. Every prefs-sharing rail takes this same file
  /// (foreground claim callers + `BackgroundAlerts.runBackgroundTick`)
  /// so concurrent rails serialize instead of double-notifying.
  static File dedupLockFile() =>
      dedupLockFileOverride ??
      HeadlessPaths.lockFile(HeadlessPaths.stateDir());

  /// In-process single-flight chain: serializes concurrent claims inside
  /// this isolate. The file lock covers the cross-process half; both
  /// layers must agree (same two-layer contract as [HeadlessLock]).
  static Future<void> _claimChain = Future.value();

  /// Atomically claim the fresh batch for [current]: read the shared
  /// seen-set, diff, and mark seen in one critical section, then return
  /// the fresh titles the caller must notify on.
  ///
  /// Exactly-once contract: when N rails claim the same firing batch
  /// concurrently, exactly one claimant gets a non-empty list (the
  /// winner) and every loser gets `[]` and must stay silent. A rail that
  /// finds the lock held returns `[]` immediately (skip, never overlap —
  /// same philosophy as the headless tick's exit-2 single-flight).
  ///
  /// [lockFile] is the cross-process guard (`dedupLockFile()` in
  /// production); null means in-process mutex only (unit tests, and
  /// rails that never leave their isolate). [lockTimeout] bounds the
  /// wait — foreground callers pass a short timeout so the UI never
  /// stalls behind a background tick; a timeout is a skip (`[]`), and a
  /// skip is safe because the lock holder owns the toast.
  static Future<List<String>> claimFreshTitles(
    Set<String> current,
    List<AlertEntry> alerts,
    List<DeployItem> runs, {
    File? lockFile,
    Duration lockTimeout = const Duration(seconds: 10),
  }) async {
    final previous = _claimChain;
    final gate = Completer<void>();
    _claimChain = gate.future;
    await previous;
    HeadlessLock? lock;
    try {
      if (lockFile != null) {
        lock = await HeadlessLock.tryAcquire(lockFile, timeout: lockTimeout);
        if (lock == null) return <String>[];
      }
      final prefs = await SharedPreferences.getInstance();
      try {
        // Fresh read inside the critical section: a contending isolate's
        // cache may predate the winner's write (real backends only; the
        // unit-test mock answers from memory either way).
        await prefs.reload();
      } catch (_) {}
      final seen = prefs.getStringList(_seenKey)?.toSet() ?? {};
      final fresh = freshTitles(current, seen, alerts, runs);
      await markSeen(current);
      return fresh;
    } finally {
      try {
        await lock?.release();
      } catch (_) {}
      gate.complete();
    }
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
