// SPDX-License-Identifier: MIT
// TM-2 ops ledger tests (Zara): record shape, append/tail round-trip,
// corrupt-line tolerance, missing-file behavior, secrecy pins.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:my_control_panel/ops/run_ledger.dart';

void main() {
  group('RunLedger.buildRecord', () {
    test('carries allowlisted fields only', () {
      final record = RunLedger.buildRecord(
        atMs: 1730600000000,
        provider: 'mycontrolpanel.exe',
        exitCode: 0,
        status: 'notified',
        durationMs: 1234,
        freshTitles: ['Disk 82% full on / (web)'],
      );
      expect(record['v'], RunLedger.recordVersion);
      expect(record['atMs'], 1730600000000);
      expect(record['provider'], 'mycontrolpanel.exe');
      expect(record['exitCode'], 0);
      expect(record['status'], 'notified');
      expect(record['durationMs'], 1234);
      expect(record['freshCount'], 1);
      expect(record['freshTitles'], ['Disk 82% full on / (web)']);
      expect(record.containsKey('reason'), isFalse);
    });

    test('truncates fresh titles to the cap', () {
      final record = RunLedger.buildRecord(
        atMs: 1,
        provider: 'p',
        exitCode: 0,
        status: 'notified',
        durationMs: 1,
        freshTitles: List.generate(9, (i) => 't$i'),
      );
      expect(record['freshCount'], 9);
      expect((record['freshTitles'] as List).length,
          RunLedger.maxFreshTitles);
    });

    test('omits empty reasons', () {
      final record = RunLedger.buildRecord(
        atMs: 1,
        provider: 'p',
        exitCode: 2,
        status: 'skipped',
        durationMs: 1,
        reason: '',
      );
      expect(record.containsKey('reason'), isFalse);
    });
  });

  group('RunLedger file round-trip', () {
    test('append then tail returns newest-last records', () async {
      final dir = await Directory.systemTemp.createTemp('mcp-ledger-rt');
      try {
        final file = RunLedger.ledgerFile(dir);
        expect(file.path.endsWith(RunLedger.fileName), isTrue);
        for (var i = 0; i < 3; i++) {
          expect(
              RunLedger.append(
                  file,
                  RunLedger.buildRecord(
                    atMs: i,
                    provider: 'p',
                    exitCode: 0,
                    status: 'ok',
                    durationMs: i,
                  )),
              isTrue);
        }
        final records = RunLedger.tail(file);
        expect(records.length, 3);
        expect(records.first['atMs'], 0);
        expect(records.last['atMs'], 2);
        expect(RunLedger.latest(file)?['atMs'], 2);
      } finally {
        await dir.delete(recursive: true);
      }
    });

    test('tail honors limit and skips corrupt lines', () async {
      final dir =
          await Directory.systemTemp.createTemp('mcp-ledger-corrupt');
      try {
        final file = RunLedger.ledgerFile(dir);
        RunLedger.append(
            file,
            RunLedger.buildRecord(
                atMs: 1,
                provider: 'p',
                exitCode: 0,
                status: 'ok',
                durationMs: 1));
        file.writeAsStringSync('{not valid json\n', mode: FileMode.append);
        file.writeAsStringSync('\n', mode: FileMode.append);
        RunLedger.append(
            file,
            RunLedger.buildRecord(
                atMs: 2,
                provider: 'p',
                exitCode: 0,
                status: 'ok',
                durationMs: 1));
        final records = RunLedger.tail(file);
        expect(records.length, 2);
        expect(RunLedger.tail(file, limit: 1).single['atMs'], 2);
      } finally {
        await dir.delete(recursive: true);
      }
    });

    test('missing file yields empty reads', () async {
      final dir =
          await Directory.systemTemp.createTemp('mcp-ledger-missing');
      try {
        final file = RunLedger.ledgerFile(dir);
        expect(RunLedger.tail(file), isEmpty);
        expect(RunLedger.latest(file), isNull);
      } finally {
        await dir.delete(recursive: true);
      }
    });

    test('ledger record never carries full provider paths', () async {
      final dir =
          await Directory.systemTemp.createTemp('mcp-ledger-path');
      try {
        final file = RunLedger.ledgerFile(dir);
        // check_runner labels providers by basename; the ledger layer
        // pins the invariant from its side: whatever label it is given
        // must not smuggle vault/token fragments into the file.
        RunLedger.append(
            file,
            RunLedger.buildRecord(
              atMs: 1,
              provider: 'mycontrolpanel.exe',
              exitCode: 0,
              status: 'ok',
              durationMs: 1,
              reason: 'background_alerts consent OFF — skipped',
            ));
        final raw = file.readAsStringSync();
        for (final frag in [
          'secure:',
          'srv_cred_',
          'agent_tok_',
          '.pem',
          'BEGIN PRIVATE KEY',
          'C:\\Users\\',
          '/home/',
        ]) {
          expect(raw.contains(frag), isFalse,
              reason: 'ledger leaked $frag');
        }
      } finally {
        await dir.delete(recursive: true);
      }
    });
  });
}
