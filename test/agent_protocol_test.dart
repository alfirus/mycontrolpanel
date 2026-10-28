import 'package:flutter_test/flutter_test.dart';
import 'package:my_control_panel/services/agent_protocol.dart';

void main() {
  group('parseAgentMetrics', () {
    test('accepts a valid v2 payload', () {
      final m = parseAgentMetrics({
        'cpu': 0.25,
        'ram': 0.5,
        'disk': 0.75,
        'uptime_days': 9,
        'version': 2,
      });
      expect(m.cpu, 0.25);
      expect(m.ram, 0.5);
      expect(m.disk, 0.75);
      expect(m.uptimeDays, 9);
      expect(m.agentVersion, 2);
    });

    test('clamps out-of-range ratios', () {
      final m = parseAgentMetrics({
        'cpu': 9.9,
        'ram': -1,
        'disk': 0.5,
        'uptime_days': 0,
        'version': 2,
      });
      expect(m.cpu, 1.0);
      expect(m.ram, 0.0);
    });

    test('missing version is staleAgent, not badPayload', () {
      expect(
        () => parseAgentMetrics(
            {'cpu': 0.1, 'ram': 0.1, 'disk': 0.1, 'uptime_days': 1}),
        throwsA(isA<AgentProtocolException>().having(
            (e) => e.code, 'code', AgentErrorCode.staleAgent)),
      );
    });

    test('version below floor is staleAgent', () {
      expect(
        () => parseAgentMetrics({
          'cpu': 0.1,
          'ram': 0.1,
          'disk': 0.1,
          'uptime_days': 1,
          'version': 1,
        }),
        throwsA(isA<AgentProtocolException>().having(
            (e) => e.code, 'code', AgentErrorCode.staleAgent)),
      );
    });

    test('non-numeric ratio is badPayload', () {
      expect(
        () => parseAgentMetrics({
          'cpu': 'hot',
          'ram': 0.1,
          'disk': 0.1,
          'uptime_days': 1,
          'version': 2,
        }),
        throwsA(isA<AgentProtocolException>().having(
            (e) => e.code, 'code', AgentErrorCode.badPayload)),
      );
    });
  });

  group('checkProcStatsSchema', () {
    test('accepts a valid v2 body', () {
      checkProcStatsSchema({
        'version': 2,
        'top': [
          {'pid': 1, 'name': 'systemd', 'cpu': 0.0, 'mem_mb': 12}
        ],
        'ports': {
          '3000': {'listening': true, 'established': 2}
        },
      });
    });

    test('missing top is badPayload', () {
      expect(
        () => checkProcStatsSchema({'version': 2, 'ports': {}}),
        throwsA(isA<AgentProtocolException>().having(
            (e) => e.code, 'code', AgentErrorCode.badPayload)),
      );
    });
  });

  group('agentHttpError', () {
    test('401 maps to unauthorized', () {
      expect(agentHttpError(401, '/metrics').code,
          AgentErrorCode.unauthorized);
    });

    test('404 maps to badPayload', () {
      expect(
          agentHttpError(404, '/nope').code, AgentErrorCode.badPayload);
    });

    test('405 maps to badPayload with GET hint', () {
      final e = agentHttpError(405, '/metrics');
      expect(e.code, AgentErrorCode.badPayload);
      expect(e.detail.contains('GET'), isTrue);
    });

    test('400 maps to badPayload with query hint', () {
      final e = agentHttpError(400, '/logs');
      expect(e.code, AgentErrorCode.badPayload);
      expect(e.detail.contains('query'), isTrue);
    });

    test('500 maps to badPayload', () {
      expect(agentHttpError(500, '/metrics').code,
          AgentErrorCode.badPayload);
    });
  });

  group('parseAgentHealth', () {
    test('accepts a valid v4 payload', () {
      final h = parseAgentHealth(
          {'status': 'ok', 'version': 4, 'agent_uptime_s': 3600});
      expect(h.agentVersion, 4);
      expect(h.agentUptimeS, 3600);
    });

    test('missing status is badPayload', () {
      expect(
        () => parseAgentHealth({'version': 4, 'agent_uptime_s': 1}),
        throwsA(isA<AgentProtocolException>().having(
            (e) => e.code, 'code', AgentErrorCode.badPayload)),
      );
    });

    test('non-ok status is badPayload', () {
      expect(
        () => parseAgentHealth(
            {'status': 'degraded', 'version': 4, 'agent_uptime_s': 1}),
        throwsA(isA<AgentProtocolException>().having(
            (e) => e.code, 'code', AgentErrorCode.badPayload)),
      );
    });

    test('missing version is staleAgent', () {
      expect(
        () => parseAgentHealth({'status': 'ok', 'agent_uptime_s': 1}),
        throwsA(isA<AgentProtocolException>().having(
            (e) => e.code, 'code', AgentErrorCode.staleAgent)),
      );
    });

    test('negative uptime is badPayload', () {
      expect(
        () => parseAgentHealth(
            {'status': 'ok', 'version': 4, 'agent_uptime_s': -1}),
        throwsA(isA<AgentProtocolException>().having(
            (e) => e.code, 'code', AgentErrorCode.badPayload)),
      );
    });
  });

  group('decodeAgentBody', () {
    test('rejects non-JSON', () {
      expect(
        () => decodeAgentBody('not json', '/metrics'),
        throwsA(isA<AgentProtocolException>().having(
            (e) => e.code, 'code', AgentErrorCode.badPayload)),
      );
    });

    test('rejects non-object JSON', () {
      expect(
        () => decodeAgentBody('[1,2]', '/metrics'),
        throwsA(isA<AgentProtocolException>().having(
            (e) => e.code, 'code', AgentErrorCode.badPayload)),
      );
    });
  });
}
