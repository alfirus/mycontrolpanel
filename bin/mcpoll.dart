// SPDX-License-Identifier: MIT
/// mcpoll — headless agent poller CLI (Lisa, TM-1 follow-up).
///
/// `dart run my_control_panel:mcpoll --consent --host H` (or `--servers`):
/// no UI, one tick, machine-readable JSON on stdout, process exit.
///
/// What this reuses verbatim (never reimplemented — Lina's frozen table):
/// - Gate + exit codes: [HeadlessSecurity] (consent-first; the vault reads
///   unlocked because mcpoll carries no vault — agent tokens arrive via the
///   environment, never argv).
/// - Backoff: [PollPolicy] via [HeadlessCheck.run], streak persisted in
///   the shared `headless_state.json` (+ `headless.lock` single-flight, so
///   mcpoll and the app `--poll-headless` rail never overlap in one dir).
/// - Verdicts: [HeadlessCheck.rules] (`AlertRules` 80/90) + gauges via
///   [HeadlessCheck.thresholds] (0.85/0.95, cpu/ram only).
/// - Payload: [NotificationHook.build] via [HeadlessCheck.run], title
///   `'MyControlPanel alert'`, transition-only against the persisted
///   seen-set (`kind::owner::title`).
///
/// Transport: short-lived agent HTTP per host (`fetchHostSignals`,
/// snapshot-first with metrics/sysstats fallback, per-host timeout,
/// max 10 hosts, one sick host never sinks the run). The SSH sweep stays
/// in the app (`pollHostAlerts`) — mcpoll is the agent-HTTP rail.
///
/// Pure Dart only (`dart:io` + pure lib modules): it MUST stay runnable
/// under plain `dart run`. Never import plugins, vault, or prefs here.
library;

import 'dart:io';

import 'package:my_control_panel/background/headless_check.dart';
import 'package:my_control_panel/background/headless_state.dart';
import 'package:my_control_panel/mcpoll/config.dart';
import 'package:my_control_panel/mcpoll/snapshot_fetch.dart';
import 'package:my_control_panel/services/headless_security.dart';

Future<void> main(List<String> args) async {
  late final McpollConfig config;
  try {
    config = parseMcpollArgs(args);
  } on McpollHelp {
    // ignore: avoid_print
    print(mcpollUsage());
    return;
  } on McpollArgError catch (e) {
    stderr.writeln(e);
    stderr.writeln(mcpollUsage());
    exitCode = headlessExitError;
    return;
  }

  final dir =
      HeadlessPaths.stateDir(stateDirOverride: config.stateDirOverride);
  final lock = await HeadlessLock.tryAcquire(HeadlessPaths.lockFile(dir));
  if (lock == null) {
    // Another tick (app rail or mcpoll) is still polling — skip, never
    // overlap.
    // ignore: avoid_print
    print(const HeadlessTickResult(
      exitCode: headlessExitSkipped,
      status: 'skipped',
      checkedAtMs: 0,
      reason: 'another headless tick is already running',
    ).toJsonString());
    exitCode = headlessExitSkipped;
    return;
  }
  try {
    final state = HeadlessState.load(HeadlessPaths.stateFile(dir));
    final result = await HeadlessCheck.run(
      consentEnabled: config.consent,
      vaultUnlocked: true,
      state: state,
      fetchAll: () => _fetchAll(config),
      now: DateTime.now(),
      argv: args,
    );
    state.save(HeadlessPaths.stateFile(dir));
    // ignore: avoid_print
    print(result.toJsonString());
    exitCode = result.exitCode;
  } catch (_) {
    // ignore: avoid_print
    print(HeadlessTickResult(
      exitCode: headlessExitError,
      status: 'error',
      checkedAtMs: DateTime.now().millisecondsSinceEpoch,
      reason: 'mcpoll tick failed before evaluation',
    ).toJsonString());
    exitCode = headlessExitError;
  } finally {
    await lock.release();
  }
}

/// Agent-HTTP sweep over the configured hosts. Per-host failures are
/// swallowed (parity: `pollHostAlerts`); only a total failure throws.
Future<List<HeadlessSignal>> _fetchAll(McpollConfig config) async {
  final out = <HeadlessSignal>[];
  var answered = false;
  for (final h in config.hosts.take(config.maxHosts)) {
    try {
      final signals = await fetchHostSignals(
        h,
        timeout: config.timeout,
        token: resolveToken(h),
        noSnapshot: config.noSnapshot,
      ).timeout(config.timeout);
      answered = true;
      out.addAll(signals);
    } catch (_) {
      // One sick host never sinks the run.
    }
  }
  if (!answered) {
    throw Exception('mcpoll: no host answered (agent :9108 down)');
  }
  return out;
}
