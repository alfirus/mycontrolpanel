// SPDX-License-Identifier: MIT
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:my_control_panel/services/agent_service.dart';

/// Parity: the anomaly scorer deployed to /opt/mcp-agent/agent.py is the
/// exact text between the BEGIN/END markers in agent/anomaly_scorer.py
/// (canonical source, covered by agent/tests/test_anomaly_scorer.py +
/// test_anomaly_eval.py). If you change the scorer, edit the .py file and
/// re-vendor the block into AgentService.agentScript — this test fails
/// otherwise.
void main() {
  test('embedded agentScript vendors anomaly_scorer.py verbatim', () {
    const begin =
        '# BEGIN ANOMALY SCORER (vendored into AgentService.agentScript verbatim)';
    const end =
        '# END ANOMALY SCORER (vendored into AgentService.agentScript verbatim)';
    final src = File('agent/anomaly_scorer.py').readAsStringSync();
    final si = src.indexOf(begin);
    final ei = src.indexOf(end);
    expect(si, isNot(-1), reason: 'BEGIN marker missing in scorer');
    expect(ei, isNot(-1), reason: 'END marker missing in scorer');
    expect(ei, greaterThan(si));
    final block = src.substring(si, ei + end.length);
    expect(block.contains("'''"), isFalse,
        reason: 'triple-quote would break the Dart raw string');
    expect(block.contains('\$'), isFalse,
        reason: 'dollar would interpolate in the Dart string');
    expect(AgentService.agentScript.contains(block), isTrue,
        reason: 're-vendor agent/anomaly_scorer.py into agentScript');
  });

  test('embedded /anomaly endpoint preserves the query contract', () {
    const script = AgentService.agentScript;
    for (final needle in [
      "'/anomaly'",
      'score_sample',
      'SENSITIVITIES',
      'sensitivity',
      "'firing'",
      "'reason'",
    ]) {
      expect(script.contains(needle), isTrue, reason: 'missing $needle');
    }
  });
}
