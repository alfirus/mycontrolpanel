import 'package:flutter_test/flutter_test.dart';
import 'package:my_control_panel/services/agent_service.dart';

void main() {
  group('agent v4 health+auth contract', () {
    test('agentVersion is 5', () {
      expect(AgentService.agentVersion, 5);
    });

    test('script declares AGENT_VERSION = 5', () {
      expect(AgentService.agentScript.contains('AGENT_VERSION = 5'), isTrue);
    });

    test('v2/v3 endpoints preserved (backward compatible)', () {
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

    test('/health liveness probe (no /proc scan)', () {
      final script = AgentService.agentScript;
      for (final needle in ['/health', "'status': 'ok'", 'agent_uptime_s']) {
        expect(script.contains(needle), isTrue, reason: 'missing $needle');
      }
    });

    test('optional token auth via MCP_AGENT_TOKEN env', () {
      final script = AgentService.agentScript;
      for (final needle in [
        'MCP_AGENT_TOKEN',
        'X-MCP-Agent-Token',
        '401',
        'compare_digest',
      ]) {
        expect(script.contains(needle), isTrue, reason: 'missing $needle');
      }
    });

    test('sysstats carries nproc + boot_epoch_s for load/reboot checks', () {
      final script = AgentService.agentScript;
      for (final needle in ['nproc', 'boot_epoch_s', 'read_nproc', 'read_boot_epoch_s']) {
        expect(script.contains(needle), isTrue, reason: 'missing $needle');
      }
    });

    test('hardened routing: query strings, JSON errors, 405 on non-GET', () {
      final script = AgentService.agentScript;
      for (final needle in [
        'urlsplit',
        'not_found',
        'method_not_allowed',
        'do_POST',
      ]) {
        expect(script.contains(needle), isTrue, reason: 'missing $needle');
      }
    });

    test('log endpoint with allowlisted sources', () {
      final script = AgentService.agentScript;
      for (final needle in [
        '/logs',
        'read_logs',
        'ALLOWED_LOG_SOURCES',
        'bad_source',
      ]) {
        expect(script.contains(needle), isTrue, reason: 'missing $needle');
      }
    });

    test('systemd unit supports the token env file', () {
      expect(AgentService.serviceUnit.contains('EnvironmentFile=-/etc/mcp-agent.env'), isTrue);
    });
  });
}
