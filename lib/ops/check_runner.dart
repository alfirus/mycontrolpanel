// SPDX-License-Identifier: MIT
/// Supervised single headless-tick run + ledger write (TM-2, Zara owns).
///
/// `mycontrolpanel-check` does NOT poll or notify itself — the frozen
/// pipeline (`lib/background/headless_check.dart`, Lina) owns
/// poll-evaluate-notify, and Lisa's `bin/mcpoll.dart` owns real-fetch.
/// This runner supervises exactly one tick of a *provider* subprocess
/// (default: the installed app binary with the exact `--poll-headless`
/// argv — never re-templated, never extended with secret material),
/// validates its contract-shaped JSON stdout, appends one [RunLedger]
/// record, and exits with the provider's code.
///
/// Injectable [runProvider] keeps unit tests hermetic (no subprocesses);
/// the default implementation shells out with a kill-timeout so a hung
/// provider becomes an exit-1 ledger record, never a wedged scheduler.
///
/// Pure `dart:io` / `dart:convert` only (see `run_ledger.dart`).
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:my_control_panel/background/headless_state.dart';
import 'package:my_control_panel/services/headless_security.dart';

import 'run_ledger.dart';

/// Raw outcome of one provider invocation (subprocess or test fake).
class ProviderResult {
  const ProviderResult({
    required this.exitCode,
    required this.stdout,
    required this.stderr,
    required this.durationMs,
    this.timedOut = false,
  });

  final int exitCode;
  final String stdout;
  final String stderr;
  final int durationMs;
  final bool timedOut;
}

/// One supervised tick: provider outcome + parsed tick fields + ledger.
class SupervisedRun {
  const SupervisedRun({
    required this.exitCode,
    required this.status,
    required this.tickExitCode,
    required this.freshTitles,
    required this.reason,
    required this.durationMs,
    required this.ledgerWritten,
    required this.ledgerPath,
  });

  /// Process exit code for the `check` command (== provider code, or 1
  /// when the wrapper itself failed to supervise).
  final int exitCode;

  /// Tick status per contract: ok | notified | skipped | error.
  final String status;
  final int tickExitCode;
  final List<String> freshTitles;
  final String? reason;
  final int durationMs;
  final bool ledgerWritten;
  final String ledgerPath;

  Map<String, dynamic> toJson() => {
        'version': 1,
        'tool': 'mycontrolpanel-check',
        'status': status,
        'exitCode': exitCode,
        'tickExitCode': tickExitCode,
        'freshTitles': freshTitles,
        if (reason != null) 'reason': reason,
        'durationMs': durationMs,
        'ledger': {'path': ledgerPath, 'written': ledgerWritten},
      };

  String toJsonString() => jsonEncode(toJson());
}

/// Supervises one tick run.
abstract class CheckRunner {
  /// Default provider timeout (generous: slow SSH legs take up to
  /// 15 s/host × 10 hosts inside the provider).
  static const defaultTimeout = Duration(minutes: 5);

  /// Run one supervised tick.
  ///
  /// - [tickCommand]/[tickArgs]: provider argv. Managed installs pass the
  ///   installed app binary + exactly `[--poll-headless]`; CI/dev pass a
  ///   fake tick. Secret-bearing args are rejected before spawn.
  /// - [stateDir]: ledger location (defaults to [HeadlessPaths.stateDir]).
  /// - [runProvider]: test seam; defaults to [spawnProvider].
  /// Never throws — every failure path is a [SupervisedRun] with a
  /// ledger record.
  static Future<SupervisedRun> run({
    required String tickCommand,
    List<String> tickArgs = const [headlessFlag],
    Duration timeout = defaultTimeout,
    Directory? stateDir,
    Future<ProviderResult> Function()? runProvider,
    DateTime? now,
  }) async {
    final dir = stateDir ?? HeadlessPaths.stateDir();
    final ledger = RunLedger.ledgerFile(dir);
    final atMs = (now ?? DateTime.now()).millisecondsSinceEpoch;

    ProviderResult provider;
    try {
      provider = runProvider != null
          ? await runProvider()
          : await spawnProvider(tickCommand, tickArgs, timeout);
    } catch (e) {
      return _record(
        atMs: atMs,
        providerLabel: _label(tickCommand),
        ledger: ledger,
        exitCode: headlessExitError,
        status: 'error',
        tickExitCode: headlessExitError,
        reason: 'check failed to launch tick provider: $e',
        durationMs: 0,
      );
    }

    if (provider.timedOut) {
      return _record(
        atMs: atMs,
        providerLabel: _label(tickCommand),
        ledger: ledger,
        exitCode: headlessExitError,
        status: 'error',
        tickExitCode: headlessExitError,
        reason:
            'tick provider timed out after ${timeout.inSeconds}s and was killed',
        durationMs: provider.durationMs,
      );
    }

    final tick = parseTickJson(provider.stdout);
    if (tick == null) {
      final hint = provider.stdout.trim().isEmpty
          ? 'tick provider emitted no output'
          : 'tick provider emitted no contract JSON (first 160 chars: ${_preview(provider.stdout)})';
      return _record(
        atMs: atMs,
        providerLabel: _label(tickCommand),
        ledger: ledger,
        exitCode: headlessExitError,
        status: 'error',
        tickExitCode: headlessExitError,
        reason: hint,
        durationMs: provider.durationMs,
      );
    }

    return _record(
      atMs: atMs,
      providerLabel: _label(tickCommand),
      ledger: ledger,
      exitCode: tick.exitCode,
      status: tick.status,
      tickExitCode: tick.exitCode,
      freshTitles: tick.freshTitles,
      reason: tick.reason,
      durationMs: provider.durationMs,
    );
  }

  /// Default provider: spawn [command] with [args], kill after [timeout].
  static Future<ProviderResult> spawnProvider(
    String command,
    List<String> args,
    Duration timeout,
  ) async {
    final violations = HeadlessSecurity.findSecretMaterialInArgs(
        [command, ...args]);
    if (violations.isNotEmpty) {
      return const ProviderResult(
        exitCode: headlessExitError,
        stdout: '',
        stderr: 'refused: tick argv carries forbidden material',
        durationMs: 0,
      );
    }
    final sw = Stopwatch()..start();
    try {
      // Windows resolves SDK shims (dart.bat) only via the shell;
      // production providers are real .exe files either way.
      final future =
          Process.run(command, args, runInShell: Platform.isWindows);
      final result = await future.timeout(timeout);
      sw.stop();
      return ProviderResult(
        exitCode: result.exitCode,
        stdout: result.stdout.toString(),
        stderr: result.stderr.toString(),
        durationMs: sw.elapsedMilliseconds,
      );
    } on TimeoutException {
      sw.stop();
      try {
        // Process.run has no handle to kill; the timeout lets the orphan
        // run out — record it and move on (the OS reaps it; the next
        // tick single-flights on headless.lock, never overlaps).
      } catch (_) {}
      return ProviderResult(
        exitCode: headlessExitError,
        stdout: '',
        stderr: 'tick provider timed out',
        durationMs: sw.elapsedMilliseconds,
        timedOut: true,
      );
    } catch (e) {
      sw.stop();
      return ProviderResult(
        exitCode: headlessExitError,
        stdout: '',
        stderr: 'tick provider failed to launch: $e',
        durationMs: sw.elapsedMilliseconds,
      );
    }
  }

  /// Extract the first contract-shaped JSON object from provider stdout.
  ///
  /// Returns null unless the object carries a numeric `version`, a known
  /// `status`, and a numeric `exitCode` — multi-line harness chatter
  /// (PASS/FAIL lines, log preambles) is skipped line by line.
  static ParsedTick? parseTickJson(String stdout) {
    const known = {'ok', 'notified', 'skipped', 'error'};
    for (final line in const LineSplitter().convert(stdout)) {
      final trimmed = line.trim();
      if (!trimmed.startsWith('{')) continue;
      try {
        final decoded = jsonDecode(trimmed);
        if (decoded is! Map<String, dynamic>) continue;
        final version = decoded['version'];
        final status = decoded['status'];
        final exitCode = decoded['exitCode'];
        if (version is! int) continue;
        if (status is! String || !known.contains(status)) continue;
        if (exitCode is! int) continue;
        final fresh = decoded['freshTitles'];
        final reason = decoded['reason'];
        return ParsedTick(
          status: status,
          exitCode: exitCode,
          freshTitles: fresh is List
              ? fresh.map((e) => e.toString()).toList()
              : const <String>[],
          reason: reason is String && reason.isNotEmpty ? reason : null,
        );
      } catch (_) {
        continue;
      }
    }
    return null;
  }

  static SupervisedRun _record({
    required int atMs,
    required String providerLabel,
    required File ledger,
    required int exitCode,
    required String status,
    required int tickExitCode,
    required int durationMs,
    List<String> freshTitles = const [],
    String? reason,
  }) {
    final record = RunLedger.buildRecord(
      atMs: atMs,
      provider: providerLabel,
      exitCode: tickExitCode,
      status: status,
      durationMs: durationMs,
      freshTitles: freshTitles,
      reason: reason,
    );
    final written = RunLedger.append(ledger, record);
    return SupervisedRun(
      exitCode: exitCode,
      status: status,
      tickExitCode: tickExitCode,
      freshTitles: freshTitles,
      reason: reason,
      durationMs: durationMs,
      ledgerWritten: written,
      ledgerPath: ledger.path,
    );
  }

  /// Basename only — full install paths embed the OS username.
  static String _label(String command) {
    final normalized = command.replaceAll('\\', '/');
    final base = normalized.split('/').lastWhere(
        (s) => s.isNotEmpty,
        orElse: () => command);
    return base.isEmpty ? command : base;
  }

  static String _preview(String s) {
    final oneLine = s.replaceAll(RegExp(r'\s+'), ' ').trim();
    return oneLine.length <= 160 ? oneLine : oneLine.substring(0, 160);
  }
}

/// One contract-shaped tick line parsed from provider stdout.
class ParsedTick {
  const ParsedTick({
    required this.status,
    required this.exitCode,
    required this.freshTitles,
    this.reason,
  });

  final String status;
  final int exitCode;
  final List<String> freshTitles;
  final String? reason;
}
