// SPDX-License-Identifier: MIT
/// `mycontrolpanel-check` — supervised headless-tick CLI (TM-2, Zara owns).
///
/// Scheduler-facing wrapper around the frozen `--poll-headless` tick: run
/// exactly one supervised cycle, append one JSONL [RunLedger] record, and
/// exit with the tick's code. The managed scheduler lifecycle
/// (`install` / `verify` / `uninstall` / `status`, stacked PR2) routes the
/// OS task/timer through this wrapper; the poll argv it supervises stays
/// exactly `--poll-headless` (never re-templated, never secret-bearing).
///
/// Usage:
///   mycontrolpanel-check check [--tick-cmd <exe>] [--tick-arg <a>]...
///       [--timeout-sec N] [--state-dir <path>]
///   mycontrolpanel-check ledger [--tail N] [--json] [--state-dir <path>]
///   mycontrolpanel-check --help
///
/// Pure Dart only (`dart:io` + pure lib modules) — MUST stay runnable
/// under `dart run`. Never import Flutter or plugins here.
///
/// Exit codes for `check` mirror the tick (0 ok / 2 skipped / 1 error).
library;

import 'dart:io';

import 'package:my_control_panel/background/headless_state.dart';
import 'package:my_control_panel/ops/check_runner.dart';
import 'package:my_control_panel/ops/run_ledger.dart';

Future<void> main(List<String> args) async {
  if (args.contains('--help') || args.contains('-h')) {
    _usage();
    return;
  }
  final cmd = args.isEmpty ? 'check' : args.first;
  switch (cmd) {
    case 'check':
      exitCode = await _check(args.skip(1).toList());
    case 'ledger':
      exitCode = _ledger(args.skip(1).toList());
    default:
      stderr.writeln('mycontrolpanel-check: unknown command "$cmd".');
      _usage();
      exitCode = 2;
  }
}

void _usage() {
  // ignore: avoid_print
  print('''mycontrolpanel-check — supervised headless-tick wrapper (Zara).

Usage:
  mycontrolpanel-check check [--tick-cmd <exe>] [--tick-arg <arg>]...
      [--timeout-sec N] [--state-dir <path>]
  mycontrolpanel-check ledger [--tail N] [--json] [--state-dir <path>]
  mycontrolpanel-check --help

check: run one supervised tick of <exe> (default: installed app binary
  with exactly --poll-headless), append one JSONL run record, exit with
  the tick's code (0 ok / 2 skipped / 1 error).
ledger: print the tail of headless_runs.jsonl (newest last).

Managed scheduler lifecycle (install/verify/uninstall/status) arrives in
the stacked lifecycle PR; the manual scheduler path is
docs/runbooks/headless-manual-install.md.''');
}

String? _flagValue(List<String> args, String flag) {
  for (var i = 0; i < args.length; i++) {
    final arg = args[i];
    if (arg == flag && i + 1 < args.length) return args[i + 1];
    if (arg.startsWith('$flag=')) {
      return arg.substring(flag.length + 1);
    }
  }
  return null;
}

List<String> _flagValues(List<String> args, String flag) {
  final out = <String>[];
  for (var i = 0; i < args.length; i++) {
    final arg = args[i];
    if (arg == flag && i + 1 < args.length) out.add(args[i + 1]);
    if (arg.startsWith('$flag=')) {
      out.add(arg.substring(flag.length + 1));
    }
  }
  return out;
}

String _defaultTickCommand() {
  if (Platform.isWindows) {
    final base = Platform.environment['LOCALAPPDATA'];
    if (base != null && base.isNotEmpty) {
      return '$base\\MyControlPanel\\mycontrolpanel.exe';
    }
    return 'mycontrolpanel.exe';
  }
  if (Platform.isMacOS) {
    return '/Applications/MyControlPanel.app/Contents/MacOS/mycontrolpanel';
  }
  final home = Platform.environment['HOME'];
  if (home != null && home.isNotEmpty) {
    return '$home/.local/share/mycontrolpanel/mycontrolpanel';
  }
  return 'mycontrolpanel';
}

Future<int> _check(List<String> args) async {
  final tickCmd = _flagValue(args, '--tick-cmd') ?? _defaultTickCommand();
  final tickArgs = _flagValues(args, '--tick-arg');
  final timeoutSec =
      int.tryParse(_flagValue(args, '--timeout-sec') ?? '300') ?? 300;
  final stateDirFlag = _flagValue(args, '--state-dir');
  final dir = HeadlessPaths.stateDir(stateDirOverride: stateDirFlag);

  final run = await CheckRunner.run(
    tickCommand: tickCmd,
    tickArgs: tickArgs.isEmpty ? const ['--poll-headless'] : tickArgs,
    timeout: Duration(seconds: timeoutSec),
    stateDir: dir,
  );
  // ignore: avoid_print
  print(run.toJsonString());
  return run.exitCode;
}

int _ledger(List<String> args) {
  final tailN = int.tryParse(_flagValue(args, '--tail') ?? '20') ?? 20;
  final asJson = args.contains('--json');
  final stateDirFlag = _flagValue(args, '--state-dir');
  final dir = HeadlessPaths.stateDir(stateDirOverride: stateDirFlag);
  final file = RunLedger.ledgerFile(dir);
  final records = RunLedger.tail(file, limit: tailN);
  if (asJson) {
    for (final record in records) {
      // ignore: avoid_print
      print(record.toString());
    }
  } else {
    if (records.isEmpty) {
      // ignore: avoid_print
      print('ledger empty (${file.path})');
    }
    for (final record in records) {
      final at = DateTime.fromMillisecondsSinceEpoch(
          (record['atMs'] as int? ?? 0));
      // ignore: avoid_print
      print('$at  ${record['status']} exit=${record['exitCode']} '
          'fresh=${record['freshCount']} dur=${record['durationMs']}ms'
          '${record['reason'] != null ? '  (${record['reason']})' : ''}');
    }
  }
  return 0;
}
