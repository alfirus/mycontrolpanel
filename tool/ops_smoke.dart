// SPDX-License-Identifier: MIT
/// Ops smoke driver (TM-2, Zara owns): install → fire twice → assert
/// payload + ledger → status → verify → uninstall, against a sandbox
/// scheduler artifact (no live OS scheduler touched) and the fake tick
/// fixture. Stdlib-only (`dart:io` / `dart:convert`); run as
/// `dart tool/ops_smoke.dart --wrapper <exe> --sandbox <dir>
/// --state-dir <dir> [--install-dir <dir>]`.
///
/// Steps print `PASS <label>` / `FAIL <label> (detail)`; exit 0 only
/// when every assertion holds. CI (`.github/workflows/ops-smoke.yml`)
/// runs this on Windows + Linux after compiling the wrapper.
library;

import 'dart:convert';
import 'dart:io';

int _failures = 0;

void _check(bool cond, String label, [Object? detail]) {
  if (cond) {
    // ignore: avoid_print
    print('PASS  $label');
  } else {
    _failures++;
    // ignore: avoid_print
    print('FAIL  $label${detail == null ? '' : '  ($detail)'}');
  }
}

String? _flag(List<String> args, String name) {
  final idx = args.indexOf(name);
  if (idx >= 0 && idx + 1 < args.length) return args[idx + 1];
  return null;
}

Future<ProcessResult> _run(
    String exe, List<String> args, Map<String, String>? env) {
  return Process.run(exe, args,
      runInShell: Platform.isWindows, environment: env);
}

Future<void> main(List<String> args) async {
  final wrapper = _flag(args, '--wrapper');
  final sandbox = _flag(args, '--sandbox');
  final stateDir = _flag(args, '--state-dir');
  final installDir =
      _flag(args, '--install-dir') ?? Directory.current.path;
  if (wrapper == null || sandbox == null || stateDir == null) {
    stderr.writeln(
        'usage: dart tool/ops_smoke.dart --wrapper <exe> '
        '--sandbox <dir> --state-dir <dir> [--install-dir <dir>]');
    exit(2);
  }

  // 1. Consent-gated install into the sandbox (--force: CI has no real
  // app binary for the preflight tick; the gate itself is unit-tested).
  var r = await _run(wrapper, [
    'install',
    '--install-dir',
    installDir,
    '--wrapper',
    wrapper,
    '--sandbox',
    sandbox,
    '--force',
    '--no-reload',
  ], null);
  _check(r.exitCode == 0, 'install into sandbox',
      r.exitCode == 0 ? null : '${r.stdout}${r.stderr}');

  // 2. Verify the sandboxed artifact.
  r = await _run(wrapper, ['verify', '--sandbox', sandbox], null);
  _check(r.exitCode == 0, 'verify clean after install',
      r.exitCode == 0 ? null : '${r.stdout}${r.stderr}');

  // 3. Fire twice via the fake tick (ok, then notified).
  Map<String, dynamic>? first;
  r = await _run(wrapper, [
    'check',
    '--tick-cmd',
    'dart',
    '--tick-arg',
    'test/ops_support/fake_tick.dart',
    '--state-dir',
    stateDir,
  ], null);
  try {
    first = jsonDecode(r.stdout.toString().trim()) as Map<String, dynamic>;
  } catch (_) {
    first = null;
  }
  _check(r.exitCode == 0 && first?['status'] == 'ok',
      'first fire: ok payload',
      'exit=${r.exitCode} out=${r.stdout} err=${r.stderr}');

  Map<String, dynamic>? second;
  r = await _run(wrapper, [
    'check',
    '--tick-cmd',
    'dart',
    '--tick-arg',
    'test/ops_support/fake_tick.dart',
    '--state-dir',
    stateDir,
  ], {
    ...Platform.environment,
    'FAKE_TICK_STATUS': 'notified',
    'FAKE_TICK_FRESH': 'Disk 82% full on /',
  });
  try {
    second = jsonDecode(r.stdout.toString().trim()) as Map<String, dynamic>;
  } catch (_) {
    second = null;
  }
  _check(
      r.exitCode == 0 &&
          second?['status'] == 'notified' &&
          (second?['freshTitles'] as List?)?.isNotEmpty == true,
      'second fire: notified payload with titles',
      'exit=${r.exitCode} out=${r.stdout} err=${r.stderr}');

  // 4. Ledger holds exactly the two supervised runs.
  final ledger = File('$stateDir${Platform.pathSeparator}'
      'headless_runs.jsonl');
  var records = <Map<String, dynamic>>[];
  try {
    records = const LineSplitter()
        .convert(ledger.readAsStringSync())
        .where((l) => l.trim().isNotEmpty)
        .map((l) => jsonDecode(l) as Map<String, dynamic>)
        .toList();
  } catch (_) {}
  _check(
      records.length == 2 &&
          records.every((m) => m['v'] == 1) &&
          records.last['status'] == 'notified',
      'ledger holds both runs',
      'records=${records.length}');

  // 5. Status: installed + fresh, no missed heartbeat.
  r = await _run(wrapper, [
    'status',
    '--json',
    '--sandbox',
    sandbox,
    '--state-dir',
    stateDir,
  ], null);
  Map<String, dynamic>? st;
  try {
    st = jsonDecode(r.stdout.toString().trim()) as Map<String, dynamic>;
  } catch (_) {
    st = null;
  }
  _check(
      st?['installed'] == true &&
          st?['verdict'] == 'fresh' &&
          st?['missedHeartbeat'] == false,
      'status fresh, heartbeat ok',
      'out=${r.stdout}');

  // 6. Uninstall → status flips, verify fails closed.
  r = await _run(wrapper, [
    'uninstall',
    '--sandbox',
    sandbox,
    '--no-reload',
  ], null);
  _check(r.exitCode == 0, 'uninstall removes sandbox artifact',
      r.exitCode == 0 ? null : '${r.stdout}${r.stderr}');
  r = await _run(wrapper, [
    'status',
    '--json',
    '--sandbox',
    sandbox,
    '--state-dir',
    stateDir,
  ], null);
  try {
    st = jsonDecode(r.stdout.toString().trim()) as Map<String, dynamic>;
  } catch (_) {
    st = null;
  }
  _check(st?['installed'] == false, 'status shows uninstalled',
      'out=${r.stdout}');
  r = await _run(wrapper, ['verify', '--sandbox', sandbox], null);
  _check(r.exitCode != 0, 'verify fails closed after uninstall',
      'exit=${r.exitCode}');

  if (_failures > 0) {
    // ignore: avoid_print
    print('OPS SMOKE FAILED ($_failures)');
    exit(1);
  }
  // ignore: avoid_print
  print('OPS SMOKE GREEN');
}
