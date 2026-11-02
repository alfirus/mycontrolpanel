// SPDX-License-Identifier: MIT
/// Tray-mode headless security boundary (Beta.2, ADR-003).
///
/// Pure-Dart policy gate for the `--poll-headless` tick and its OS
/// scheduler artifacts. No plugins, no I/O here — callers wire
/// [BackgroundAlerts.isEnabled], [SecureStore.readSecret], and the
/// platform scheduler to these pure decisions so the whole boundary
/// stays unit-testable.
///
/// Guardrails (binding, see `docs/decisions/003-tray-headless-security.md`):
/// - Read-only vault access from the headless tick: never write, migrate,
///   or heal secrets headless (healing is an interactive-session job).
/// - Biometric-gated vault: when the app lock is engaged the OS vault is
///   treated as locked and background reads are denied (fail closed).
/// - No plaintext fallback: a non-`secure:` credential marker resolves to
///   "no credential", never to the raw prefs string.
/// - OS-ACL-scoped storage: prefs + scheduler artifacts live in per-user
///   locations only (see [artifactStorageNotes]).
/// - Locked-vault denies background reads: a null/empty vault secret skips
///   the host (exit 2 path), never retries hot, never prompts headless.
/// - Least-privilege scheduler artifacts: per-user scope, no elevation,
///   args carry no token, key name, key path, or passphrase.
/// - Consent honored headless: the shared `background_alerts` pref
///   (default OFF) gates every headless tick — no second pref.
library;

/// CLI flag for the headless poll entry-point (TM-1 contract, Lina owns).
const headlessFlag = '--poll-headless';

/// Headless tick exit codes (TM-1 contract, frozen by Lina 2026-11-21).
/// `0` = tick ok (alerts or not), `2` = tick skipped (consent OFF / no
/// network / backoff active / vault locked), `1` = error.
const headlessExitOk = 0;
const headlessExitError = 1;
const headlessExitSkipped = 2;

/// Outcome of the headless-tick gate: check consent first, vault second.
enum HeadlessTickGate {
  /// Consent ON and vault unlocked — run one poll tick.
  proceed,

  /// Shared `background_alerts` pref OFF (or never written, default OFF).
  /// Exit [headlessExitSkipped]; touch nothing, notify nothing.
  skipConsentOff,

  /// Vault locked (app lock engaged / keychain unavailable). Background
  /// reads are denied: exit [headlessExitSkipped], never prompt headless,
  /// never fall back to plaintext.
  skipVaultLocked,
}

/// Scheduler artifact kinds the headless CLI may be invoked from.
enum SchedulerKind {
  windowsTaskScheduler,
  systemdUserTimer,
  macOsLaunchAgent,
}

/// Decision + exit code for one headless-tick gate evaluation.
class HeadlessTickDecision {
  const HeadlessTickDecision(this.gate, this.exitCode, this.reason);

  final HeadlessTickGate gate;
  final int exitCode;
  final String reason;

  bool get proceed => gate == HeadlessTickGate.proceed;
}

/// Headless security policy: pure decisions, no I/O.
abstract class HeadlessSecurity {
  /// Prefix marking a keychain reference (mirrors `SecureStore` markers).
  /// Anything else in a persisted credential slot is legacy plaintext.
  static const securePrefix = 'secure:';

  /// Key fragments that must never appear in scheduler argv: tokens, key
  /// names/paths, or passphrases (TM-2 binding — vault-only reads inside
  /// the headless process, never argv/env).
  static const forbiddenArgFragments = {
    'srv_cred_',
    'agent_tok_',
    'secure:',
    '--password',
    '--token',
    '--credential',
    '--passphrase',
    '--secret',
    '--api-key',
    '--apikey',
    '--private-key',
    '--key',
    '--key-file',
    'id_rsa',
    '.pem',
    'private_key',
    'BEGIN PRIVATE KEY',
    'BEGIN OPENSSH PRIVATE KEY',
  };

  /// Gate a headless tick. Consent is checked first so a locked vault on
  /// an opted-out machine still reports "consent off" (audit clarity).
  static HeadlessTickDecision evaluateHeadlessTick({
    required bool consentEnabled,
    required bool vaultUnlocked,
  }) {
    if (!consentEnabled) {
      return const HeadlessTickDecision(
        HeadlessTickGate.skipConsentOff,
        headlessExitSkipped,
        'background_alerts consent OFF — headless tick skipped',
      );
    }
    if (!vaultUnlocked) {
      return const HeadlessTickDecision(
        HeadlessTickGate.skipVaultLocked,
        headlessExitSkipped,
        'vault locked — background credential reads denied',
      );
    }
    return const HeadlessTickDecision(
      HeadlessTickGate.proceed,
      headlessExitOk,
      'consent ON, vault unlocked — one poll tick',
    );
  }

  /// Resolve one persisted credential marker against its vault read.
  ///
  /// Returns the in-memory secret, or null when the host must be skipped:
  /// - [marker] not starting with [securePrefix] → null. This is the
  ///   no-plaintext-fallback rule: legacy raw prefs material is NEVER
  ///   returned to the headless poller (healing happens only in an
  ///   interactive session via `SecureStore.readServers`).
  /// - [vaultSecret] null/empty → null (locked-vault denies: fail closed,
  ///   force re-entry in the UI, never prompt headless).
  static String? resolveCredential({
    required String marker,
    required String? vaultSecret,
  }) {
    if (!marker.startsWith(securePrefix)) return null;
    if (vaultSecret == null || vaultSecret.isEmpty) return null;
    return vaultSecret;
  }

  /// Scan scheduler argv for secret material. Returns one violation per
  /// offending arg; empty means clean. Matching is case-insensitive and
  /// covers `key=value` / `key:value` / bare-value shapes.
  static List<String> findSecretMaterialInArgs(List<String> args) {
    final out = <String>[];
    for (final arg in args) {
      final lower = arg.toLowerCase();
      for (final frag in forbiddenArgFragments) {
        if (lower.contains(frag.toLowerCase())) {
          out.add('scheduler arg carries forbidden material ($frag): $arg');
          break;
        }
      }
    }
    return out;
  }

  /// Validate a scheduler artifact (TM-2). Returns violations; empty
  /// means the artifact may invoke the headless CLI.
  ///
  /// - [perUserScope]: Windows per-user task / systemd `--user` timer /
  ///   per-user LaunchAgent. System-wide scope is rejected.
  /// - [runsElevated]: highest-privileges / root / sudo = rejected.
  /// - [args]: scanned by [findSecretMaterialInArgs].
  /// - [invokesHeadlessFlag]: argv must contain [headlessFlag] exactly —
  ///   anything else (a reused interactive entry-point, extra subcommands)
  ///   is a tampered artifact.
  static List<String> validateSchedulerArtifact({
    required SchedulerKind kind,
    required bool perUserScope,
    required bool runsElevated,
    required List<String> args,
    required bool invokesHeadlessFlag,
  }) {
    final violations = <String>[];
    if (!perUserScope) {
      violations.add(
          '${kind.name}: scheduler artifact must be per-user scope (system-wide install rejected)');
    }
    if (runsElevated) {
      violations.add(
          '${kind.name}: scheduler artifact must not run elevated (no highest-privileges / root)');
    }
    if (!invokesHeadlessFlag) {
      violations.add(
          '${kind.name}: scheduler artifact must invoke $headlessFlag exactly (tampered entry-point)');
    }
    violations.addAll(findSecretMaterialInArgs(args));
    return violations;
  }

  /// Where scheduler/prefs artifacts must live so OS ACLs confine them
  /// to the installing user (no world-readable credential-adjacent files).
  static const artifactStorageNotes = {
    SchedulerKind.windowsTaskScheduler:
        'per-user task under %LOCALAPPDATA% / task path \\MyControlPanel\\; '
            'no SYSTEM task, no stored password on the principal, logon + repeat trigger only',
    SchedulerKind.systemdUserTimer:
        'systemd --user unit in ~/.config/systemd/user/ (mode 0600); '
            'no system unit, no Environment= secrets, User= never root',
    SchedulerKind.macOsLaunchAgent:
        'per-user ~/Library/LaunchAgents/*.plist (mode 0600); '
            'no LaunchDaemon, Keychain item gated by device unlock',
  };
}
