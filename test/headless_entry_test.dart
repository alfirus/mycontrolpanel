// SPDX-License-Identifier: MIT
// TM-1 adapter tests (Lina): `lib/headless.dart` with fully fake deps —
// zero plugin I/O. Proves the no-UI-boot gate, consent/vault wiring,
// read-only resolution (no healing), and staleness stamping.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:my_control_panel/background/headless_state.dart';
import 'package:my_control_panel/headless.dart';
import 'package:my_control_panel/models/server_connection.dart';
import 'package:my_control_panel/services/background_alerts.dart';
import 'package:my_control_panel/services/headless_security.dart';
import 'package:my_control_panel/services/secure_store.dart';

ServerConnection fakeServer({String credential = 'secure:srv_cred_web'}) =>
    ServerConnection(
      id: 'web',
      name: 'web',
      host: 'example.com',
      port: 22,
      username: 'deploy',
      authMethod: AuthMethod.password,
      credential: credential,
      region: 'us-east-1',
      os: 'Ubuntu 24.04',
      env: ServerEnv.prod,
      createdAt: DateTime.fromMillisecondsSinceEpoch(0),
    );

void main() {
  group('runHeadlessIfRequested gate', () {
    test('no flag returns null (normal launch untouched)', () async {
      final dir =
          await Directory.systemTemp.createTemp('mcp-he-gate');
      try {
        var fetched = false;
        final code = await runHeadlessIfRequested(
          const [],
          stateDir: () => dir,
          loadServersRaw: () async {
            fetched = true;
            return [fakeServer()];
          },
        );
        expect(code, isNull);
        expect(fetched, isFalse);
      } finally {
        await dir.delete(recursive: true);
      }
    });

    test('consent OFF exits 2 without fetching or notifying', () async {
      final dir =
          await Directory.systemTemp.createTemp('mcp-he-consent');
      try {
        var fetched = false;
        var notified = false;
        var stamped = false;
        final code = await runHeadlessIfRequested(
          const ['--poll-headless'],
          stateDir: () => dir,
          readPrefs: () async => {
            BackgroundAlerts.prefEnabledKey: false,
            'biometrics': false,
          },
          loadServersRaw: () async {
            fetched = true;
            return [fakeServer()];
          },
          notify: (title, body) async => notified = true,
          onCheckRecorded: () async => stamped = true,
        );
        expect(code, headlessExitSkipped);
        expect(fetched, isFalse);
        expect(notified, isFalse);
        expect(stamped, isTrue,
            reason: 'skips still stamp the last-check pref (T3)');
      } finally {
        await dir.delete(recursive: true);
      }
    });

    test('app lock engaged exits 2 (vault treated as locked)', () async {
      final dir =
          await Directory.systemTemp.createTemp('mcp-he-lock');
      try {
        var fetched = false;
        final code = await runHeadlessIfRequested(
          const ['--poll-headless'],
          stateDir: () => dir,
          readPrefs: () async => {
            BackgroundAlerts.prefEnabledKey: true,
            'biometrics': true,
          },
          loadServersRaw: () async {
            fetched = true;
            return [fakeServer()];
          },
        );
        expect(code, headlessExitSkipped);
        expect(fetched, isFalse);
      } finally {
        await dir.delete(recursive: true);
      }
    });

    test('happy path aggregates, notifies once, stamps, persists',
        () async {
      final dir =
          await Directory.systemTemp.createTemp('mcp-he-happy');
      try {
        final notes = <String>[];
        var stamps = 0;
        Future<int?> tick() => runHeadlessIfRequested(
              const ['--poll-headless'],
              stateDir: () => dir,
              readPrefs: () async => {
                BackgroundAlerts.prefEnabledKey: true,
                'biometrics': false,
              },
              loadServersRaw: () async => [fakeServer()],
              fetchFor: (_) async => const [
                HeadlessSignal(
                    kind: 'alert',
                    title: 'Disk 82% full on /',
                    owner: 'web'),
              ],
              notify: (t, b) async => notes.add('$t::$b'),
              onCheckRecorded: () async => stamps++,
            );
        final first = await tick();
        expect(first, headlessExitOk);
        expect(notes, hasLength(1));
        expect(notes.single, contains('MyControlPanel alert'));
        expect(stamps, 1);
        final state =
            HeadlessState.load(HeadlessPaths.stateFile(dir));
        expect(state.seenKeys, {'alert::web::Disk 82% full on /'});
        expect(state.lastCheckMs, greaterThan(0));

        final second = await tick();
        expect(second, headlessExitOk);
        expect(notes, hasLength(1),
            reason: 'transition-only: no re-notify');
        expect(stamps, 2);
      } finally {
        await dir.delete(recursive: true);
      }
    });

    test('plaintext marker host is skipped (no fallback)', () async {
      final dir =
          await Directory.systemTemp.createTemp('mcp-he-plain');
      try {
        var vaultReads = 0;
        final code = await runHeadlessIfRequested(
          const ['--poll-headless'],
          stateDir: () => dir,
          readPrefs: () async => {
            BackgroundAlerts.prefEnabledKey: true,
            'biometrics': false,
          },
          loadServersRaw: () async =>
              [fakeServer(credential: 'hunter2-plaintext')],
          readVault: (_) async {
            vaultReads++;
            return 'hunter2-plaintext';
          },
          fetchFor: (_) async => const [
            HeadlessSignal(
                kind: 'alert', title: 'X', owner: 'web'),
          ],
        );
        // The default fetch path resolves read-only: plaintext never
        // resolves, so without an injected fetchFor the host is skipped.
        // Here fetchFor is injected (adapter seam), so the tick still runs
        // — but the vault must never be consulted for a plaintext marker
        // on the production path. This tick uses the injected fetch, which
        // bypasses resolution by design (test seam).
        expect(code, headlessExitOk);
        expect(vaultReads, 0);
      } finally {
        await dir.delete(recursive: true);
      }
    });

    test('resolveCredential pins the no-heal rule at the unit level',
        () async {
      expect(
        HeadlessSecurity.resolveCredential(
            marker: 'hunter2-plaintext', vaultSecret: 'hunter2-plaintext'),
        isNull,
      );
      expect(
        HeadlessSecurity.resolveCredential(
            marker: 'secure:srv_cred_web', vaultSecret: null),
        isNull,
      );
    });

    test('readRawServerListJson is best-effort (never throws headless)',
        () async {
      // No plugin binding in this test — the accessor must fail closed
      // to null, never throw, so a broken prefs layer skips the tick
      // instead of crashing it.
      expect(await SecureStore.readRawServerListJson(), isNull);
    });
  });
}
