// SPDX-License-Identifier: MIT
// TM-1 headless state tests (Lina): persistence round-trip, corrupt-file
// defaults, single-flight lock, per-user paths, AlertWatch key parity.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:my_control_panel/background/headless_state.dart';
import 'package:my_control_panel/services/alert_watch.dart';

void main() {
  group('HeadlessState persistence', () {
    test('round-trips through JSON', () async {
      final dir =
          await Directory.systemTemp.createTemp('mcp-hs-roundtrip');
      try {
        final file = HeadlessPaths.stateFile(dir);
        final state = HeadlessState(
          lastCheckMs: 123456789,
          seenKeys: {'alert::web::Disk 80% full on /'},
          lastSentMs: {'alert::web::Disk 80% full on /': 123456789},
          consecutiveFailures: 2,
        );
        state.save(file);
        final loaded = HeadlessState.load(file);
        expect(loaded.version, HeadlessCheckStateVersion.current);
        expect(loaded.lastCheckMs, 123456789);
        expect(loaded.seenKeys,
            {'alert::web::Disk 80% full on /'});
        expect(loaded.lastSentMs,
            {'alert::web::Disk 80% full on /': 123456789});
        expect(loaded.consecutiveFailures, 2);
      } finally {
        await dir.delete(recursive: true);
      }
    });

    test('missing file yields defaults', () async {
      final dir =
          await Directory.systemTemp.createTemp('mcp-hs-missing');
      try {
        final loaded =
            HeadlessState.load(HeadlessPaths.stateFile(dir));
        expect(loaded.lastCheckMs, 0);
        expect(loaded.seenKeys, isEmpty);
        expect(loaded.consecutiveFailures, 0);
      } finally {
        await dir.delete(recursive: true);
      }
    });

    test('corrupt file yields defaults (never throws)', () async {
      final dir =
          await Directory.systemTemp.createTemp('mcp-hs-corrupt');
      try {
        final file = HeadlessPaths.stateFile(dir);
        await file.parent.create(recursive: true);
        await file.writeAsString('not-json{{{');
        expect(HeadlessState.load(file).lastCheckMs, 0);
        await file.writeAsString('["a","list","not","a","map"]');
        expect(HeadlessState.load(file).seenKeys, isEmpty);
      } finally {
        await dir.delete(recursive: true);
      }
    });
  });

  group('HeadlessLock single-flight', () {
    test('second acquire denied while held', () async {
      final dir =
          await Directory.systemTemp.createTemp('mcp-hs-lock');
      try {
        final lockFile = HeadlessPaths.lockFile(dir);
        final first = await HeadlessLock.tryAcquire(lockFile);
        expect(first, isNotNull);
        final second = await HeadlessLock.tryAcquire(
          lockFile,
          timeout: const Duration(milliseconds: 200),
        );
        expect(second, isNull,
            reason: 'overlapping scheduler ticks must skip, never overlap');
        await first!.release();
        final third = await HeadlessLock.tryAcquire(lockFile);
        expect(third, isNotNull,
            reason: 'lock is reusable after release');
        await third!.release();
      } finally {
        // Best-effort cleanup: Windows may briefly hold the lock file
        // after release — temp-dir residue must never fail the test.
        try {
          await dir.delete(recursive: true);
        } catch (_) {}
      }
    });
  });

  group('HeadlessPaths per-user scope (ADR-003)', () {
    test('env override wins (CI/test hook)', () {
      final dir = HeadlessPaths.stateDir(
        environment: {'MCP_STATE_DIR': '/tmp/mcp-test-state'},
        isWindowsOverride: false,
      );
      expect(dir.path, '/tmp/mcp-test-state');
    });

    test('windows default lives under LOCALAPPDATA', () {
      final dir = HeadlessPaths.stateDir(
        environment: {'LOCALAPPDATA': 'C:\\Users\\t\\AppData\\Local'},
        isWindowsOverride: true,
      );
      expect(dir.path, contains('MyControlPanel'));
      expect(dir.path, contains('AppData'));
    });

    test('linux default lives under the user config home', () {
      final dir = HeadlessPaths.stateDir(
        environment: {'HOME': '/home/t'},
        isWindowsOverride: false,
      );
      expect(dir.path, contains('/home/t'));
    });
  });

  group('dedup identity parity with AlertWatch', () {
    test('HeadlessKeys.keyFor == AlertWatch.keyFor', () {
      expect(HeadlessKeys.keyFor('alert', 'Disk 80% full on /', 'web'),
          AlertWatch.keyFor('alert', 'Disk 80% full on /', 'web'));
      expect(HeadlessKeys.keyFor('ci', 'shop 1.2.3', 'prod'),
          AlertWatch.keyFor('ci', 'shop 1.2.3', 'prod'));
    });

    test('HeadlessSignal display titles match AlertWatch.freshTitles', () {
      const alert = HeadlessSignal(
          kind: 'alert', title: 'Disk 80% full on /', owner: 'web');
      expect(alert.key, 'alert::web::Disk 80% full on /');
      expect(alert.displayTitle, 'Disk 80% full on / (web)');
      const ci =
          HeadlessSignal(kind: 'ci', title: 'shop 1.2.3', owner: 'prod');
      expect(ci.key, 'ci::prod::shop 1.2.3');
      expect(ci.displayTitle, 'CI failed: shop 1.2.3');
    });
  });
}
