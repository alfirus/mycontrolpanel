import 'package:flutter_test/flutter_test.dart';
import 'package:my_control_panel/services/agent_service.dart';

void main() {
  group('agent v3 sysstats contract', () {
    test('agentVersion is 3', () {
      expect(AgentService.agentVersion, 3);
    });

    test('script declares AGENT_VERSION = 3', () {
      expect(AgentService.agentScript.contains('AGENT_VERSION = 3'), isTrue);
    });

    test('v2 endpoints preserved (backward compatible)', () {
      expect(AgentService.agentScript.contains('/metrics'), isTrue);
      expect(AgentService.agentScript.contains('/procstats'), isTrue);
      expect(AgentService.agentScript.contains('read_top_processes'), isTrue);
      expect(AgentService.agentScript.contains('read_ports'), isTrue);
    });

    test('sysstats endpoint with load/mem/gpu/uptime signals', () {
      for (final needle in [
        '/sysstats',
        'read_loadavg',
        'read_mem_detail',
        'read_gpu',
        'agent_uptime_s',
        'load1',
        'load5',
        'load15',
      ]) {
        expect(AgentService.agentScript.contains(needle), isTrue,
            reason: 'missing $needle');
      }
    });

    test('/metrics carries additive load1 without dropping v2 keys', () {
      final script = AgentService.agentScript;
      for (final needle in ['read_cpu', 'read_ram', 'read_disk', 'uptime_days', 'load1']) {
        expect(script.contains(needle), isTrue, reason: 'missing $needle');
      }
    });
  });
}
