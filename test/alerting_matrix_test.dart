// SPDX-License-Identifier: MIT
/// Alerting QA harness (Balqis, Beta.2 TM-6): deterministic CI matrices for
/// the alerting rails — consent granted/denied/revoked, stale thresholds,
/// cold start, alpha.2 upgrade, battery-saver/OS-killed, and desktop
/// foreground-vs-closed exactly-once.
///
/// CI determinism contract (this file MUST stay green on the ubuntu runner):
/// - No WorkManager / BGTaskScheduler / local-notifications call is ever
///   made. Mobile scheduling is guarded by `BackgroundAlerts.schedule()`
///   (no-op off Android/iOS here); the background tick runs with an
///   injectable `fetchAlertsFor` so no SSH/agent HTTP ever leaves the test.
/// - Plugin-backed reads (`flutter_secure_storage`) fail closed to null in
///   `flutter test` and every assertion accounts for that: seeded servers
///   carry an empty credential so `SecureStore.readServers()` never touches
///   the keychain, and `showFresh` is only pinned to "silent, never throws".
/// - SharedPreferences is the only real mock (`setMockInitialValues`),
///   reset in `setUp` so rows never leak into each other.
///
/// Device-lab rows (SSH-live hosts, real schedulers, real toasts) are NOT
/// here — they live in the guarded `device-lab` lane
/// (`.github/workflows/device-lab.yml`) + `docs/qa/test-plan-beta.md`.
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:my_control_panel/models/alert_entry.dart';
import 'package:my_control_panel/models/mock_data.dart' show DeployItem;
import 'package:my_control_panel/models/server_connection.dart';
import 'package:my_control_panel/services/alert_watch.dart';
import 'package:my_control_panel/services/background_alerts.dart';
import 'package:my_control_panel/services/desktop_alerts.dart';
import 'package:my_control_panel/services/headless_security.dart';
import 'package:my_control_panel/services/polling_alerts.dart';
import 'package:my_control_panel/services/secure_store.dart';

/// Deterministic doubles: one empty-credential server per host (never
/// touches the keychain), one firing disk alert, one failed CI run.
class MatrixDoubles {
  static ServerConnection server(String id, String host) => ServerConnection(
        id: id,
        name: host,
        host: host,
        port: 22,
        username: 'ops',
        authMethod: AuthMethod.password,
        credential: '',
        region: 'us-east-1',
        os: 'Ubuntu 24.04',
        env: ServerEnv.prod,
        createdAt: DateTime(2026, 1, 1),
      );

  static AlertEntry firingDisk(String host) => AlertEntry(
        title: 'disk / at 97% on $host',
        source: 'disk',
        severity: 'critical',
        serverId: 's1',
        serverName: host,
      );

  static DeployItem failedRun() => DeployItem(
        app: 'api-gateway',
        version: 'v2.14.3',
        env: 'prod',
        actor: 'ci',
        time: DateTime(2026, 10, 1),
        status: 'failed',
        duration: '3m',
      );

  /// Seed [hosts] into prefs without touching the keychain (empty
  /// credentials decode verbatim; `secure:` markers are NOT used here —
  /// the upgrade rows cover those via `HeadlessSecurity` directly).
  static Future<void> seedServers(List<ServerConnection> servers) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        'server_connections', ServerConnection.encodeList(servers));
  }
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('AM-C consent matrix (granted / denied / revoked)', () {
    test('AM-C1 denied by default: never-written pref gates every rail', () async {
      expect(await BackgroundAlerts.isEnabled(), isFalse);
      expect(await DesktopAlerts.isEnabled(), isFalse);
      final gate = HeadlessSecurity.evaluateHeadlessTick(
        consentEnabled: await BackgroundAlerts.isEnabled(),
        vaultUnlocked: true,
      );
      expect(gate.gate, HeadlessTickGate.skipConsentOff);
      expect(gate.exitCode, headlessExitSkipped);
    });

    test('AM-C2 granted persists on the shared toggle', () async {
      await BackgroundAlerts.setEnabled(true);
      expect(await BackgroundAlerts.isEnabled(), isTrue);
      expect(await DesktopAlerts.isEnabled(), isTrue);
    });

    test('AM-C3 revoked stops the rails (opt-out is immediate)', () async {
      await BackgroundAlerts.setEnabled(true);
      await BackgroundAlerts.setEnabled(false);
      expect(await BackgroundAlerts.isEnabled(), isFalse);
      expect(await DesktopAlerts.isEnabled(), isFalse);
      final gate = HeadlessSecurity.evaluateHeadlessTick(
        consentEnabled: false,
        vaultUnlocked: true,
      );
      expect(gate.proceed, isFalse);
      expect(gate.exitCode, headlessExitSkipped);
    });

    test('AM-C4 headless gate: consent OFF wins over unlocked vault', () {
      final gate = HeadlessSecurity.evaluateHeadlessTick(
        consentEnabled: false,
        vaultUnlocked: true,
      );
      expect(gate.gate, HeadlessTickGate.skipConsentOff);
      expect(gate.exitCode, headlessExitSkipped);
    });

    test('AM-C5 consent copy carries the binding ~15 min wording', () {
      expect(BackgroundAlerts.consentCopy, contains('~15 min'));
      expect(BackgroundAlerts.consentCopy, contains('in the background'));
      expect(BackgroundAlerts.pollFrequency, const Duration(minutes: 15));
    });
  });

  group('AM-S stale thresholds (backoff, warn/crit, honesty stamp)', () {
    test('AM-S1 PollPolicy backoff: 5m base, doubling, 1h cap', () {
      const policy = PollPolicy();
      expect(policy.nextDelay(0), const Duration(minutes: 5));
      expect(policy.nextDelay(1), const Duration(minutes: 10));
      expect(policy.nextDelay(2), const Duration(minutes: 20));
      expect(policy.nextDelay(3), const Duration(minutes: 40));
      expect(policy.nextDelay(4), const Duration(hours: 1));
      expect(policy.nextDelay(10), const Duration(hours: 1));
    });

    test('AM-S2 Thresholds: warn at 0.85, critical at 0.95', () {
      const thresholds = Thresholds();
      expect(thresholds.evaluate(0.84), AlertSeverity.ok);
      expect(thresholds.evaluate(0.85), AlertSeverity.warning);
      expect(thresholds.evaluate(0.94), AlertSeverity.warning);
      expect(thresholds.evaluate(0.95), AlertSeverity.critical);
    });

    test('AM-S3 staleness copy: never / just-now / min / hr / days', () {
      final now = DateTime(2026, 10, 30, 12, 0, 0);
      expect(
        BackgroundAlerts.formatLastChecked(now: now),
        contains('never checked'),
      );
      expect(
        BackgroundAlerts.formatLastChecked(
            now: now, last: now.subtract(const Duration(seconds: 30))),
        'last checked just now',
      );
      expect(
        BackgroundAlerts.formatLastChecked(
            now: now, last: now.subtract(const Duration(minutes: 16))),
        'last checked 16 min ago',
      );
      expect(
        BackgroundAlerts.formatLastChecked(
            now: now, last: now.subtract(const Duration(hours: 3))),
        'last checked 3 hr ago',
      );
      expect(
        BackgroundAlerts.formatLastChecked(
            now: now, last: now.subtract(const Duration(days: 2))),
        'last checked 2 days ago',
      );
    });

    test('AM-S4 future stamp (clock skew) reads just now, never negative',
        () {
      final now = DateTime(2026, 10, 30, 12, 0, 0);
      expect(
        BackgroundAlerts.formatLastChecked(
            now: now, last: now.add(const Duration(minutes: 5))),
        'last checked just now',
      );
    });

    test('AM-S5 Slo math: empty never breaches', () {
      expect(Slo.uptimePct(0, 0), isNull);
      expect(Slo.breaches(null, 0.99), isFalse);
      expect(Slo.breaches(0.98, 0.99), isTrue);
      expect(Slo.breaches(1.0, 0.99), isFalse);
    });

    test('AM-S6 empty-host tick still stamps the check (never silent)',
        () async {
      await BackgroundAlerts.setEnabled(true);
      await BackgroundAlerts.runBackgroundTick(
        fetchAlertsFor: (_) async => <AlertEntry>[],
      );
      expect(await BackgroundAlerts.readLastCheck(), isNotNull);
      expect(await BackgroundAlerts.lastCheckedLabel(),
          contains('last checked'));
    });
  });

  group('AM-F cold start (first launch, empty prefs)', () {
    test('AM-F1 empty state: no consent, no stamp, no badge, no body',
        () async {
      expect(await BackgroundAlerts.readLastCheck(), isNull);
      expect(await BackgroundAlerts.lastCheckedLabel(),
          contains('never checked'));
      expect(AlertWatch.currentKeys(const [], const []), isEmpty);
      expect(
          AlertWatch.freshTitles(const {}, const {}, const [], const []),
          isEmpty);
      expect(
          NotificationHook.build('MyControlPanel alert', const [])['body'],
          '');
    });

    test('AM-F2 first firing alert is entirely fresh (empty seen set)',
        () async {
      final alert = MatrixDoubles.firingDisk('cold-host');
      final run = MatrixDoubles.failedRun();
      final current = AlertWatch.currentKeys([alert], [run]);
      expect(current, hasLength(2));
      final fresh = AlertWatch.freshTitles(current, const {}, [alert], [run]);
      expect(fresh, hasLength(2));
      final payload =
          BackgroundAlerts.buildLocalPayload('MyControlPanel alert', fresh);
      expect(payload['body'], isNotEmpty);
    });

    test('AM-F3 cold start defaults the headless gate to skip (exit 2)', () {
      final gate = HeadlessSecurity.evaluateHeadlessTick(
        consentEnabled: false,
        vaultUnlocked: false,
      );
      expect(gate.gate, HeadlessTickGate.skipConsentOff);
      expect(gate.exitCode, headlessExitSkipped);
    });
  });

  group('AM-U alpha.2 upgrade (vault markers, no plaintext fallback)', () {
    test('AM-U1 secure marker + vault secret resolves headless', () {
      expect(
        HeadlessSecurity.resolveCredential(
          marker: 'secure:srv_cred_s1',
          vaultSecret: 's3cr3t',
        ),
        's3cr3t',
      );
    });

    test('AM-U2 legacy plaintext marker never resolves (heal is UI-only)',
        () {
      expect(
        HeadlessSecurity.resolveCredential(
          marker: 'hunter2-plaintext',
          vaultSecret: 'hunter2-plaintext',
        ),
        isNull,
      );
    });

    test('AM-U3 locked vault denies the host (null/empty secret)', () {
      expect(
        HeadlessSecurity.resolveCredential(
          marker: 'secure:srv_cred_s1',
          vaultSecret: null,
        ),
        isNull,
      );
      expect(
        HeadlessSecurity.resolveCredential(
          marker: 'secure:srv_cred_s1',
          vaultSecret: '',
        ),
        isNull,
      );
      final gate = HeadlessSecurity.evaluateHeadlessTick(
        consentEnabled: true,
        vaultUnlocked: false,
      );
      expect(gate.gate, HeadlessTickGate.skipVaultLocked);
      expect(gate.exitCode, headlessExitSkipped);
      expect(gate.reason, contains('denied'));
    });

    test('AM-U4 secure marker without a vault secret forces re-entry', () async {
      await BackgroundAlerts.setEnabled(true);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
          'server_connections',
          ServerConnection.encodeList(
              [MatrixDoubles.server('s9', 'upgraded-host')]));
      // Empty credential decodes verbatim without keychain reads; a real
      // `secure:` marker with a locked vault resolves to '' (re-entry).
      final servers = await SecureStore.readServers();
      expect(servers, hasLength(1));
      expect(servers.single.host, 'upgraded-host');
    });
  });

  group('AM-B battery-saver / OS-killed (backoff, no hot retry)', () {
    test('AM-B1 throwing fetch never sinks the tick; check still stamped',
        () async {
      await BackgroundAlerts.setEnabled(true);
      await MatrixDoubles.seedServers([MatrixDoubles.server('s1', 'sick')]);
      await BackgroundAlerts.runBackgroundTick(
        fetchAlertsFor: (_) async => throw Exception('radio dead'),
      );
      expect(await BackgroundAlerts.readLastCheck(), isNotNull);
    });

    test('AM-B2 one sick host never sinks a healthy sibling', () async {
      await BackgroundAlerts.setEnabled(true);
      await MatrixDoubles.seedServers([
        MatrixDoubles.server('s1', 'sick-host'),
        MatrixDoubles.server('s2', 'well-host'),
      ]);
      await BackgroundAlerts.runBackgroundTick(
        fetchAlertsFor: (server) async {
          if (server.host == 'sick-host') throw Exception('timeout');
          return [MatrixDoubles.firingDisk('well-host')];
        },
      );
      final prefs = await SharedPreferences.getInstance();
      final seen = prefs.getStringList('alert_watch_seen_v1')?.toSet() ?? {};
      expect(
        seen,
        contains(AlertWatch.keyFor(
            'alert', 'disk / at 97% on well-host', 'well-host')),
      );
      expect(await BackgroundAlerts.readLastCheck(), isNotNull);
    });

    test('AM-B3 scheduler argv scan flags secret material', () {
      expect(
          HeadlessSecurity.findSecretMaterialInArgs(
              ['mycontrolpanel', '--poll-headless']),
          isEmpty);
      expect(
          HeadlessSecurity.findSecretMaterialInArgs(
              ['mycontrolpanel', '--poll-headless', '--token=abc']),
          isNotEmpty);
      expect(
          HeadlessSecurity.findSecretMaterialInArgs(
              ['mycontrolpanel', '--poll-headless', 'secure:srv_cred_s1']),
          isNotEmpty);
    });

    test('AM-B4 artifact validation: per-user, no elevation, exact flag',
        () {
      for (final kind in SchedulerKind.values) {
        expect(
          HeadlessSecurity.validateSchedulerArtifact(
            kind: kind,
            perUserScope: true,
            runsElevated: false,
            args: const ['mycontrolpanel', '--poll-headless'],
            invokesHeadlessFlag: true,
          ),
          isEmpty,
          reason: '$kind clean artifact must pass',
        );
        final bad = HeadlessSecurity.validateSchedulerArtifact(
          kind: kind,
          perUserScope: false,
          runsElevated: true,
          args: const ['mycontrolpanel', '--token=abc'],
          invokesHeadlessFlag: false,
        );
        expect(bad.length, greaterThanOrEqualTo(3), reason: '$kind');
      }
    });
  });

  group('AM-D desktop foreground-vs-closed (shared rail, exactly-once)', () {
    test('AM-D1 one consent pref gates both rails (no second toggle)', () async {
      expect(BackgroundAlerts.prefEnabledKey, 'background_alerts');
      expect(await DesktopAlerts.isEnabled(), isFalse);
    });

    test('AM-D1b opt-in is honored through the shared pref', () async {
      SharedPreferences.setMockInitialValues(
          {BackgroundAlerts.prefEnabledKey: true});
      expect(await DesktopAlerts.isEnabled(), isTrue);
    });

    test('AM-D2 payload parity: desktop == NotificationHook verbatim', () {
      const shapes = [
        <String>[],
        ['  ', ''],
        ['a'],
        ['a', 'b', 'c'],
        ['a', 'b', 'c', 'd', 'e'],
      ];
      for (final titles in shapes) {
        expect(
          DesktopAlerts.buildLocalPayload('t', titles),
          BackgroundAlerts.buildLocalPayload('t', titles),
        );
        final clean = titles.where((t) => t.trim().isNotEmpty).toList();
        expect(
          DesktopAlerts.buildLocalPayload('t', titles),
          NotificationHook.build('t', clean),
        );
      }
    });

    test('AM-D3 exactly-once: shared seen-set suppresses the second rail',
        () async {
      final alert = MatrixDoubles.firingDisk('desk-host');
      final current = AlertWatch.currentKeys([alert], const []);
      final first =
          AlertWatch.freshTitles(current, const {}, [alert], const []);
      expect(first, hasLength(1));
      // Foreground rail consumes the batch (in-app snack / desktop toast).
      await AlertWatch.markSeen(current);
      // Headless tick sees the same shared set: nothing fresh, no toast.
      final prefs = await SharedPreferences.getInstance();
      final seen =
          prefs.getStringList('alert_watch_seen_v1')?.toSet() ?? {};
      expect(AlertWatch.freshTitles(current, seen, [alert], const []),
          isEmpty);
    });

    test('AM-D4 in-app fan-out stamps the shared check (honest while open)',
        () async {
      await BackgroundAlerts.setEnabled(true);
      await DesktopAlerts.recordCheck();
      expect(await BackgroundAlerts.readLastCheck(), isNotNull);
      expect(
          await BackgroundAlerts.lastCheckedLabel(now: DateTime.now()),
          contains('last checked'));
    });

    test('AM-D5 rails stay silent without consent (never throws)', () async {
      expect(await DesktopAlerts.showFresh(['disk / at 97%']), isFalse);
      expect(await BackgroundAlerts.showFresh(['disk / at 97%']), isFalse);
    });

    test('AM-D5b rails stay silent with no payload (never throws)', () async {
      SharedPreferences.setMockInitialValues(
          {BackgroundAlerts.prefEnabledKey: true});
      expect(await DesktopAlerts.showFresh([]), isFalse);
      expect(await DesktopAlerts.showFresh(['  ', '']), isFalse);
    });
  });

  group('AM-M deterministic-mock contract (what CI never touches)', () {
    test('AM-M1 scheduler/plugin entry-points are safe no-ops in CI',
        () async {
      await BackgroundAlerts.schedule();
      await BackgroundAlerts.cancel();
      await BackgroundAlerts.requestPermissions();
      await BackgroundAlerts.ensureInitialized();
      await DesktopAlerts.ensureInitialized();
    });

    test('AM-M2 injected fetch drives the tick end to end', () async {
      await BackgroundAlerts.setEnabled(true);
      await MatrixDoubles.seedServers([MatrixDoubles.server('s1', 'lab')]);
      await BackgroundAlerts.runBackgroundTick(
        fetchAlertsFor: (server) async => [MatrixDoubles.firingDisk(server.host)],
      );
      final prefs = await SharedPreferences.getInstance();
      final seen = prefs.getStringList('alert_watch_seen_v1')?.toSet() ?? {};
      expect(
        seen,
        contains(
            AlertWatch.keyFor('alert', 'disk / at 97% on lab', 'lab')),
      );
    });

    test('AM-M3 tampered entry-point is rejected on every scheduler', () {
      for (final kind in SchedulerKind.values) {
        final violations = HeadlessSecurity.validateSchedulerArtifact(
          kind: kind,
          perUserScope: true,
          runsElevated: false,
          args: const ['mycontrolpanel', '--serve'],
          invokesHeadlessFlag: false,
        );
        expect(violations, isNotEmpty, reason: '$kind');
        expect(violations.join(' '), contains(headlessFlag));
      }
    });
  });
}
