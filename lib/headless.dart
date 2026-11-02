// SPDX-License-Identifier: MIT
/// `--poll-headless` Flutter adapter (TM-1, Lina owns).
///
/// Thin wiring between the OS scheduler and the shared pure pipeline
/// (`lib/background/headless_check.dart`): called from `main()` BEFORE any
/// UI boots, runs one poll tick with no window, prints machine-readable
/// JSON to stdout, and returns the process exit code. Returns null when
/// the flag is absent so normal launch is untouched.
///
/// Security wiring (ADR-003 — read this before changing anything here):
/// - Consent: shared `background_alerts` pref (default OFF). OFF → exit 2,
///   touch nothing, notify nothing.
/// - Vault: read-only. Servers are loaded RAW via
///   `SecureStore.readRawServerListJson` (decoded, never via
///   `SecureStore.readServers()` — that method heals plaintext into the
///   keychain and healing is interactive-only). Each `secure:` marker
///   resolves via `HeadlessSecurity.resolveCredential` against one
///   `SecureStore.readSecret` call; non-`secure:` markers and locked-vault
///   (null/empty secret) skip the host, exit 2 path when nothing can run.
/// - App lock engaged (`biometrics` pref ON) → vault treated as locked →
///   background reads denied, no headless biometric prompt, exit 2.
/// - Transport: short-lived agent-HTTP + SSH sweep per host
///   (`pollHostAlerts`, 15 s timeout, max 10 hosts — parity with
///   `BackgroundAlerts.runBackgroundTick`), 6 h resend cooldown,
///   `NotificationHook.build` verbatim, `DesktopAlerts.recordCheck()` stamp
///   on every tick (T3), best-effort OS toast via `DesktopAlerts.showFresh`.
///
/// Every I/O seam is an optional parameter so `test/headless_entry_test.dart`
/// drives this file with fakes and zero plugin I/O.
library;

import 'dart:async';
import 'dart:io';

import 'package:shared_preferences/shared_preferences.dart';

import 'background/headless_check.dart';
import 'background/headless_state.dart';
import 'models/server_connection.dart';
import 'services/agent_service.dart';
import 'services/alert_poller.dart';
import 'services/app_lock.dart' show appLockPrefsKey;
import 'services/background_alerts.dart';
import 'services/desktop_alerts.dart';
import 'services/headless_security.dart';
import 'services/secure_store.dart';

/// Max hosts per tick (parity with `BackgroundAlerts.runBackgroundTick`).
const headlessMaxHosts = 10;

/// Per-host transport timeout (parity with the background tick).
const headlessFetchTimeout = Duration(seconds: 15);

/// Run the headless tick when `--poll-headless` is in [args].
///
/// Returns the process exit code (`0` tick ok, `2` skipped, `1` error), or
/// null when the flag is absent (normal UI launch proceeds). Never throws —
/// unexpected failures become exit 1 with a secret-free JSON line.
Future<int?> runHeadlessIfRequested(
  List<String> args, {
  Future<Map<String, Object?>> Function()? readPrefs,
  Future<String?> Function(String key)? readVault,
  Future<List<ServerConnection>> Function()? loadServersRaw,
  Future<List<HeadlessSignal>> Function(ServerConnection server)? fetchFor,
  Future<void> Function(String title, String body)? notify,
  Future<void> Function()? onCheckRecorded,
  Directory Function()? stateDir,
  DateTime? now,
}) async {
  if (!args.contains(headlessFlag)) return null;
  final at = now ?? DateTime.now();
  final dir = stateDir != null ? stateDir() : HeadlessPaths.stateDir();
  final lock = await HeadlessLock.tryAcquire(HeadlessPaths.lockFile(dir));
  if (lock == null) {
    // Another tick is still polling — skip, never overlap.
    _printJson(const HeadlessTickResult(
      exitCode: headlessExitSkipped,
      status: 'skipped',
      checkedAtMs: 0,
      reason: 'another headless tick is already running',
    ));
    return headlessExitSkipped;
  }
  try {
    final code = await _runTick(
      argv: args,
      readPrefs: readPrefs,
      readVault: readVault,
      loadServersRaw: loadServersRaw,
      fetchFor: fetchFor,
      notify: notify,
      onCheckRecorded: onCheckRecorded,
      dir: dir,
      now: at,
    );
    return code;
  } catch (_) {
    _printJson(HeadlessTickResult(
      exitCode: headlessExitError,
      status: 'error',
      checkedAtMs: at.millisecondsSinceEpoch,
      reason: 'headless tick failed before evaluation',
    ));
    return headlessExitError;
  } finally {
    await lock.release();
  }
}

Future<int> _runTick({
  required List<String> argv,
  required Future<Map<String, Object?>> Function()? readPrefs,
  required Future<String?> Function(String key)? readVault,
  required Future<List<ServerConnection>> Function()? loadServersRaw,
  required Future<List<HeadlessSignal>> Function(ServerConnection server)?
      fetchFor,
  required Future<void> Function(String title, String body)? notify,
  required Future<void> Function()? onCheckRecorded,
  required Directory dir,
  required DateTime now,
}) async {
  // Prefs snapshot (single read; default OFF on any failure).
  Map<String, Object?> prefsMap = const {};
  try {
    prefsMap = readPrefs != null
        ? await readPrefs()
        : await _readPrefsSnapshot();
  } catch (_) {
    prefsMap = const {};
  }
  final consentEnabled = prefsMap[BackgroundAlerts.prefEnabledKey] == true;
  // App lock engaged → vault treated as locked (fail closed, ADR-003 §1).
  final vaultUnlocked = prefsMap[appLockPrefsKey] != true;

  Future<List<HeadlessSignal>> fetchAll() async {
    List<ServerConnection> servers = const [];
    try {
      servers = loadServersRaw != null
          ? await loadServersRaw()
          : await _loadServersRawDefault();
    } catch (_) {
      servers = const [];
    }
    final out = <HeadlessSignal>[];
    var answered = false;
    for (final s in servers.where((e) => e.enabled).take(headlessMaxHosts)) {
      try {
        final signals = fetchFor != null
            ? await fetchFor(s)
                .timeout(headlessFetchTimeout)
            : await _fetchForDefault(s, readVault).timeout(
                headlessFetchTimeout);
        answered = true;
        out.addAll(signals);
      } catch (_) {
        // One sick host never sinks the run (parity: runBackgroundTick).
      }
    }
    if (!answered) {
      throw Exception('alert poll failed (no host answered)');
    }
    return out;
  }

  final state = HeadlessState.load(HeadlessPaths.stateFile(dir));
  final result = await HeadlessCheck.run(
    consentEnabled: consentEnabled,
    vaultUnlocked: vaultUnlocked,
    state: state,
    fetchAll: fetchAll,
    now: now,
    argv: argv,
    onNotify: (title, body) async {
      try {
        if (notify != null) {
          await notify(title, body);
        } else {
          await DesktopAlerts.showFreshPayload(title, body);
        }
      } catch (_) {}
    },
  );
  state.save(HeadlessPaths.stateFile(dir));

  // Staleness honesty (T3 + §8.2 invariant): every evaluated tick stamps
  // the shared last-check pref, even skips and errors.
  try {
    if (onCheckRecorded != null) {
      await onCheckRecorded();
    } else {
      await DesktopAlerts.recordCheck(now);
    }
  } catch (_) {}

  _printJson(result);
  return result.exitCode;
}

/// Default prefs snapshot via SharedPreferences (production only).
Future<Map<String, Object?>> _readPrefsSnapshot() async {
  final prefs = await SharedPreferences.getInstance();
  return {
    BackgroundAlerts.prefEnabledKey:
        prefs.getBool(BackgroundAlerts.prefEnabledKey) ?? false,
    appLockPrefsKey: prefs.getBool(appLockPrefsKey) ?? false,
  };
}

/// Default raw server load via the store of record WITHOUT healing
/// (ADR-003: no keychain writes headless — healing stays interactive-only;
/// Option A: the prefs key is named only in `SecureStore`).
Future<List<ServerConnection>> _loadServersRawDefault() async {
  final raw = await SecureStore.readRawServerListJson();
  if (raw == null || raw.isEmpty) return const [];
  return ServerConnection.decodeList(raw);
}

/// Default per-host fetch: read-only vault resolution + short-lived
/// agent/SSH legs. Hosts without a resolvable `secure:` credential are
/// skipped (no plaintext fallback, locked-vault denies).
Future<List<HeadlessSignal>> _fetchForDefault(
  ServerConnection s,
  Future<String?> Function(String key)? readVault,
) async {
  final marker = s.credential;
  final vaultKey = _vaultKeyForMarker(marker);
  final vaultSecret = vaultKey.isEmpty
      ? null
      : (readVault != null
          ? await readVault(vaultKey)
          : await SecureStore.readSecret(vaultKey));
  final secret = HeadlessSecurity.resolveCredential(
    marker: marker,
    vaultSecret: vaultSecret,
  );
  if (secret == null) return const [];
  final agentToken = readVault != null
      ? await readVault(SecureStore.agentTokenKey(s.id))
      : await SecureStore.readSecret(SecureStore.agentTokenKey(s.id));
  final agent = AgentService();
  final withSecret = s.copyWith(credential: secret);
  final alerts = await pollHostAlerts(
    agent,
    withSecret,
    agentToken: agentToken,
    sshSweep: true,
  );
  return HeadlessCheck.signalsFromAlerts(alerts);
}

/// Vault key for a `secure:<key>` marker (empty for non-markers).
String _vaultKeyForMarker(String marker) {
  if (!marker.startsWith(HeadlessSecurity.securePrefix)) return '';
  return marker.substring(HeadlessSecurity.securePrefix.length);
}

void _printJson(HeadlessTickResult result) {
  try {
    // ignore: avoid_print
    print(result.toJsonString());
  } catch (_) {}
}
