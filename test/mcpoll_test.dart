// SPDX-License-Identifier: MIT
// mcpoll operator CLI contract (Lisa, TM-1 follow-up): arg parsing,
// servers-file loading, pure snapshot/metrics mapping, scheduler
// examples (ADR-003 invariants), frozen reuse table.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:my_control_panel/background/headless_check.dart';
import 'package:my_control_panel/mcpoll/config.dart';
import 'package:my_control_panel/mcpoll/snapshot_fetch.dart';
import 'package:my_control_panel/services/headless_security.dart';

String _repoRoot() {
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

File _writeTempServers(String body) {
  final dir = Directory.systemTemp.createTempSync('mcpoll-test');
  final f = File('${dir.path}${Platform.pathSeparator}servers.json');
  f.writeAsStringSync(body);
  return f;
}

void main() {
  group('parseMcpollArgs', () {
    test('--help throws McpollHelp (exit 0)', () {
      expect(() => parseMcpollArgs(['--help']), throwsA(isA<McpollHelp>()));
      expect(() => parseMcpollArgs(['-h']), throwsA(isA<McpollHelp>()));
    });

    test('nothing to poll is an error', () {
      expect(() => parseMcpollArgs(['--consent']),
          throwsA(isA<McpollArgError>()));
    });

    test('single-host mode defaults', () {
      final c = parseMcpollArgs(['--consent', '--host', 'h.example']);
      expect(c.consent, isTrue);
      expect(c.hosts, hasLength(1));
      expect(c.hosts.single.host, 'h.example');
      expect(c.hosts.single.port, 9108);
      expect(c.hosts.single.name, 'h.example');
      expect(c.timeout, const Duration(seconds: 15));
      expect(c.maxHosts, 10);
      expect(c.noSnapshot, isFalse);
    });

    test('single-host overrides + caps', () {
      final c = parseMcpollArgs([
        '--host', 'h.example', '--name', 'web', '--id', 'w1', '--port', '19108',
        '--token-env', 'TOK_X', '--state-dir', '/tmp/x',
        '--timeout-secs', '7', '--max-hosts', '3', '--no-snapshot',
      ]);
      expect(c.consent, isFalse);
      expect(c.hosts.single.name, 'web');
      expect(c.hosts.single.port, 19108);
      expect(c.hosts.single.tokenEnv, 'TOK_X');
      expect(c.stateDirOverride, '/tmp/x');
      expect(c.timeout, const Duration(seconds: 7));
      expect(c.maxHosts, 3);
      expect(c.noSnapshot, isTrue);
    });

    test('out-of-range ints are errors', () {
      for (final argv in [
        ['--host', 'h', '--timeout-secs', '0'],
        ['--host', 'h', '--timeout-secs', '61'],
        ['--host', 'h', '--max-hosts', '0'],
        ['--host', 'h', '--max-hosts', '11'],
        ['--host', 'h', '--port', '99999'],
      ]) {
        expect(() => parseMcpollArgs(argv),
            throwsA(isA<McpollArgError>()), reason: '$argv');
      }
    });

    test('missing flag values are errors', () {
      for (final argv in [
        ['--host'],
        ['--servers'],
        ['--host', 'h', '--port'],
      ]) {
        expect(() => parseMcpollArgs(argv),
            throwsA(isA<McpollArgError>()), reason: '$argv');
      }
    });
  });

  group('loadServersFile', () {
    test('loads entries with defaults', () {
      final f = _writeTempServers(
          '[{"host":"a.example"},{"id":"db","name":"DB","host":"b.example","port":19108,"tokenEnv":"TOK_DB"}]');
      final hosts = loadServersFile(f.path);
      expect(hosts, hasLength(2));
      expect(hosts.first.port, 9108);
      expect(hosts.first.tokenEnv, isNull);
      expect(hosts.last.port, 19108);
      expect(hosts.last.tokenEnv, 'TOK_DB');
    });

    test('bad files are errors, never throws raw', () {
      expect(() => loadServersFile('/no/such/file.json'),
          throwsA(isA<McpollArgError>()));
      final bad = _writeTempServers('not json');
      expect(() => loadServersFile(bad.path),
          throwsA(isA<McpollArgError>()));
      final nonArray = _writeTempServers('{"host":"a"}');
      expect(() => loadServersFile(nonArray.path),
          throwsA(isA<McpollArgError>()));
      final noHost = _writeTempServers('[{}]');
      expect(
          () => loadServersFile(noHost.path), throwsA(isA<McpollArgError>()));
      final empty = _writeTempServers('[]');
      expect(
          () => loadServersFile(empty.path), throwsA(isA<McpollArgError>()));
    });
  });

  group('resolveToken', () {
    test('default env, per-host override, empty is open', () {
      const h = McpollHost(id: 'w', name: 'web', host: 'h');
      expect(
          resolveToken(h, {'MCP_AGENT_TOKEN': '  abc '}), 'abc');
      expect(resolveToken(h, {}), isNull);
      const tagged =
          McpollHost(id: 'w', name: 'web', host: 'h', tokenEnv: 'TOK_DB');
      expect(
          resolveToken(tagged, {'TOK_DB': 'x', 'MCP_AGENT_TOKEN': 'y'}), 'x');
    });
  });

  group('pure signal mapping', () {
    test('snapshot 82% disk fires an alert signal', () {
      final signals = signalsFromSnapshot('s1', 'web', {
        'disk': 0.82,
        'load1': 0.1,
        'nproc': 4,
        'uptime_s': 99999,
      });
      expect(signals.map((s) => s.displayTitle),
          contains('Disk 82% full on / (web)'));
      expect(signals.first.key, 'alert::web::Disk 82% full on /');
    });

    test('quiet snapshot stays silent', () {
      expect(
          signalsFromSnapshot('s1', 'web', {
            'disk': 0.1,
            'load1': 0.1,
            'nproc': 4,
            'uptime_s': 99999,
          }),
          isEmpty);
    });

    test('metrics gauges fire via frozen Thresholds', () {
      final signals = signalsFromMetricsSysstats(
        's1',
        'web',
        {'cpu': 0.96, 'ram': 0.5, 'disk': 0.1, 'uptime_days': 9},
        {'load1': 0.1, 'nproc': 4},
      );
      expect(signals.map((s) => s.displayTitle), contains('CPU 96% (web)'));
      expect(signals.where((s) => s.kind == 'gauge'), hasLength(1));
    });

    test('hostile metric maps never throw', () {
      expect(
          signalsFromMetricsSysstats('s1', 'web', {'cpu': 'hot'}, null),
          isEmpty);
      expect(signalsFromMetricsSysstats('s1', 'web', null, null), isEmpty);
    });
  });

  group('frozen reuse table (TM-1, verbatim)', () {
    test('rules / thresholds / policy are the frozen values', () {
      expect(HeadlessCheck.rules.diskWarnAt, 0.80);
      expect(HeadlessCheck.rules.diskCritAt, 0.90);
      expect(HeadlessCheck.thresholds.warnAt, 0.85);
      expect(HeadlessCheck.thresholds.critAt, 0.95);
      expect(HeadlessCheck.pollPolicy.baseInterval,
          const Duration(minutes: 5));
      expect(
          HeadlessCheck.pollPolicy.maxInterval, const Duration(hours: 1));
      expect(HeadlessCheck.notificationTitle, 'MyControlPanel alert');
      expect(HeadlessCheck.resendCooldown, const Duration(hours: 6));
    });
  });

  group('mcpoll scheduler examples (ADR-003 invariants)', () {
    test('windows task: per-user, no elevation, no credential material', () {
      final xml = _read('scripts/mcpoll/windows/mcp-poll-task.xml');
      expect(xml, contains('mcpoll'));
      expect(xml, contains('--consent'));
      expect(xml, contains('--servers'));
      expect(xml, isNot(contains('HighestAvailableAuthority')));
      expect(
          HeadlessSecurity.findSecretMaterialInArgs(xml.split('\n')), isEmpty);
      expect(
        HeadlessSecurity.validateSchedulerArtifact(
          kind: SchedulerKind.windowsTaskScheduler,
          perUserScope: true,
          runsElevated: false,
          args: const ['mcpoll.exe', '--consent', '--servers', 'servers.json'],
          invokesHeadlessFlag: true,
        ),
        isEmpty,
      );
    });

    test('systemd units: user scope, no Environment secrets', () {
      final service = _read('scripts/mcpoll/linux/mcp-poll.service');
      final timer = _read('scripts/mcpoll/linux/mcp-poll.timer');
      expect(service, contains('mcpoll --consent --servers'));
      expect(service, contains('Type=oneshot'));
      expect(service, isNot(contains('Environment=')));
      expect(timer, contains('OnUnitActiveSec=15min'));
      expect(
        HeadlessSecurity.findSecretMaterialInArgs(
            service.split('\n') + timer.split('\n')),
        isEmpty,
      );
    });

    test('macOS plist: LaunchAgent scope, 900s interval', () {
      final plist =
          _read('scripts/mcpoll/macos/com.mycontrolpanel.mcpoll.plist');
      expect(plist, contains('mcpoll'));
      expect(plist, contains('--consent'));
      expect(plist, contains('<integer>900</integer>'));
      expect(plist, isNot(contains('LaunchDaemon')));
      expect(
        HeadlessSecurity.findSecretMaterialInArgs(plist.split('\n')),
        isEmpty,
      );
    });

    test('manual scripts invoke mcpoll with no elevation or secrets', () {
      final ps1 = _read('scripts/mcpoll/install-windows.ps1');
      final sh = _read('scripts/mcpoll/install-linux.sh');
      final mac = _read('scripts/mcpoll/install-macos.sh');
      for (final s in [ps1, sh, mac]) {
        expect(s, contains('mcpoll'));
        expect(
          HeadlessSecurity.findSecretMaterialInArgs(s.split('\n')),
          isEmpty,
        );
      }
      expect(ps1.toLowerCase(), isNot(contains('runas')));
      bool invokes(String script, String tool) => script
          .split('\n')
          .where((l) => !l.trimLeft().startsWith('#'))
          .any((l) => RegExp('(^|\\s|;)$tool\\s').hasMatch(l));
      expect(invokes(sh, 'sudo'), isFalse);
      expect(invokes(mac, 'sudo'), isFalse);
    });
  });
}
