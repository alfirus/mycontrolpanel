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
import 'models/mock_data.dart' show DeployItem;
import 'models/server_connection.dart';
import 'services/agent_service.dart';
import 'services/alert_poller.dart';
import 'services/app_lock.dart' show appLockPrefsKey;
import 'services/background_alerts.dart';
import 'services/ci_sync.dart';
import 'services/desktop_alerts.dart';
import 'services/github_service.dart';
import 'services/gitlab_service.dart';
import 'services/headless_security.dart';
import 'services/headless_slice.dart';
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
///
/// CI enrichment (Elizabeth slice): [fetchRuns] supplies the failed-CI
/// half of the in-app verdict (`AlertWatch.currentKeys(alerts, runs)`).
/// Production default reads tracked repos + read-only vault tokens and
/// syncs via `CiSyncService` (cache stands in on failure); a throwing CI
/// fetch never sinks the host tick.
Future<int?> runHeadlessIfRequested(
  List<String> args, {
  Future<Map<String, Object?>> Function()? readPrefs,
  Future<String?> Function(String key)? readVault,
  Future<List<ServerConnection>> Function()? loadServersRaw,
  Future<List<HeadlessSignal>> Function(ServerConnection server)? fetchFor,
  Future<List<DeployItem>> Function()? fetchRuns,
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
      fetchRuns: fetchRuns,
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
  required Future<List<DeployItem>> Function()? fetchRuns,
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
    // CI enrichment (slice parity): failed runs ride the host tick so the
    // headless verdict covers the same `AlertWatch.currentKeys(alerts,
    // runs)` set the in-app rail diffs. CI sickness never sinks the host
    // tick — and `answered` stays host-driven (frozen exit semantics).
    try {
      final runs = fetchRuns != null
          ? await fetchRuns()
          : await _fetchRunsDefault(prefsMap, readVault);
      out.addAll(HeadlessSlice.signalsFromCiRuns(runs));
    } catch (_) {
      // One sick CI leg never sinks the run.
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
    // CI enrichment reads (slice parity — same keys the control center
    // screen reads; read-only, never written headless).
    'github_repos': prefs.getStringList('github_repos') ?? const <String>[],
    'gitlab_projects':
        prefs.getStringList('gitlab_projects') ?? const <String>[],
    'gitlab_base_url':
        prefs.getString('gitlab_base_url') ?? 'https://gitlab.com',
  };
}

/// Default CI fetch: GitHub Actions runs + GitLab pipelines for the
/// user's tracked repos/projects, mapped downstream to `kind: 'ci'`
/// signals. Headless-safe by construction:
///
/// - Tokens come from the vault read-only (`github_token` /
///   `gitlab_token` via [readVault] or `SecureStore.readSecret`);
///   absent/empty token ⇒ that VCS is skipped, never an error.
/// - [CiSyncService] never throws (per-repo backoff + last-good cache
///   stands in); GitLab legs are per-project try/catch. Total CI failure
///   ⇒ empty list, and the caller swallows even that.
/// - Capped + time-boxed (a scheduler tick must stay short).
Future<List<DeployItem>> _fetchRunsDefault(
  Map<String, Object?> prefs,
  Future<String?> Function(String key)? readVault,
) async {
  final out = <DeployItem>[];
  try {
    final repos = ((prefs['github_repos'] as List?) ?? const [])
        .map((e) => e.toString().trim())
        .where((e) => e.isNotEmpty)
        .take(6)
        .toList();
    if (repos.isNotEmpty) {
      final token = readVault != null
          ? await readVault('github_token')
          : await SecureStore.readSecret('github_token');
      if (token != null && token.isNotEmpty) {
        final sync = CiSyncService(perRepoLimit: 4);
        final res = await sync
            .syncRepos(GithubService(token), repos)
            .timeout(const Duration(seconds: 60));
        out.addAll(res.runs);
      }
    }
  } catch (_) {
    // GitHub sickness never sinks the tick.
  }
  try {
    final projects = ((prefs['gitlab_projects'] as List?) ?? const [])
        .map((e) => e.toString().trim())
        .where((e) => e.isNotEmpty)
        .take(6)
        .toList();
    if (projects.isNotEmpty) {
      final base = (prefs['gitlab_base_url']?.toString() ?? '').trim();
      final token = readVault != null
          ? await readVault('gitlab_token')
          : await SecureStore.readSecret('gitlab_token');
      if (token != null && token.isNotEmpty) {
        final svc = GitlabService(
          baseUrl: base.isEmpty ? 'https://gitlab.com' : base,
          token: token,
        );
        for (final p in projects) {
          try {
            out.addAll(await svc
                .projectPipelines(p, limit: 4)
                .timeout(const Duration(seconds: 30)));
          } catch (_) {}
        }
      }
    }
  } catch (_) {
    // GitLab sickness never sinks the tick.
  }
  return out;
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
