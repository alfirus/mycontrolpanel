// SPDX-License-Identifier: MIT
/// CI/dev harness for the shared headless pipeline (TM-1, Lina owns).
///
/// `dart run my_control_panel:headless_check --self-test` exercises
/// `lib/background/headless_check.dart` with a fake transport against a
/// temp state dir — no network, no vault, no plugins — so the CI headless
/// job (Windows + Linux) proves the contract without building the app.
///
/// This is a HARNESS, not the shipped scheduler target: OS schedulers
/// invoke the installed app binary as
/// `mycontrolpanel[.exe] --poll-headless` (see
/// `docs/specs/headless-cli-contract.md`). Lisa's `bin/mcpoll.dart` owns
/// the real-fetch poller CLI; keep the two files' responsibilities
/// separate (Lina's handoff on t_caf477ca records the boundary).
///
/// Pure Dart only (`dart:io` + pure lib modules) — it MUST stay runnable
/// under `dart run`. Never import Flutter or plugins here.
library;

import 'dart:io';

import 'package:my_control_panel/background/headless_check.dart';
import 'package:my_control_panel/background/headless_state.dart';
import 'package:my_control_panel/services/headless_security.dart';

Future<void> main(List<String> args) async {
  if (args.contains('--help') || args.contains('-h')) {
    _usage();
    return;
  }
  if (!args.contains('--self-test')) {
    stderr.writeln(
        'headless_check: nothing to do (pass --self-test or --help).');
    _usage();
    exitCode = 2;
    return;
  }
  exitCode = await _selfTest(args);
}

void _usage() {
  // ignore: avoid_print
  print('''headless_check — TM-1 headless pipeline harness (Lina).

Usage:
  dart run headless_check --self-test [--state-dir <path>]

Modes:
  --self-test   Run two ticks against a fake transport in a temp (or given)
                state dir: tick 1 must notify (exit 0), tick 2 must stay
                transition-only silent (exit 0). Prints both JSON lines.
  --help        This text.

Exit codes: 0 = self-test green, 1 = self-test FAILED.''');
}

/// Two-tick self-test: notify-then-silent proves transition-only dedup,
/// the file lock proves single-flight, the state file proves persistence.
Future<int> _selfTest(List<String> args) async {
  final dirArg = _flagValue(args, '--state-dir');
  final dir = dirArg != null
      ? Directory(dirArg)
      : await Directory.systemTemp.createTemp('mcp-headless-selftest');
  try {
    await dir.create(recursive: true);
  } catch (e) {
    stderr.writeln('headless_check: cannot create state dir: $e');
    return 1;
  }

  List<HeadlessSignal> fakeTransport() => const [
        HeadlessSignal(
            kind: 'alert',
            title: 'Disk 82% full on /',
            owner: 'selftest-host'),
        HeadlessSignal(
            kind: 'alert',
            title: 'Service failed: nginx',
            owner: 'selftest-host'),
      ];

  var failures = 0;

  Future<HeadlessTickResult> tick() async {
    final lock =
        await HeadlessLock.tryAcquire(HeadlessPaths.lockFile(dir));
    if (lock == null) {
      return const HeadlessTickResult(
        exitCode: 2,
        status: 'skipped',
        checkedAtMs: 0,
        reason: 'lock contention in self-test',
      );
    }
    try {
      final state = HeadlessState.load(HeadlessPaths.stateFile(dir));
      final result = await HeadlessCheck.run(
        consentEnabled: true,
        vaultUnlocked: true,
        state: state,
        fetchAll: () async => fakeTransport(),
        now: DateTime.now(),
        argv: const ['--poll-headless'],
      );
      state.save(HeadlessPaths.stateFile(dir));
      return result;
    } finally {
      await lock.release();
    }
  }

  void check(bool cond, String label, [Object? detail]) {
    // ignore: avoid_print
    print('${cond ? 'PASS' : 'FAIL'}  $label'
        '${detail == null ? '' : '  ($detail)'}');
    if (!cond) failures++;
  }

  // Tick 1: fresh signals → notify, exit 0.
  final first = await tick();
  // ignore: avoid_print
  print(first.toJsonString());
  check(first.exitCode == headlessExitOk, 'tick1 exit 0', first.exitCode);
  check(first.status == 'notified', 'tick1 notified', first.status);
  check(first.freshTitles.length == 2, 'tick1 two fresh titles',
      first.freshTitles);
  check(first.notification != null &&
      (first.notification!['body'] ?? '').isNotEmpty, 'tick1 payload body');

  // Lock single-flight: hold the lock, a second acquire must fail fast.
  final held =
      await HeadlessLock.tryAcquire(HeadlessPaths.lockFile(dir));
  check(held != null, 'lock acquirable when free');
  if (held != null) {
    final contended = await HeadlessLock.tryAcquire(
      HeadlessPaths.lockFile(dir),
      timeout: const Duration(milliseconds: 200),
    );
    check(contended == null, 'second acquire denied while held');
    await held.release();
  }

  // Tick 2: same signals → transition-only silent, exit 0.
  final second = await tick();
  // ignore: avoid_print
  print(second.toJsonString());
  check(second.exitCode == headlessExitOk, 'tick2 exit 0', second.exitCode);
  check(second.status == 'ok', 'tick2 silent (no re-notify)', second.status);
  check(!second.notified && second.freshTitles.isEmpty, 'tick2 no fresh');

  // Gate spot-checks (ADR-003): consent OFF and locked vault skip.
  final state = HeadlessState.load(HeadlessPaths.stateFile(dir));
  final skipConsent = await HeadlessCheck.run(
    consentEnabled: false,
    vaultUnlocked: true,
    state: state,
    fetchAll: () async => fakeTransport(),
    now: DateTime.now(),
  );
  check(skipConsent.exitCode == headlessExitSkipped, 'consent OFF → exit 2');
  final skipVault = await HeadlessCheck.run(
    consentEnabled: true,
    vaultUnlocked: false,
    state: state,
    fetchAll: () async => fakeTransport(),
    now: DateTime.now(),
  );
  check(skipVault.exitCode == headlessExitSkipped, 'vault locked → exit 2');

  // Stdout hygiene: encoded payloads carry no secret-shaped material.
  final hygiene = HeadlessSecurity.findSecretMaterialInArgs(
      [first.toJsonString(), second.toJsonString()]);
  check(hygiene.isEmpty, 'stdout carries no secret material');

  // ignore: avoid_print
  print(failures == 0
      ? 'SELF-TEST GREEN (${dir.path})'
      : 'SELF-TEST RED ($failures failure(s))');
  if (dirArg == null) {
    try {
      await dir.delete(recursive: true);
    } catch (_) {}
  }
  return failures == 0 ? 0 : 1;
}

String? _flagValue(List<String> args, String flag) {
  final i = args.indexOf(flag);
  if (i < 0 || i + 1 >= args.length) return null;
  final v = args[i + 1];
  if (v.startsWith('--')) return null;
  return v;
}
