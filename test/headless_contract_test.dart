// SPDX-License-Identifier: MIT
// TM-1 contract tests (Lina): scheduler templates honor ADR-003, frozen
// constants stay frozen, reuse table stays verbatim.
//
// These tests are the machine-readable half of
// `docs/specs/headless-cli-contract.md` — Zara's lifecycle, Elizabeth's
// slice, and Lisa's poller all build against the invariants pinned here.
// A failing test here means the TM-1 freeze moved: get Lina + Rina
// sign-off before "fixing" the expectation.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:my_control_panel/background/headless_check.dart';
import 'package:my_control_panel/services/background_alerts.dart';
import 'package:my_control_panel/services/headless_security.dart';

String _repoRoot() {
  // test/ sits at the repo root; walk up until pubspec.yaml is found.
  var dir = Directory.current;
  for (var i = 0; i < 6; i++) {
    if (File('${dir.path}${Platform.pathSeparator}pubspec.yaml')
        .existsSync()) {
      return dir.path;
    }
    dir = dir.parent;
  }
  return Directory.current.path;
}

String _read(String rel) {
  final sep = Platform.pathSeparator;
  return File('${_repoRoot()}$sep${rel.replaceAll('/', sep)}')
      .readAsStringSync();
}

void main() {
  group('frozen CLI contract', () {
    test('flag + exit codes are frozen', () {
      expect(headlessFlag, '--poll-headless');
      expect(headlessExitOk, 0);
      expect(headlessExitError, 1);
      expect(headlessExitSkipped, 2);
    });

    test('notification title matches the mobile rail verbatim', () {
      // BackgroundAlerts.showFresh builds with 'MyControlPanel alert' —
      // the headless rail must announce with the identical string.
      expect(HeadlessCheck.notificationTitle, 'MyControlPanel alert');
    });

    test('threshold + policy defaults are the frozen table', () {
      expect(HeadlessCheck.rules.diskWarnAt, 0.80);
      expect(HeadlessCheck.rules.diskCritAt, 0.90);
      expect(HeadlessCheck.thresholds.warnAt, 0.85);
      expect(HeadlessCheck.thresholds.critAt, 0.95);
      expect(HeadlessCheck.pollPolicy.baseInterval,
          const Duration(minutes: 5));
      expect(HeadlessCheck.pollPolicy.maxInterval,
          const Duration(hours: 1));
      expect(HeadlessCheck.resendCooldown, const Duration(hours: 6));
      expect(BackgroundAlerts.prefEnabledKey, 'background_alerts');
    });
  });

  group('scheduler templates (ADR-003 invariants)', () {
    test('windows task: per-user, no elevation, exact argv', () {
      final xml =
          _read('scripts/headless/windows/mcp-poll-task.xml');
      expect(xml, contains('--poll-headless'));
      expect(xml, isNot(contains('HighestAvailableAuthority')));
      expect(xml, isNot(contains('System')));
      final violations = HeadlessSecurity.findSecretMaterialInArgs(
          xml.split('\n'));
      // The whole template — comments included — must scan clean: no
      // example in this file may normalize secret-bearing argv.
      expect(violations, isEmpty);
      final argsLine = xml
          .split('\n')
          .firstWhere((l) => l.contains('<Arguments>'));
      expect(argsLine.trim(), '<Arguments>--poll-headless</Arguments>');
      expect(
        HeadlessSecurity.validateSchedulerArtifact(
          kind: SchedulerKind.windowsTaskScheduler,
          perUserScope: true,
          runsElevated: false,
          args: const ['mycontrolpanel.exe', '--poll-headless'],
          invokesHeadlessFlag: true,
        ),
        isEmpty,
      );
    });

    test('systemd units: user scope, no Environment secrets', () {
      final service =
          _read('scripts/headless/linux/mcp-poll.service');
      final timer = _read('scripts/headless/linux/mcp-poll.timer');
      expect(service, contains('--poll-headless'));
      expect(service, isNot(contains('Environment=')));
      expect(service, contains('Type=oneshot'));
      expect(timer, contains('OnUnitActiveSec=15min'));
      expect(
        HeadlessSecurity.findSecretMaterialInArgs(
            service.split('\n') + timer.split('\n')),
        isEmpty,
      );
    });

    test('macOS plist: LaunchAgent scope, 900s interval', () {
      final plist =
          _read('scripts/headless/macos/com.mycontrolpanel.poll.plist');
      expect(plist, contains('--poll-headless'));
      expect(plist, contains('<integer>900</integer>'));
      expect(plist, isNot(contains('LaunchDaemon')));
      expect(
        HeadlessSecurity.findSecretMaterialInArgs(plist.split('\n')),
        isEmpty,
      );
    });

    test('manual scripts invoke the exact headless argv', () {
      final ps1 =
          _read('scripts/headless/install-windows.ps1');
      final sh = _read('scripts/headless/install-linux.sh');
      final mac = _read('scripts/headless/install-macos.sh');
      for (final s in [ps1, sh, mac]) {
        expect(s, contains('--poll-headless'));
        expect(
          HeadlessSecurity.findSecretMaterialInArgs(s.split('\n')),
          isEmpty,
        );
      }
      expect(ps1.toLowerCase(), isNot(contains('runas')));
      // No elevation INVOKED: comments may name the forbidden tools, but
      // no operative line may call them.
      bool invokes(String script, String tool) => script
          .split('\n')
          .where((l) => !l.trimLeft().startsWith('#'))
          .any((l) => RegExp('(^|\\s|;)$tool\\s').hasMatch(l));
      expect(invokes(sh, 'sudo'), isFalse);
      expect(invokes(mac, 'sudo'), isFalse);
    });
  });
}
