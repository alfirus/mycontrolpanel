// SPDX-License-Identifier: MIT
/// `mycontrolpanel-check` — supervised headless-tick CLI + scheduler
/// lifecycle (TM-2, Zara owns).
///
/// Scheduler-facing wrapper around the frozen `--poll-headless` tick:
/// supervise one cycle, append one JSONL [RunLedger] record, and manage
/// the OS task/timer that fires it (`install` / `verify` / `uninstall` /
/// `status`). The managed artifacts start from Lina's templates
/// (`scripts/headless/...`) with triggers/principals/settings preserved;
/// only the Exec action routes through this wrapper, and the embedded
/// poll argv stays exactly `--poll-headless` (never re-templated, never
/// secret-bearing — enforced by `verify` via
/// `HeadlessSecurity.validateSchedulerArtifact`).
///
/// Usage:
///   mycontrolpanel-check check [--tick-cmd <exe>] [--tick-arg <arg>]...
///       [--timeout-sec N] [--state-dir <path>]
///   mycontrolpanel-check ledger [--tail N] [--json] [--state-dir <path>]
///   mycontrolpanel-check install --install-dir <dir> --wrapper <exe>
///       [--task-path <tn>] [--unit-name <n>] [--sandbox <dir>]
///       [--install-user <DOMAIN/user>] [--force] [--template-dir <dir>]
///   mycontrolpanel-check verify [--task-path <tn>] [--sandbox <dir>]
///       [--artifact <path>] [--template-dir <dir>]
///   mycontrolpanel-check uninstall [--task-path <tn>] [--sandbox <dir>]
///   mycontrolpanel-check status [--json] [--stale-after-min N]
///       [--state-dir <path>] [--sandbox <dir>]
///   mycontrolpanel-check --help
///
/// Pure Dart only (`dart:io` + pure lib modules) — MUST stay runnable
/// under `dart run`. Never import Flutter or plugins here.
///
/// Exit codes: `check` mirrors the tick (0 ok / 2 skipped / 1 error);
/// install/verify/uninstall exit 0 on success, 1 on failure/violations.
library;

import 'dart:convert';
import 'dart:io';

import 'package:my_control_panel/background/headless_state.dart';
import 'package:my_control_panel/ops/check_runner.dart';
import 'package:my_control_panel/ops/run_ledger.dart';
import 'package:my_control_panel/ops/scheduler_lifecycle.dart';

Future<void> main(List<String> args) async {
  if (args.contains('--help') || args.contains('-h')) {
    _usage();
    return;
  }
  final cmd = args.isEmpty ? 'check' : args.first;
  final rest = args.length <= 1 ? <String>[] : args.skip(1).toList();
  switch (cmd) {
    case 'check':
      exitCode = await _check(rest);
    case 'ledger':
      exitCode = _ledger(rest);
    case 'install':
      exitCode = await _install(rest);
    case 'verify':
      exitCode = await _verify(rest);
    case 'uninstall':
      exitCode = await _uninstall(rest);
    case 'status':
      exitCode = await _status(rest);
    default:
      stderr.writeln('mycontrolpanel-check: unknown command "$cmd".');
      _usage();
      exitCode = 2;
  }
}

void _usage() {
  // ignore: avoid_print
  print('''mycontrolpanel-check — supervised headless-tick wrapper + scheduler lifecycle (Zara).

Usage:
  mycontrolpanel-check check [--tick-cmd <exe>] [--tick-arg <arg>]...
      [--timeout-sec N] [--state-dir <path>]
  mycontrolpanel-check ledger [--tail N] [--json] [--state-dir <path>]
  mycontrolpanel-check install --install-dir <dir> --wrapper <exe>
      [--task-path <tn>] [--unit-name <n>] [--unit-dir <dir>]
      [--install-user <DOMAIN/user>] [--sandbox <dir>] [--no-reload]
      [--force] [--template-dir <dir>]
  mycontrolpanel-check verify [--task-path <tn>] [--unit-name <n>]
      [--unit-dir <dir>] [--sandbox <dir>] [--artifact <path>]
      [--template-dir <dir>] [--json]
  mycontrolpanel-check uninstall [--task-path <tn>] [--unit-name <n>]
      [--unit-dir <dir>] [--sandbox <dir>] [--no-reload]
  mycontrolpanel-check status [--json] [--stale-after-min N]
      [--state-dir <path>] [--sandbox <dir>]
  mycontrolpanel-check --help

check: run one supervised tick, append one JSONL run record, exit with
  the tick's code (0 ok / 2 skipped / 1 error).
install: consent-gated install of the per-user scheduler artifact
  (preflight tick first; aborts when the tick cannot fire unless
  --force). macOS is Elizabeth's rail and is refused with guidance.
verify: validate the installed/filled artifact against the frozen
  template invariants (exit 1 on violations).
status: scheduler presence + ledger tail + staleness verdict
  (fresh/stale/never-ran) with missed-heartbeat detection.''');
}

bool _hasFlag(List<String> args, String flag) => args.contains(flag);

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
  final asJson = _hasFlag(args, '--json');
  final stateDirFlag = _flagValue(args, '--state-dir');
  final dir = HeadlessPaths.stateDir(stateDirOverride: stateDirFlag);
  final file = RunLedger.ledgerFile(dir);
  final records = RunLedger.tail(file, limit: tailN);
  if (asJson) {
    for (final record in records) {
      // ignore: avoid_print
      print(jsonEncode(record));
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

Future<int> _install(List<String> args) async {
  final installDir = _flagValue(args, '--install-dir');
  final wrapper = _flagValue(args, '--wrapper');
  if (installDir == null || installDir.isEmpty) {
    stderr.writeln('install: --install-dir <dir> is required.');
    return 2;
  }
  if (wrapper == null || wrapper.isEmpty) {
    stderr.writeln('install: --wrapper <path-to-mycontrolpanel-check> '
        'is required '
        '(compile via `dart compile exe bin/mycontrolpanel_check.dart`).');
    return 2;
  }
  final result = await SchedulerLifecycle.install(InstallOptions(
    installDir: installDir,
    wrapperPath: wrapper,
    taskPath: _flagValue(args, '--task-path') ?? defaultTaskPath,
    unitName: _flagValue(args, '--unit-name') ?? defaultUnitName,
    unitDirOverride: _flagValue(args, '--unit-dir'),
    installUser: _flagValue(args, '--install-user'),
    sandbox: _flagValue(args, '--sandbox'),
    noReload: _hasFlag(args, '--no-reload'),
    force: _hasFlag(args, '--force'),
    templateDir: _flagValue(args, '--template-dir'),
  ));
  // ignore: avoid_print
  print(result.toJson());
  if (!result.ok) stderr.writeln('install refused: ${result.detail}');
  return result.ok ? 0 : 1;
}

Future<int> _verify(List<String> args) async {
  final asJson = _hasFlag(args, '--json');
  final templateDir = SchedulerLifecycle.resolveTemplateDir(
      override: _flagValue(args, '--template-dir'));
  final violations = await _verifyImpl(
    templateDir: templateDir,
    sandbox: _flagValue(args, '--sandbox'),
    artifact: _flagValue(args, '--artifact'),
    taskPath: _flagValue(args, '--task-path') ?? defaultTaskPath,
    unitName: _flagValue(args, '--unit-name') ?? defaultUnitName,
    unitDirOverride: _flagValue(args, '--unit-dir'),
  );
  if (asJson) {
    // ignore: avoid_print
    print(jsonEncode({'version': 1, 'violations': violations}));
  } else if (violations.isEmpty) {
    // ignore: avoid_print
    print('verify: clean — scheduler artifact matches template invariants');
  } else {
    for (final v in violations) {
      // ignore: avoid_print
      print('verify VIOLATION: $v');
    }
  }
  return violations.isEmpty ? 0 : 1;
}

Future<List<String>> _verifyImpl({
  required Directory templateDir,
  String? sandbox,
  String? artifact,
  required String taskPath,
  required String unitName,
  String? unitDirOverride,
}) async {
  if (Platform.isWindows) {
    final xml = await _readWindowsXml(
        sandbox: sandbox, artifact: artifact, taskPath: taskPath);
    if (xml == null) {
      return [
        'windowsTaskScheduler: no installed task found (run install first)'
      ];
    }
    final violations =
        SchedulerLifecycle.verifyWindowsXml(xml: xml, taskPath: taskPath);
    try {
      final template = SchedulerLifecycle.windowsTemplate(templateDir);
      if (!SchedulerLifecycle.windowsMatchesTemplateExceptExec(
          xml, template)) {
        violations.add('windowsTaskScheduler: installed XML drifted from '
            'scripts/headless/windows/mcp-poll-task.xml outside the Exec '
            'action (reinstall from the template)');
      }
    } catch (e) {
      violations.add('windowsTaskScheduler: cannot load template: $e');
    }
    return violations;
  }
  if (Platform.isLinux) {
    final paths = _linuxUnitPaths(
        sandbox: sandbox,
        unitName: unitName,
        unitDirOverride: unitDirOverride);
    final serviceFile = File(paths.service);
    final timerFile = File(paths.timer);
    if (!serviceFile.existsSync() || !timerFile.existsSync()) {
      return ['systemdUserTimer: units not installed (run install first)'];
    }
    try {
      final timerTpl = SchedulerLifecycle.linuxTimerTemplate(templateDir);
      return SchedulerLifecycle.verifyLinuxService(
        service: serviceFile.readAsStringSync(),
        timer: timerFile.readAsStringSync(),
        timerTemplate: timerTpl,
        unitPath: serviceFile.path,
        sandbox: sandbox != null,
      );
    } catch (e) {
      return ['systemdUserTimer: cannot load template: $e'];
    }
  }
  return ['unsupported OS for verify (macOS is Elizabeth\'s rail)'];
}

Future<String?> _readWindowsXml({
  String? sandbox,
  String? artifact,
  required String taskPath,
}) async {
  if (artifact != null) {
    final file = File(artifact);
    return file.existsSync()
        ? SchedulerLifecycle.readTaskXml(file)
        : null;
  }
  if (sandbox != null) {
    final file =
        File('$sandbox${Platform.pathSeparator}mcp-poll-task.xml');
    return file.existsSync()
        ? SchedulerLifecycle.readTaskXml(file)
        : null;
  }
  try {
    final result = await Process.run(
        'schtasks', ['/Query', '/TN', taskPath, '/XML'],
        runInShell: true);
    if (result.exitCode != 0) return null;
    return result.stdout.toString();
  } catch (_) {
    return null;
  }
}

class _UnitPaths {
  const _UnitPaths(this.service, this.timer);
  final String service;
  final String timer;
}

_UnitPaths _linuxUnitPaths({
  String? sandbox,
  required String unitName,
  String? unitDirOverride,
}) {
  final sep = Platform.pathSeparator;
  if (sandbox != null) {
    return _UnitPaths(
        '$sandbox${sep}$unitName.service', '$sandbox${sep}$unitName.timer');
  }
  final dir = unitDirOverride ?? SchedulerLifecycle.defaultUnitDir().path;
  return _UnitPaths('$dir$sep$unitName.service', '$dir$sep$unitName.timer');
}

Future<int> _uninstall(List<String> args) async {
  final result = await SchedulerLifecycle.uninstall(
    taskPath: _flagValue(args, '--task-path') ?? defaultTaskPath,
    unitName: _flagValue(args, '--unit-name') ?? defaultUnitName,
    unitDirOverride: _flagValue(args, '--unit-dir'),
    sandbox: _flagValue(args, '--sandbox'),
    noReload: _hasFlag(args, '--no-reload'),
  );
  // ignore: avoid_print
  print(result.toJson());
  return result.ok ? 0 : 1;
}

Future<int> _status(List<String> args) async {
  final asJson = _hasFlag(args, '--json');
  final staleMin =
      int.tryParse(_flagValue(args, '--stale-after-min') ?? '30') ?? 30;
  final stateDirFlag = _flagValue(args, '--state-dir');
  final dir = HeadlessPaths.stateDir(stateDirOverride: stateDirFlag);
  final st = await SchedulerLifecycle.status(
    taskPath: _flagValue(args, '--task-path') ?? defaultTaskPath,
    unitName: _flagValue(args, '--unit-name') ?? defaultUnitName,
    unitDirOverride: _flagValue(args, '--unit-dir'),
    sandbox: _flagValue(args, '--sandbox'),
    stateDir: dir,
    staleAfter: Duration(minutes: staleMin),
  );
  if (asJson) {
    // ignore: avoid_print
    print(jsonEncode(st.toJson()));
    return 0;
  }
  final lastRun = st.lastRunAtMs == null
      ? 'never'
      : DateTime.fromMillisecondsSinceEpoch(st.lastRunAtMs!).toString();
  // ignore: avoid_print
  print('''scheduler: ${st.installed ? 'installed (${st.artifactDetail})' : 'not installed'} [${st.os}]
last supervised run: $lastRun — verdict: ${st.verdict.toUpperCase()}${st.missedHeartbeat ? '  (MISSED HEARTBEAT: scheduler present, no fresh run)' : ''}${st.consentHint ? '  (hint: last run skipped on consent — enable Settings → background alerts)' : ''}''');
  return 0;
}
