// SPDX-License-Identifier: MIT
// TM-2 scheduler-lifecycle tests (Zara): template fill, verify
// invariants (clean + tampered), consent-gated sandbox install,
// uninstall round-trip, status verdicts — both OS branches via the
// injectable `os` parameter so Windows and Linux paths are pinned on
// any host.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:my_control_panel/ops/run_ledger.dart';
import 'package:my_control_panel/ops/scheduler_lifecycle.dart';
import 'package:my_control_panel/services/headless_security.dart';

import 'ops_support/fake_provider.dart';

void main() {
  Directory templates() =>
      SchedulerLifecycle.resolveTemplateDir(override: 'scripts/headless');

  group('template fill', () {
    test('windows fill routes Exec via wrapper, keeps the rest', () {
      final template =
          SchedulerLifecycle.windowsTemplate(templates());
      final filled = SchedulerLifecycle.fillWindowsTask(
        template: template,
        wrapperExe: r'C:\Tools\mycontrolpanel-check.exe',
        tickBinary: r'C:\App\mycontrolpanel.exe',
        installUser: r'DESKTOP\TestUser',
      );
      expect(filled.contains('mycontrolpanel-check.exe'), isTrue);
      expect(filled.contains('--poll-headless'), isTrue);
      expect(filled.contains(r'C:\App\mycontrolpanel.exe'), isTrue);
      // <AllowDemandStart> is dropped: current schtasks parsers reject
      // it outright (bisected on CI); it defaults to true when omitted.
      expect(filled.contains('AllowDemandStart'), isFalse);
      // Non-Exec template body preserved (modulo the dropped
      // header comment + AllowDemandStart line).
      expect(
          SchedulerLifecycle.windowsMatchesTemplateExceptExec(
              filled, template),
          isTrue);
      expect(filled.contains('InteractiveToken'), isTrue);
      expect(filled.contains('LeastPrivilege'), isTrue);
    });

    test('windows task xml survives a UTF-16 write/read round-trip', () async {
      final template =
          SchedulerLifecycle.windowsTemplate(templates());
      final filled = SchedulerLifecycle.fillWindowsTask(
        template: template,
        wrapperExe: r'C:\Tools\mycontrolpanel-check.exe',
        tickBinary: r'C:\App\mycontrolpanel.exe',
        installUser: r'DESKTOP\TestUser',
      );
      final dir = await Directory.systemTemp.createTemp('mcp-ops-xml');
      try {
        final file = File(
            '${dir.path}${Platform.pathSeparator}mcp-poll-task.xml');
        SchedulerLifecycle.writeTaskXml(file, filled);
        final raw = file.readAsBytesSync();
        expect(raw[0], 0xFF);
        expect(raw[1], 0xFE);
        final back = SchedulerLifecycle.readTaskXml(file);
        expect(back, filled);
        // Managed artifact carries no XML comments: the template's
        // header comment names --poll-headless, illegal inside a
        // comment, and schtasks rejects it.
        expect(back, isNot(contains('<!--')));
        expect(
            SchedulerLifecycle.verifyWindowsXml(
                xml: back, taskPath: defaultTaskPath),
            isEmpty);
      } finally {
        await dir.delete(recursive: true);
      }
    });

    test('windows fill fails loud on template drift', () {
      expect(
          () => SchedulerLifecycle.fillWindowsTask(
                template: '<Task><Nope/></Task>',
                wrapperExe: 'w',
                tickBinary: 'b',
                installUser: 'u',
              ),
          throwsStateError);
    });

    test('linux fill routes ExecStart via wrapper only', () {
      final serviceTpl =
          SchedulerLifecycle.linuxServiceTemplate(templates());
      final timerTpl = SchedulerLifecycle.linuxTimerTemplate(templates());
      final filled = SchedulerLifecycle.fillLinuxService(
        template: serviceTpl,
        wrapperExe: '/opt/mcp/mycontrolpanel-check',
        tickBinary: '/opt/mcp/mycontrolpanel',
      );
      final exec = const LineSplitter()
          .convert(filled)
          .where((l) => l.startsWith('ExecStart='));
      expect(exec.length, 1);
      expect(exec.single.contains('--poll-headless'), isTrue);
      expect(exec.single.contains('mycontrolpanel-check'), isTrue);
      expect(timerTpl.contains('OnUnitActiveSec=15min'), isTrue);
    });

    test('linux fill fails loud on template drift', () {
      expect(
          () => SchedulerLifecycle.fillLinuxService(
                template: '[Service]\nType=oneshot\n',
                wrapperExe: 'w',
                tickBinary: 'b',
              ),
          throwsStateError);
    });
  });

  group('verify', () {
    test('clean windows artifact verifies', () {
      final template =
          SchedulerLifecycle.windowsTemplate(templates());
      final filled = SchedulerLifecycle.fillWindowsTask(
        template: template,
        wrapperExe: r'C:\Tools\mycontrolpanel-check.exe',
        tickBinary: r'C:\App\mycontrolpanel.exe',
        installUser: r'DESKTOP\TestUser',
      );
      expect(
          SchedulerLifecycle.verifyWindowsXml(
              xml: filled, taskPath: defaultTaskPath),
          isEmpty);
    });

    test('windows tampering is flagged', () {
      final template =
          SchedulerLifecycle.windowsTemplate(templates());
      final elevated = template
          .replaceFirst('LeastPrivilege', 'HighestAvailable')
          .replaceFirst('<Command>INSTALL_DIR\\mycontrolpanel.exe</Command>',
              '<Command>C:\\App\\mycontrolpanel.exe</Command>');
      final violations = SchedulerLifecycle.verifyWindowsXml(
          xml: elevated, taskPath: defaultTaskPath);
      expect(violations.any((v) => v.contains('must not run elevated')),
          isTrue);

      final noFlag = template.replaceFirst(
          '<Arguments>--poll-headless</Arguments>',
          '<Arguments>--interactive</Arguments>');
      expect(
          SchedulerLifecycle.verifyWindowsXml(
              xml: noFlag, taskPath: defaultTaskPath),
          anyElement(contains('must invoke $headlessFlag')));

      final secret = template.replaceFirst(
          '<Arguments>--poll-headless</Arguments>',
          '<Arguments>--poll-headless --token=abc</Arguments>');
      expect(
          SchedulerLifecycle.verifyWindowsXml(
              xml: secret, taskPath: defaultTaskPath),
          anyElement(contains('forbidden material')));

      expect(
          SchedulerLifecycle.verifyWindowsXml(
              xml: template, taskPath: r'\Other\poll'),
          anyElement(contains('per-user scope')));
    });

    test('windows template drift outside Exec is flagged', () {
      final template =
          SchedulerLifecycle.windowsTemplate(templates());
      final filled = SchedulerLifecycle.fillWindowsTask(
        template: template,
        wrapperExe: 'w',
        tickBinary: 'b',
        installUser: 'u',
      );
      final drifted =
          filled.replaceFirst('PT15M', 'PT5M');
      expect(
          SchedulerLifecycle.windowsMatchesTemplateExceptExec(
              drifted, template),
          isFalse);
    });

    test('windows fill scopes the logon trigger to the installing user',
        () {
      final template =
          SchedulerLifecycle.windowsTemplate(templates());
      final filled = SchedulerLifecycle.fillWindowsTask(
        template: template,
        wrapperExe: 'w',
        tickBinary: 'b',
        installUser: r'DESKTOP\TestUser',
      );
      expect(filled.contains('INSTALL_USER'), isFalse);
      expect(
          filled.contains(r'<UserId>DESKTOP\TestUser</UserId>'), isTrue);
      expect(
          SchedulerLifecycle.verifyWindowsXml(
              xml: filled, taskPath: defaultTaskPath),
          isEmpty);
    });

    test('fidelity tolerates schtasks-stamped identities, not scope loss',
        () {
      final template =
          SchedulerLifecycle.windowsTemplate(templates());
      final filled = SchedulerLifecycle.fillWindowsTask(
        template: template,
        wrapperExe: 'w',
        tickBinary: 'b',
        installUser: r'DESKTOP\TestUser',
      );
      // schtasks resolves the trigger user and stamps the caller SID on
      // the principal — fidelity must still hold for registered XML.
      final registered =
          filled.replaceFirst('DESKTOP', 'S-1-5-21-1-2-3-1001');
      expect(
          SchedulerLifecycle.windowsMatchesTemplateExceptExec(
              registered, template),
          isTrue);
      // Dropping the trigger UserId (back to an unscoped logon trigger)
      // must break fidelity.
      final unscoped = filled.replaceAll(
          RegExp('<UserId>.*?</UserId>'), '');
      expect(
          SchedulerLifecycle.windowsMatchesTemplateExceptExec(
              unscoped, template),
          isFalse);
    });

    test('verify requires a user-scoped logon trigger', () {
      final template =
          SchedulerLifecycle.windowsTemplate(templates());
      // Raw template still carries the INSTALL_USER token: not installable.
      expect(
          SchedulerLifecycle.verifyWindowsXml(
              xml: template, taskPath: defaultTaskPath),
          anyElement(contains('must be scoped')));
      // No UserId at all: unscoped trigger demands elevation.
      final unscoped =
          template.replaceAll(RegExp('      <UserId>.*?</UserId>\n'), '');
      expect(
          SchedulerLifecycle.verifyWindowsXml(
              xml: unscoped, taskPath: defaultTaskPath),
          anyElement(contains('must be scoped')));
    });

    test('clean linux units verify', () {
      final serviceTpl =
          SchedulerLifecycle.linuxServiceTemplate(templates());
      final timerTpl =
          SchedulerLifecycle.linuxTimerTemplate(templates());
      final filled = SchedulerLifecycle.fillLinuxService(
        template: serviceTpl,
        wrapperExe: '/opt/mcp/mycontrolpanel-check',
        tickBinary: '/opt/mcp/mycontrolpanel',
      );
      expect(
          SchedulerLifecycle.verifyLinuxService(
            service: filled,
            timer: timerTpl,
            timerTemplate: timerTpl,
            unitPath: '/home/u/.config/systemd/user/mcp-poll.service',
          ),
          isEmpty);
    });

    test('linux violations are flagged', () {
      final serviceTpl =
          SchedulerLifecycle.linuxServiceTemplate(templates());
      final timerTpl =
          SchedulerLifecycle.linuxTimerTemplate(templates());
      final filled = SchedulerLifecycle.fillLinuxService(
        template: serviceTpl,
        wrapperExe: '/opt/mcp/mycontrolpanel-check',
        tickBinary: '/opt/mcp/mycontrolpanel',
      );

      final withSecret = '$filled\nEnvironment=AGENT_TOKEN=x\n';
      expect(
          SchedulerLifecycle.verifyLinuxService(
            service: withSecret,
            timer: timerTpl,
            timerTemplate: timerTpl,
            unitPath: '/home/u/.config/systemd/user/mcp-poll.service',
          ),
          anyElement(contains('Environment=')));

      expect(
          SchedulerLifecycle.verifyLinuxService(
            service: filled,
            timer: '[Timer]\nOnUnitActiveSec=5min\n',
            timerTemplate: timerTpl,
            unitPath: '/home/u/.config/systemd/user/mcp-poll.service',
          ),
          anyElement(contains('timer unit drifted')));

      final root = filled.replaceFirst(
          'Nice=10', 'Nice=10\nUser=root');
      expect(
          SchedulerLifecycle.verifyLinuxService(
            service: root,
            timer: timerTpl,
            timerTemplate: timerTpl,
            unitPath: '/home/u/.config/systemd/user/mcp-poll.service',
          ),
          anyElement(contains('must not run elevated')));
    });
  });

  group('install consent gate + sandbox round-trip', () {
    test('consent-OFF preflight refuses install without --force',
        () async {
      final sandbox =
          await Directory.systemTemp.createTemp('mcp-ops-sb');
      try {
        final result = await SchedulerLifecycle.install(InstallOptions(
          installDir: r'C:\App',
          wrapperPath: r'C:\Tools\mycontrolpanel-check.exe',
          sandbox: sandbox.path,
          os: OpsOs.windows,
          templateDir: 'scripts/headless',
          installUser: r'DESKTOP\TestUser',
          preflight: () async => FakeProviders.consentOff(),
        ));
        expect(result.ok, isFalse);
        expect(result.detail, contains('background alerts'));
      } finally {
        await sandbox.delete(recursive: true);
      }
    });

    test('windows sandbox install → status → uninstall', () async {
      final sandbox =
          await Directory.systemTemp.createTemp('mcp-ops-win');
      final state =
          await Directory.systemTemp.createTemp('mcp-ops-wstate');
      try {
        final installed =
            await SchedulerLifecycle.install(InstallOptions(
          installDir: r'C:\App',
          wrapperPath: r'C:\Tools\mycontrolpanel-check.exe',
          sandbox: sandbox.path,
          os: OpsOs.windows,
          templateDir: 'scripts/headless',
          installUser: r'DESKTOP\TestUser',
          force: true,
          preflight: () async => FakeProviders.ok(),
        ));
        expect(installed.ok, isTrue);
        expect(
            File('${sandbox.path}${Platform.pathSeparator}'
                    'mcp-poll-task.xml')
                .existsSync(),
            isTrue);

        var st = await SchedulerLifecycle.status(
          sandbox: sandbox.path,
          stateDir: state,
          os: OpsOs.windows,
        );
        expect(st.installed, isTrue);
        expect(st.verdict, 'never-ran');
        expect(st.missedHeartbeat, isTrue);

        // One supervised run lands the ledger → fresh.
        RunLedger.append(
            RunLedger.ledgerFile(state),
            RunLedger.buildRecord(
                atMs: DateTime.now().millisecondsSinceEpoch,
                provider: 'mycontrolpanel.exe',
                exitCode: 0,
                status: 'ok',
                durationMs: 1));
        st = await SchedulerLifecycle.status(
          sandbox: sandbox.path,
          stateDir: state,
          os: OpsOs.windows,
        );
        expect(st.verdict, 'fresh');
        expect(st.missedHeartbeat, isFalse);

        final uninstalled = await SchedulerLifecycle.uninstall(
            sandbox: sandbox.path, os: OpsOs.windows);
        expect(uninstalled.ok, isTrue);
        st = await SchedulerLifecycle.status(
          sandbox: sandbox.path,
          stateDir: state,
          os: OpsOs.windows,
        );
        expect(st.installed, isFalse);
      } finally {
        await sandbox.delete(recursive: true);
        await state.delete(recursive: true);
      }
    });

    test('linux sandbox install → verify → uninstall', () async {
      final sandbox =
          await Directory.systemTemp.createTemp('mcp-ops-lin');
      try {
        final installed =
            await SchedulerLifecycle.install(InstallOptions(
          installDir: '/opt/mcp',
          wrapperPath: '/opt/mcp/mycontrolpanel-check',
          sandbox: sandbox.path,
          os: OpsOs.linux,
          templateDir: 'scripts/headless',
          force: true,
          preflight: () async => FakeProviders.ok(),
        ));
        expect(installed.ok, isTrue);
        final sep = Platform.pathSeparator;
        final service =
            File('${sandbox.path}${sep}mcp-poll.service');
        final timer = File('${sandbox.path}${sep}mcp-poll.timer');
        expect(service.existsSync(), isTrue);
        expect(timer.existsSync(), isTrue);

        final violations =
            SchedulerLifecycle.verifyLinuxService(
          service: service.readAsStringSync(),
          timer: timer.readAsStringSync(),
          timerTemplate:
              SchedulerLifecycle.linuxTimerTemplate(templates()),
          unitPath: service.path,
          sandbox: true,
        );
        expect(violations, isEmpty);

        final uninstalled = await SchedulerLifecycle.uninstall(
            sandbox: sandbox.path, os: OpsOs.linux);
        expect(uninstalled.ok, isTrue);
        expect(service.existsSync(), isFalse);
      } finally {
        await sandbox.delete(recursive: true);
      }
    });

    test('macOS install is refused with guidance', () async {
      final result = await SchedulerLifecycle.install(InstallOptions(
        installDir: '/Applications/X',
        wrapperPath: '/tmp/w',
        os: OpsOs.macos,
        preflight: () async => FakeProviders.ok(),
      ));
      expect(result.ok, isFalse);
      expect(result.detail, contains('Elizabeth'));
    });

    test('preflight transport failure blocks without --force',
        () async {
      final sandbox =
          await Directory.systemTemp.createTemp('mcp-ops-pre');
      try {
        final result = await SchedulerLifecycle.install(InstallOptions(
          installDir: r'C:\App',
          wrapperPath: 'w',
          sandbox: sandbox.path,
          os: OpsOs.windows,
          templateDir: 'scripts/headless',
          installUser: r'DESKTOP\TestUser',
          preflight: () async => FakeProviders.totalFailure(),
        ));
        expect(result.ok, isFalse);
      } finally {
        await sandbox.delete(recursive: true);
      }
    });
  });

  group('status verdicts', () {
    test('stale ledger + installed scheduler = missed heartbeat',
        () async {
      final sandbox =
          await Directory.systemTemp.createTemp('mcp-ops-stale');
      final state =
          await Directory.systemTemp.createTemp('mcp-ops-stalestate');
      try {
        File('${sandbox.path}${Platform.pathSeparator}'
                'mcp-poll-task.xml')
            .writeAsStringSync('<Task/>');
        RunLedger.append(
            RunLedger.ledgerFile(state),
            RunLedger.buildRecord(
                atMs: DateTime.now()
                    .subtract(const Duration(hours: 2))
                    .millisecondsSinceEpoch,
                provider: 'mycontrolpanel.exe',
                exitCode: 2,
                status: 'skipped',
                durationMs: 1,
                reason: 'background_alerts consent OFF — skipped'));
        final st = await SchedulerLifecycle.status(
          sandbox: sandbox.path,
          stateDir: state,
          os: OpsOs.windows,
          staleAfter: const Duration(minutes: 30),
        );
        expect(st.verdict, 'stale');
        expect(st.missedHeartbeat, isTrue);
        expect(st.consentHint, isTrue);
      } finally {
        await sandbox.delete(recursive: true);
        await state.delete(recursive: true);
      }
    });
  });
}
