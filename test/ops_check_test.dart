// SPDX-License-Identifier: MIT
// TM-2 supervised-check tests (Zara): contract-JSON parsing, injected
// provider runs (ok / skipped / error / timeout / launch failure),
// ledger side-effects, secret-argv refusal.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:my_control_panel/ops/check_runner.dart';
import 'package:my_control_panel/ops/run_ledger.dart';

ProviderResult fakeOk() => const ProviderResult(
      exitCode: 0,
      stdout: '{"version":1,"status":"notified","exitCode":0,'
          '"freshTitles":["Disk 82% full on / (web)"]}',
      stderr: '',
      durationMs: 42,
    );

void main() {
  group('CheckRunner.parseTickJson', () {
    test('parses a clean contract line', () {
      final tick = CheckRunner.parseTickJson(
          '{"version":1,"status":"ok","exitCode":0}');
      expect(tick, isNotNull);
      expect(tick!.status, 'ok');
      expect(tick.exitCode, 0);
      expect(tick.freshTitles, isEmpty);
      expect(tick.reason, isNull);
    });

    test('skips harness chatter lines', () {
      final tick = CheckRunner.parseTickJson(
          'PASS  tick started\n{"version":1,"status":"skipped",'
          '"exitCode":2,"reason":"background_alerts consent OFF"}\n');
      expect(tick, isNotNull);
      expect(tick!.status, 'skipped');
      expect(tick.reason, contains('consent'));
    });

    test('rejects garbage, unknown status, and partial shapes', () {
      expect(CheckRunner.parseTickJson('not json\n'), isNull);
      expect(
          CheckRunner.parseTickJson(
              '{"version":1,"status":"frobnicated","exitCode":0}'),
          isNull);
      expect(
          CheckRunner.parseTickJson(
              '{"version":1,"status":"ok"}'),
          isNull);
      expect(
          CheckRunner.parseTickJson(
              '{"status":"ok","exitCode":0}'),
          isNull);
    });

    test('keeps fresh titles and reason', () {
      final tick = CheckRunner.parseTickJson(
          '{"version":1,"status":"notified","exitCode":0,'
          '"freshTitles":["a","b"],"reason":null}');
      expect(tick!.freshTitles, ['a', 'b']);
    });
  });

  group('CheckRunner.run with injected provider', () {
    test('ok tick exits 0 and ledgers one record', () async {
      final dir = await Directory.systemTemp.createTemp('mcp-check-ok');
      try {
        final run = await CheckRunner.run(
          tickCommand: 'fake-provider',
          runProvider: () async => fakeOk(),
          stateDir: dir,
        );
        expect(run.exitCode, 0);
        expect(run.status, 'notified');
        expect(run.freshTitles, ['Disk 82% full on / (web)']);
        expect(run.ledgerWritten, isTrue);
        final records =
            RunLedger.tail(RunLedger.ledgerFile(dir));
        expect(records.length, 1);
        expect(records.single['status'], 'notified');
        expect(records.single['provider'], 'fake-provider');
      } finally {
        await dir.delete(recursive: true);
      }
    });

    test('skipped tick passes exit 2 through with reason', () async {
      final dir =
          await Directory.systemTemp.createTemp('mcp-check-skip');
      try {
        final run = await CheckRunner.run(
          tickCommand: 'C:\\installs\\mycontrolpanel.exe',
          tickArgs: const ['--poll-headless'],
          runProvider: () async => const ProviderResult(
            exitCode: 2,
            stdout: '{"version":1,"status":"skipped","exitCode":2,'
                '"reason":"background_alerts consent OFF — skipped"}',
            stderr: '',
            durationMs: 7,
          ),
          stateDir: dir,
        );
        expect(run.exitCode, 2);
        expect(run.status, 'skipped');
        final records =
            RunLedger.tail(RunLedger.ledgerFile(dir));
        expect(records.length, 1);
        // Basename only — the full install path (with OS username)
        // must not land in the ledger.
        expect(records.single['provider'], 'mycontrolpanel.exe');
      } finally {
        await dir.delete(recursive: true);
      }
    });

    test('garbage provider output becomes an exit-1 ledger record',
        () async {
      final dir =
          await Directory.systemTemp.createTemp('mcp-check-garbage');
      try {
        final run = await CheckRunner.run(
          tickCommand: 'fake-provider',
          runProvider: () async => const ProviderResult(
            exitCode: 3,
            stdout: 'this is not json at all\n',
            stderr: '',
            durationMs: 5,
          ),
          stateDir: dir,
        );
        expect(run.exitCode, 1);
        expect(run.status, 'error');
        expect(run.reason, contains('no contract JSON'));
        expect(
            RunLedger.tail(RunLedger.ledgerFile(dir)).length, 1);
      } finally {
        await dir.delete(recursive: true);
      }
    });

    test('timed-out provider becomes an exit-1 ledger record', () async {
      final dir =
          await Directory.systemTemp.createTemp('mcp-check-timeout');
      try {
        final run = await CheckRunner.run(
          tickCommand: 'fake-provider',
          runProvider: () async => const ProviderResult(
            exitCode: 1,
            stdout: '',
            stderr: 'tick provider timed out',
            durationMs: 300000,
            timedOut: true,
          ),
          stateDir: dir,
        );
        expect(run.exitCode, 1);
        expect(run.reason, contains('timed out'));
        expect(
            RunLedger.tail(RunLedger.ledgerFile(dir)).length, 1);
      } finally {
        await dir.delete(recursive: true);
      }
    });

    test('launch failure still writes a ledger record', () async {
      final dir =
          await Directory.systemTemp.createTemp('mcp-check-launch');
      try {
        final run = await CheckRunner.run(
          tickCommand: 'fake-provider',
          runProvider: () async => throw const SocketException('x'),
          stateDir: dir,
        );
        expect(run.exitCode, 1);
        expect(run.status, 'error');
        expect(
            RunLedger.tail(RunLedger.ledgerFile(dir)).length, 1);
      } finally {
        await dir.delete(recursive: true);
      }
    });

    test('secret-bearing tick argv is refused before spawn', () async {
      final result = await CheckRunner.spawnProvider(
        'mycontrolpanel.exe',
        const ['--poll-headless', '--token=abc'],
        const Duration(seconds: 5),
      );
      expect(result.exitCode, 1);
      expect(result.stderr, contains('forbidden material'));
    });
  });

  group('fake_tick fixture integration', () {
    test('real subprocess supervise → parse → ledger', () async {
      final dir =
          await Directory.systemTemp.createTemp('mcp-check-e2e');
      try {
        final fixture = File('test/ops_support/fake_tick.dart');
        expect(fixture.existsSync(), isTrue);
        final run = await CheckRunner.run(
          tickCommand: 'dart',
          tickArgs: [fixture.absolute.path],
          stateDir: dir,
        );
        expect(run.exitCode, 0);
        expect(run.status, 'ok');
        expect(run.ledgerWritten, isTrue);
        expect(RunLedger.tail(RunLedger.ledgerFile(dir)).length, 1);
      } finally {
        await dir.delete(recursive: true);
      }
    }, timeout: const Timeout(Duration(minutes: 2)));
  });
}
