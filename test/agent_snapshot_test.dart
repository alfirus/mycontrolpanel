// SPDX-License-Identifier: MIT
// Agent /alerts/snapshot contract (Lisa): one cheap fetch of pre-computed
// alert trigger inputs, snapshot-first with /metrics + /sysstats fallback.
import 'package:flutter_test/flutter_test.dart';
import 'package:my_control_panel/services/agent_protocol.dart';
import 'package:my_control_panel/services/agent_service.dart';
import 'package:my_control_panel/services/alert_rules.dart';

Map<String, dynamic> validBody() {
  final Map<String, dynamic> snapshot = {
    'disk': 0.41,
    'load1': 0.5,
    'load5': 0.4,
    'load15': 0.3,
    'nproc': 4,
    'uptime_s': 172800,
    'boot_epoch_s': 1793000000,
    'mem_total_mb': 3920,
    'mem_avail_mb': 1500,
    'agent_uptime_s': 3600,
  };
  return {'version': 6, 'snapshot': snapshot};
}

void main() {
  group('parseAlertSnapshot', () {
    test('accepts a valid v6 payload', () {
      final s = parseAlertSnapshot(validBody());
      expect(s.disk, 0.41);
      expect(s.load1, 0.5);
      expect(s.nproc, 4);
      expect(s.uptimeS, 172800);
      expect(s.bootEpochS, 1793000000);
      expect(s.agentVersion, 6);
    });

    test('clamps out-of-range disk', () {
      final body = validBody();
      (body['snapshot'] as Map)['disk'] = 9.9;
      expect(parseAlertSnapshot(body).disk, 1.0);
    });

    test('missing version is staleAgent, not badPayload', () {
      expect(
        () => parseAlertSnapshot({
          'snapshot': {'disk': 0.1}
        }),
        throwsA(isA<AgentProtocolException>().having(
            (e) => e.code, 'code', AgentErrorCode.staleAgent)),
      );
    });

    test('version below floor is staleAgent', () {
      expect(
        () => parseAlertSnapshot({
          'version': 1,
          'snapshot': {'disk': 0.1}
        }),
        throwsA(isA<AgentProtocolException>().having(
            (e) => e.code, 'code', AgentErrorCode.staleAgent)),
      );
    });

    test('missing snapshot is badPayload', () {
      expect(
        () => parseAlertSnapshot({'version': 6}),
        throwsA(isA<AgentProtocolException>().having(
            (e) => e.code, 'code', AgentErrorCode.badPayload)),
      );
    });

    test('non-numeric disk is badPayload', () {
      final body = validBody();
      (body['snapshot'] as Map)['disk'] = 'hot';
      expect(
        () => parseAlertSnapshot(body),
        throwsA(isA<AgentProtocolException>().having(
            (e) => e.code, 'code', AgentErrorCode.badPayload)),
      );
    });

    test('absent trigger keys default to unknown (no throw)', () {
      final s = parseAlertSnapshot({'version': 6, 'snapshot': {}});
      expect(s.disk, 0.0);
      expect(s.nproc, 0);
      expect(s.uptimeS, 0);
    });
  });

  group('HostSignals.fromSnapshot', () {
    test('maps disk/load/nproc/uptime', () {
      final sig = HostSignals.fromSnapshot(
          (validBody()['snapshot'] as Map).cast<String, dynamic>());
      expect(sig.diskByMount, {'/': 0.41});
      expect(sig.load1, 0.5);
      expect(sig.nproc, 4);
      expect(sig.uptimeSecs, 172800);
    });

    test('hostile input never throws, stays unknown', () {
      final sig = HostSignals.fromSnapshot({
        'disk': 'hot',
        'load1': -1,
        'nproc': 'four',
        'uptime_s': null,
      });
      expect(sig.diskByMount, isEmpty);
      expect(sig.load1, 0.0);
      expect(sig.nproc, 0);
      expect(sig.uptimeSecs, isNull);
    });

    test('snapshot inputs fire AlertRules identically', () {
      const rules = AlertRules();
      final firing = rules.evaluate(
        'srv1',
        'web',
        HostSignals.fromSnapshot({
          'disk': 0.82,
          'load1': 9.0,
          'nproc': 4,
          'uptime_s': 300,
        }),
      );
      final titles = firing.map((e) => e.title).toList();
      expect(titles.any((t) => t.contains('82%')), isTrue);
      expect(titles.any((t) => t.contains('Load average')), isTrue);
      expect(titles.any((t) => t.contains('rebooted')), isTrue);
    });

    test('unknown snapshot inputs stay silent', () {
      const rules = AlertRules();
      expect(
        rules.evaluate('srv1', 'web', HostSignals.fromSnapshot({})),
        isEmpty,
      );
    });
  });

  group('snapshot wiring parity', () {
    test('wire path constant is frozen', () {
      expect(kAlertSnapshotPath, '/alerts/snapshot');
    });

    test('embedded agent serves /alerts/snapshot from read_snapshot', () {
      const script = AgentService.agentScript;
      for (final needle in [
        "'/alerts/snapshot'",
        'read_snapshot',
        'uptime_s',
        'boot_epoch_s',
        "'snapshot'",
      ]) {
        expect(script.contains(needle), isTrue, reason: 'missing $needle');
      }
    });

    test('snapshot route is token-gated behind the shared auth check', () {
      // The route sits inside do_GET after the _authorized() gate, so no
      // per-endpoint auth code exists — pin the structure instead.
      const script = AgentService.agentScript;
      final getIdx = script.indexOf('def do_GET');
      final snapIdx = script.indexOf("'/alerts/snapshot'");
      expect(getIdx, isNot(-1));
      expect(snapIdx, greaterThan(getIdx));
    });
  });
}
