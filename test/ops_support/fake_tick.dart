// SPDX-License-Identifier: MIT
/// Fake tick provider for ops tests + CI smoke (Zara).
///
/// Prints one contract-shaped JSON line controlled by env, so
/// `mycontrolpanel-check check --tick-cmd dart --tick-arg <this file>`
/// exercises the full supervise → parse → ledger path without the app.
///
/// Env:
///   FAKE_TICK_STATUS  ok | notified | skipped | error (default ok)
///   FAKE_TICK_EXIT    numeric exit code (default per status: 0/0/2/1)
///   FAKE_TICK_REASON  reason string (default: set for skipped/error)
///   FAKE_TICK_FRESH   comma-separated fresh titles (default: none)
///   FAKE_TICK_CHATTER on = print harness-style noise lines first
///   FAKE_TICK_GARBAGE on = print non-JSON only (parse-failure path)
///   FAKE_TICK_SLEEP_MS    sleep before printing (timeout path)
///
/// Pure Dart only — runnable via `dart <file>` with no packages.
library;

import 'dart:convert';
import 'dart:io';

Future<void> main() async {
  final env = Platform.environment;
  final sleepMs = int.tryParse(env['FAKE_TICK_SLEEP_MS'] ?? '0') ?? 0;
  if (sleepMs > 0) {
    await Future<void>.delayed(Duration(milliseconds: sleepMs));
  }
  if ((env['FAKE_TICK_GARBAGE'] ?? '') == 'on') {
    // ignore: avoid_print
    print('this is not json at all');
    // ignore: avoid_print
    print('neither is this');
    exit(3);
  }
  if ((env['FAKE_TICK_CHATTER'] ?? '') == 'on') {
    // ignore: avoid_print
    print('PASS  tick started');
  }
  final status = env['FAKE_TICK_STATUS'] ?? 'ok';
  final defaultExit = switch (status) {
    'skipped' => 2,
    'error' => 1,
    _ => 0,
  };
  final code =
      int.tryParse(env['FAKE_TICK_EXIT'] ?? '$defaultExit') ?? defaultExit;
  final freshRaw = env['FAKE_TICK_FRESH'] ?? '';
  final fresh = freshRaw.isEmpty
      ? <String>[]
      : freshRaw.split(',').map((s) => s.trim()).toList();
  final reason = env['FAKE_TICK_REASON'] ??
      (status == 'skipped'
          ? 'background_alerts consent OFF — headless tick skipped'
          : status == 'error'
              ? 'tick provider exploded (fake)'
              : null);
  final payload = {
    'version': 1,
    'status': status,
    'exitCode': code,
    if (fresh.isNotEmpty) 'freshTitles': fresh,
    // ignore: use_null_aware_elements
    if (reason != null) 'reason': reason,
  };
  // ignore: avoid_print
  print(jsonEncode(payload));
  exitCode = code;
}
