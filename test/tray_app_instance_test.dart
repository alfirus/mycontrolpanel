// SPDX-License-Identifier: MIT
// Single-instance guard tests (Elizabeth): one live owner per state dir,
// second launch signals + exits, restore callback fires, no stale wedge.
import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:my_control_panel/tray/app_instance.dart';

void main() {
  group('AppInstanceGuard', () {
    test('first launch is primary', () async {
      final dir =
          await Directory.systemTemp.createTemp('mcp-inst-1');
      try {
        final (outcome, guard) =
            await AppInstanceGuard.tryAcquire(directory: dir);
        expect(outcome, AppInstanceOutcome.primary);
        expect(guard, isNotNull);
        await guard!.release();
      } finally {
        await dir.delete(recursive: true);
      }
    });

    test('second launch signals the primary and exits', () async {
      final dir =
          await Directory.systemTemp.createTemp('mcp-inst-2');
      try {
        var restored = false;
        final completer = Completer<void>();
        final (first, guard) =
            await AppInstanceGuard.tryAcquire(
          directory: dir,
          onRestoreRequested: () {
            restored = true;
            if (!completer.isCompleted) completer.complete();
          },
        );
        expect(first, AppInstanceOutcome.primary);

        final (second, guard2) =
            await AppInstanceGuard.tryAcquire(directory: dir);
        expect(second, AppInstanceOutcome.secondarySignaled);
        expect(guard2, isNull);

        await completer.future.timeout(const Duration(seconds: 5));
        expect(restored, isTrue);
        await guard!.release();
      } finally {
        await dir.delete(recursive: true);
      }
    });

    test('released guard can be re-acquired (no stale wedge)', () async {
      final dir =
          await Directory.systemTemp.createTemp('mcp-inst-3');
      try {
        final (first, guard) =
            await AppInstanceGuard.tryAcquire(directory: dir);
        expect(first, AppInstanceOutcome.primary);
        await guard!.release();
        final (second, guard2) =
            await AppInstanceGuard.tryAcquire(directory: dir);
        expect(second, AppInstanceOutcome.primary);
        await guard2!.release();
      } finally {
        await dir.delete(recursive: true);
      }
    });
  });
}
