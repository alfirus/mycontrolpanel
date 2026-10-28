import 'package:flutter_test/flutter_test.dart';
import 'package:my_control_panel/services/agent_protocol.dart';
import 'package:my_control_panel/services/agent_service.dart';
import 'package:my_control_panel/services/secure_store.dart';

void main() {
  group('agentTokenKey', () {
    test('namespaces per server, distinct from credential keys', () {
      expect(SecureStore.agentTokenKey('abc'), 'agent_tok_abc');
      expect(SecureStore.agentTokenKey('abc'),
          isNot(SecureStore.agentTokenKey('abd')));
      expect(SecureStore.agentTokenKey('abc'), isNot(contains('srv_cred_')));
    });
  });

  group('agentAuthHeaders', () {
    test('empty when no token (open agent)', () {
      expect(agentAuthHeaders(null), isEmpty);
      expect(agentAuthHeaders(''), isEmpty);
      expect(agentAuthHeaders('   '), isEmpty);
    });

    test('sends the token header, trimmed', () {
      final h = agentAuthHeaders('  tok123  ');
      expect(h, {kAgentAuthHeader: 'tok123'});
      expect(kAgentAuthHeader, 'X-MCP-Agent-Token');
    });
  });

  group('newAgentToken', () {
    test('256-bit base64url, unique per call', () {
      final seen = <String>{};
      final urlSafe = RegExp(r'^[A-Za-z0-9\-_]+$');
      for (var i = 0; i < 50; i++) {
        final t = AgentService.newAgentToken();
        expect(t.length, 43); // 32 bytes, no padding
        expect(urlSafe.hasMatch(t), isTrue);
        seen.add(t);
      }
      expect(seen, hasLength(50));
    });
  });
}
