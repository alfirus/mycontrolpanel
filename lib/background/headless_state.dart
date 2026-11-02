// SPDX-License-Identifier: MIT
/// Headless-tick persisted state + single-flight lock (pure Dart).
///
/// This file is the durable half of the TM-1 headless contract (Lina owns,
/// frozen by 2026-11-21 — see `docs/specs/headless-cli-contract.md`):
///
/// - [HeadlessState] is the JSON state file shared by every rail that runs
///   the headless pipeline: last-check stamp, transition-only seen-set, and
///   per-title resend timestamps. Schema version is pinned ([stateVersion])
///   so future readers can migrate instead of misreading.
/// - [HeadlessKeys.keyFor] mirrors [AlertWatch.keyFor] verbatim
///   (`kind::owner::title`) so the headless tick and the in-app rail share
///   one dedup identity — exactly one toast per fresh batch, never both.
///   Parity is pinned by `test/headless_state_test.dart`; do NOT change the
///   format here without changing `AlertWatch` in the same PR.
/// - [HeadlessLock] is the single-flight guard: the OS scheduler may fire
///   while a previous tick is still polling (slow SSH). The second tick
///   must skip (exit 2), never overlap. Implemented as an exclusive
///   `dart:io` file lock with a short acquisition timeout.
/// - [HeadlessPaths] resolves the per-user state directory (ADR-003:
///   per-user locations only, never system-wide, never world-readable).
///
/// Pure `dart:io` / `dart:convert` only — no Flutter, no plugins — so both
/// the shipped app binary (`--poll-headless`) and the CI harness
/// (`dart run headless_check`) share this file verbatim.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// One evaluatable signal for the headless pipeline.
///
/// The adapter layer (`lib/headless.dart`) maps producer models into these:
/// firing [AlertEntry]s → `kind: 'alert'`, failed CI runs → `kind: 'ci'`.
/// Display-title mapping mirrors [AlertWatch.freshTitles] verbatim so the
/// headless rail and the foreground rail announce identical strings.
class HeadlessSignal {
  const HeadlessSignal({
    required this.kind,
    required this.title,
    required this.owner,
  });

  /// 'alert' (firing server alert) or 'ci' (failed CI run).
  final String kind;

  /// Producer title (raw alert title / `app version` for CI runs).
  final String title;

  /// Owner scope (server name for alerts, env for CI runs).
  final String owner;

  /// Stable dedup identity. Format MUST match `AlertWatch.keyFor`.
  String get key => HeadlessKeys.keyFor(kind, title, owner);

  /// User-visible line. Format MUST match `AlertWatch.freshTitles`.
  String get displayTitle {
    if (kind == 'ci') return 'CI failed: $title';
    return '$title ($owner)';
  }
}

/// Dedup key helpers. Format is owned jointly with `AlertWatch` — see
/// the parity test before touching this.
abstract class HeadlessKeys {
  static String keyFor(String kind, String title, String owner) =>
      '$kind::$owner::$title';
}

/// Durable headless-tick state (JSON file, see [HeadlessPaths.stateFile]).
class HeadlessState {
  static const fileName = 'headless_state.json';
  static const lockFileName = 'headless.lock';

  HeadlessState({
    this.version = HeadlessCheckStateVersion.current,
    this.lastCheckMs = 0,
    this.seenKeys = const {},
    this.lastSentMs = const {},
    this.consecutiveFailures = 0,
  });

  final int version;
  int lastCheckMs;
  Set<String> seenKeys;
  Map<String, int> lastSentMs;
  int consecutiveFailures;

  HeadlessState copyWith({
    int? lastCheckMs,
    Set<String>? seenKeys,
    Map<String, int>? lastSentMs,
    int? consecutiveFailures,
  }) =>
      HeadlessState(
        lastCheckMs: lastCheckMs ?? this.lastCheckMs,
        seenKeys: seenKeys ?? this.seenKeys,
        lastSentMs: lastSentMs ?? this.lastSentMs,
        consecutiveFailures:
            consecutiveFailures ?? this.consecutiveFailures,
      );

  Map<String, dynamic> toJson() => {
        'version': version,
        'lastCheckMs': lastCheckMs,
        'seenKeys': seenKeys.toList()..sort(),
        'lastSentMs': lastSentMs,
        'consecutiveFailures': consecutiveFailures,
      };

  static HeadlessState fromJson(Map<String, dynamic> j) {
    try {
      final seen = (j['seenKeys'] as List? ?? const [])
          .map((e) => e.toString())
          .toSet();
      final sent = <String, int>{};
      final rawSent = j['lastSentMs'];
      if (rawSent is Map) {
        rawSent.forEach((k, v) {
          final ms = v is int ? v : int.tryParse(v.toString());
          if (ms != null) sent[k.toString()] = ms;
        });
      }
      int asInt(Object? v) =>
          v is int ? v : int.tryParse(v.toString()) ?? 0;
      return HeadlessState(
        version: asInt(j['version']),
        lastCheckMs: asInt(j['lastCheckMs']),
        seenKeys: seen,
        lastSentMs: sent,
        consecutiveFailures: asInt(j['consecutiveFailures']),
      );
    } catch (_) {
      return HeadlessState();
    }
  }

  /// Load state; corrupt/missing files yield defaults (never throws).
  static HeadlessState load(File file) {
    try {
      if (!file.existsSync()) return HeadlessState();
      final decoded = jsonDecode(file.readAsStringSync());
      if (decoded is! Map<String, dynamic>) return HeadlessState();
      return HeadlessState.fromJson(decoded);
    } catch (_) {
      return HeadlessState();
    }
  }

  /// Persist state (best-effort, never throws — a tick that evaluated
  /// must not fail on bookkeeping).
  void save(File file) {
    try {
      file.parent.createSync(recursive: true);
      file.writeAsStringSync(jsonEncode(toJson()));
    } catch (_) {}
  }
}

/// State-file schema version. Bump + migrate in [HeadlessState.fromJson]
/// if the schema ever changes.
abstract class HeadlessCheckStateVersion {
  static const current = 1;
}

/// Single-flight file lock for the headless tick.
///
/// Usage: `final lock = await HeadlessLock.tryAcquire(file); if (lock ==
/// null) skip(exit 2); try { tick } finally { await lock.release(); }`
class HeadlessLock {
  HeadlessLock._(this._raf);

  final RandomAccessFile _raf;

  /// Try to take the exclusive lock, waiting at most [timeout]. Returns
  /// null when another tick holds it (caller must skip, exit 2).
  static Future<HeadlessLock?> tryAcquire(
    File lockFile, {
    Duration timeout = const Duration(seconds: 10),
  }) async {
    try {
      lockFile.parent.createSync(recursive: true);
      final raf = lockFile.openSync(mode: FileMode.write);
      try {
        await raf.lock(FileLock.exclusive).timeout(timeout);
      } on TimeoutException {
        try {
          raf.closeSync();
        } catch (_) {}
        return null;
      }
      return HeadlessLock._(raf);
    } catch (_) {
      return null;
    }
  }

  Future<void> release() async {
    try {
      await _raf.unlock();
    } catch (_) {}
    try {
      _raf.closeSync();
    } catch (_) {}
  }
}

/// Per-user state directory resolution (ADR-003: per-user only).
///
/// Override precedence: [stateDirOverride] → `$MCP_STATE_DIR` env → OS
/// per-user default. The env override is a *path*, never secret material,
/// and exists for CI/tests only.
abstract class HeadlessPaths {
  static const envOverride = 'MCP_STATE_DIR';

  static Directory stateDir({
    String? stateDirOverride,
    Map<String, String>? environment,
    bool? isWindowsOverride,
  }) {
    if (stateDirOverride != null && stateDirOverride.isNotEmpty) {
      return Directory(stateDirOverride);
    }
    final env = environment ?? Platform.environment;
    final fromEnv = env[envOverride];
    if (fromEnv != null && fromEnv.isNotEmpty) return Directory(fromEnv);
    final isWindows = isWindowsOverride ?? Platform.isWindows;
    if (isWindows) {
      final base = env['LOCALAPPDATA'];
      if (base != null && base.isNotEmpty) {
        return Directory('$base${Platform.pathSeparator}MyControlPanel');
      }
    } else if (Platform.isMacOS && isWindowsOverride == null) {
      final home = env['HOME'];
      if (home != null && home.isNotEmpty) {
        return Directory(
            '$home/Library/Application Support/MyControlPanel');
      }
    } else {
      final xdg = env['XDG_CONFIG_HOME'];
      if (xdg != null && xdg.isNotEmpty) {
        return Directory('$xdg${Platform.pathSeparator}mycontrolpanel');
      }
      final home = env['HOME'];
      if (home != null && home.isNotEmpty) {
        return Directory('$home/.config/mycontrolpanel');
      }
    }
    return Directory('.mcp-headless');
  }

  static File stateFile(Directory dir) =>
      File('${dir.path}${Platform.pathSeparator}${HeadlessState.fileName}');

  static File lockFile(Directory dir) =>
      File('${dir.path}${Platform.pathSeparator}${HeadlessState.lockFileName}');
}
