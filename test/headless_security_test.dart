import 'package:flutter_test/flutter_test.dart';
import 'package:my_control_panel/services/headless_security.dart';

void main() {
  group('HeadlessSecurity.evaluateHeadlessTick (consent + vault gate)', () {
    test('consent ON + vault unlocked proceeds', () {
      final d = HeadlessSecurity.evaluateHeadlessTick(
        consentEnabled: true,
        vaultUnlocked: true,
      );
      expect(d.proceed, isTrue);
      expect(d.exitCode, headlessExitOk);
    });

    test('consent OFF denies even with an unlocked vault (exit 2)', () {
      final d = HeadlessSecurity.evaluateHeadlessTick(
        consentEnabled: false,
        vaultUnlocked: true,
      );
      expect(d.proceed, isFalse);
      expect(d.gate, HeadlessTickGate.skipConsentOff);
      expect(d.exitCode, headlessExitSkipped);
    });

    test('locked vault denies background reads even with consent ON', () {
      // Locked-vault-denies: headless tick must fail closed, exit 2,
      // never prompt for biometrics without a UI.
      final d = HeadlessSecurity.evaluateHeadlessTick(
        consentEnabled: true,
        vaultUnlocked: false,
      );
      expect(d.proceed, isFalse);
      expect(d.gate, HeadlessTickGate.skipVaultLocked);
      expect(d.exitCode, headlessExitSkipped);
      expect(d.reason, contains('denied'));
    });

    test('consent OFF wins over locked vault (audit clarity)', () {
      final d = HeadlessSecurity.evaluateHeadlessTick(
        consentEnabled: false,
        vaultUnlocked: false,
      );
      expect(d.gate, HeadlessTickGate.skipConsentOff);
      expect(d.exitCode, headlessExitSkipped);
    });
  });

  group('HeadlessSecurity.resolveCredential (no plaintext fallback)', () {
    test('secure marker + vault secret resolves', () {
      expect(
        HeadlessSecurity.resolveCredential(
          marker: 'secure:srv_cred_abc',
          vaultSecret: 's3cr3t',
        ),
        's3cr3t',
      );
    });

    test('legacy plaintext marker never resolves, even with a secret', () {
      // No-plaintext-fallback: raw prefs material must not reach the
      // headless poller — healing is interactive-only.
      expect(
        HeadlessSecurity.resolveCredential(
          marker: 'hunter2-plaintext',
          vaultSecret: 'hunter2-plaintext',
        ),
        isNull,
      );
    });

    test('empty marker resolves to null (force re-entry)', () {
      expect(
        HeadlessSecurity.resolveCredential(marker: '', vaultSecret: 'x'),
        isNull,
      );
    });

    test('locked vault (null secret) denies the host', () {
      expect(
        HeadlessSecurity.resolveCredential(
          marker: 'secure:srv_cred_abc',
          vaultSecret: null,
        ),
        isNull,
      );
    });

    test('empty vault secret denies the host', () {
      expect(
        HeadlessSecurity.resolveCredential(
          marker: 'secure:srv_cred_abc',
          vaultSecret: '',
        ),
        isNull,
      );
    });
  });

  group('HeadlessSecurity scheduler argv (tampered-artifact detection)', () {
    test('clean headless argv passes', () {
      expect(
        HeadlessSecurity.findSecretMaterialInArgs(
            [headlessFlag, '--interval-minutes', '15']),
        isEmpty,
      );
    });

    test('token flag in argv is a violation', () {
      final v = HeadlessSecurity.findSecretMaterialInArgs(
          [headlessFlag, '--token=abc123']);
      expect(v, isNotEmpty);
    });

    test('key name / key path in argv is a violation', () {
      expect(
        HeadlessSecurity.findSecretMaterialInArgs(
            [headlessFlag, 'secure:srv_cred_abc']),
        isNotEmpty,
      );
      expect(
        HeadlessSecurity.findSecretMaterialInArgs(
            [headlessFlag, '--key-file=/home/u/.ssh/id_rsa']),
        isNotEmpty,
      );
    });

    test('passphrase and private-key material in argv are violations', () {
      expect(
        HeadlessSecurity.findSecretMaterialInArgs(
            [headlessFlag, '--passphrase=hunter2']),
        isNotEmpty,
      );
      expect(
        HeadlessSecurity.findSecretMaterialInArgs(
            ['-----BEGIN OPENSSH PRIVATE KEY-----']),
        isNotEmpty,
      );
    });

    test('validateSchedulerArtifact: least-privilege reference is clean', () {
      expect(
        HeadlessSecurity.validateSchedulerArtifact(
          kind: SchedulerKind.systemdUserTimer,
          perUserScope: true,
          runsElevated: false,
          args: const [headlessFlag],
          invokesHeadlessFlag: true,
        ),
        isEmpty,
      );
    });

    test('validateSchedulerArtifact: tampered artifact is rejected', () {
      // System scope + elevated + wrong entry-point + secret in argv:
      // every hardening rule must fire, not just the first.
      final v = HeadlessSecurity.validateSchedulerArtifact(
        kind: SchedulerKind.windowsTaskScheduler,
        perUserScope: false,
        runsElevated: true,
        args: const ['--poll-headless', '--token=abc123'],
        invokesHeadlessFlag: false,
      );
      expect(v.length, greaterThanOrEqualTo(3));
      expect(v.any((e) => e.contains('per-user')), isTrue);
      expect(v.any((e) => e.contains('elevated')), isTrue);
      expect(v.any((e) => e.contains('tampered')), isTrue);
      expect(v.any((e) => e.contains('forbidden material')), isTrue);
    });
  });

  group('headless contract constants', () {
    test('exit codes match the TM-1 contract (0 ok / 1 error / 2 skip)', () {
      expect(headlessExitOk, 0);
      expect(headlessExitError, 1);
      expect(headlessExitSkipped, 2);
    });

    test('storage notes cover all three scheduler kinds', () {
      expect(
        HeadlessSecurity.artifactStorageNotes.keys.toSet(),
        SchedulerKind.values.toSet(),
      );
    });
  });
}
