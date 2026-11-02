// SPDX-License-Identifier: MIT
/// `agent_check` — headless-agent operability entry-point (Beta.2, Nadia).
///
/// Two modes (exact argv, schedulers must not add flags):
///   `dart run my_control_panel:agent_check --check --json [--log <path>]`
///       Evaluate the JSONL delivery log against the frozen SLOs and print
///       ONE JSON line ([AgentCheckReport]): exit 0 healthy, 1 breach,
///       2 no data / usage error.
///   `dart run my_control_panel:agent_check --rotate [--log <path>]`
///       Rotate generations per [AlertLogRotation] (512 KiB cap, keep
///       base + .1 + .2, prune older). Prints the plan as JSON. Exit 0.
///
/// Pure Dart only (`dart:io` + pure lib modules) — it MUST stay runnable
/// under `dart run`. Never import Flutter or plugins here. Reads the
/// delivery log the instrumented tick appends; never credentials,
/// markers, or paths beyond the log path itself.
library;

import 'dart:convert';
import 'dart:io';

import 'package:my_control_panel/services/agent_operability.dart';
import 'package:my_control_panel/services/alert_log_rotation.dart';

Future<void> main(List<String> args) async {
  if (args.contains('--help') || args.contains('-h')) {
    _usage();
    return;
  }
  if (args.contains('--rotate')) {
    exitCode = await _rotate(args);
    return;
  }
  if (args.contains('--check')) {
    exitCode = await _check(args);
    return;
  }
  stderr.writeln('agent_check: nothing to do (pass --check or --rotate).');
  _usage();
  exitCode = AgentCheckExit.skipped;
}

void _usage() {
  // ignore: avoid_print
  print('''agent_check — headless-agent operability check (Nadia).

Usage:
  dart run my_control_panel:agent_check --check --json [--log <path>]
  dart run my_control_panel:agent_check --rotate [--log <path>]

Modes:
  --check --json   Evaluate the delivery log against the frozen SLOs,
                   print ONE JSON report line. Exit 0 healthy, 1 breach,
                   2 no data. --json is required (bare --check exits 2).
  --rotate         Rotate log generations per policy (512 KiB cap, keep
                   base + .1 + .2). Prints the plan as JSON. Exit 0.
  --help           This text.

Exit codes mirror the headless TM-1 contract: 0 ok, 2 skipped, 1 error.''');
}

String _flagValue(List<String> args, String flag) {
  final i = args.indexOf(flag);
  if (i < 0 || i + 1 >= args.length) return '';
  return args[i + 1];
}

/// Default log location next to the headless state dir convention:
/// per-user app-data dir, overridable with --log (tests/CI).
String _defaultLogPath() {
  final override = Platform.environment['MCP_DELIVERY_LOG'];
  if (override != null && override.isNotEmpty) return override;
  if (Platform.isWindows) {
    final base = Platform.environment['LOCALAPPDATA'];
    if (base != null) return '$base\\MyControlPanel\\delivery.log';
  } else if (Platform.isMacOS) {
    final home = Platform.environment['HOME'];
    if (home != null) {
      return '$home/Library/Application Support/MyControlPanel/delivery.log';
    }
  } else {
    final xdg = Platform.environment['XDG_CONFIG_HOME'];
    final home = Platform.environment['HOME'];
    if (xdg != null && xdg.isNotEmpty) return '$xdg/mycontrolpanel/delivery.log';
    if (home != null) return '$home/.config/mycontrolpanel/delivery.log';
  }
  return 'delivery.log';
}

Future<int> _check(List<String> args) async {
  if (!args.contains('--json')) {
    stderr.writeln('agent_check --check requires --json.');
    return AgentCheckExit.skipped;
  }
  final logOpt = _flagValue(args, '--log');
  final base = logOpt.isEmpty ? _defaultLogPath() : logOpt;
  final nowMs = DateTime.now().millisecondsSinceEpoch;
  final lines = <String>[];
  var bytes = 0;
  for (final path in AlertLogRotation.livePaths(base)) {
    final file = File(path);
    if (!await file.exists()) continue;
    try {
      bytes += await file.length();
      lines.addAll(await file.readAsLines());
    } catch (_) {
      // Unreadable generation: skip, never sink the whole check.
    }
  }
  final report = buildCheckReport(
    log: parseLogLines(lines),
    nowMs: nowMs,
    logPath: base,
    logBytes: bytes,
  );
  // ignore: avoid_print
  print(jsonEncode(report.toJson()));
  return report.exitCode;
}

Future<int> _rotate(List<String> args) async {
  final logOpt = _flagValue(args, '--log');
  final base = logOpt.isEmpty ? _defaultLogPath() : logOpt;
  final actions = <String>[];
  final live = File(base);
  var liveBytes = 0;
  try {
    if (await live.exists()) liveBytes = await live.length();
  } catch (_) {}
  if (liveBytes > 0 && AlertLogRotation.rotationDue(liveBytes)) {
    try {
      final oldest =
          File(AlertLogRotation.generationPath(base, AlertLogRotation.generations));
      if (await oldest.exists()) {
        await oldest.delete();
        actions.add('pruned ${oldest.path}');
      }
      for (var gen = AlertLogRotation.generations - 1; gen >= 1; gen--) {
        final src = File(AlertLogRotation.generationPath(base, gen));
        if (await src.exists()) {
          await src.rename(
              AlertLogRotation.generationPath(base, gen + 1));
          actions.add('promoted ${src.path} -> gen ${gen + 1}');
        }
      }
      await live.rename(AlertLogRotation.generationPath(base, 1));
      actions.add('rotated live log -> gen 1');
      await live.create(recursive: true);
    } catch (e) {
      stderr.writeln('agent_check --rotate failed: $e');
      return AgentCheckExit.error;
    }
  } else {
    actions.add('no rotation due ($liveBytes bytes)');
  }
  // ignore: avoid_print
  print(jsonEncode({
    'version': 1,
    'tool': 'agent_check',
    'mode': 'rotate',
    'log': base,
    'liveBytes': liveBytes,
    'rotationDue': AlertLogRotation.rotationDue(liveBytes),
    'actions': actions,
  }));
  return AgentCheckExit.ok;
}
