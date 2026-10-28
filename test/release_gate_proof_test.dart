import 'package:flutter_test/flutter_test.dart';
import 'package:my_control_panel/models/alert_entry.dart';
import 'package:my_control_panel/services/agent_service.dart';
import 'package:my_control_panel/services/alert_rules.dart';
import 'package:my_control_panel/services/secret_hygiene.dart';

/// Release-gate proof pins (Burhanah, Release Verifier).
///
/// This file is the executable half of `docs/qa/release-gates.md`: it
/// re-asserts every binding gate threshold in one table-driven place so CI
/// itself produces the proof output — never pasted logs. If any threshold
/// below is relaxed without a matching gate-doc update + verifier sign-off,
/// this test goes red and the release gate stays HOLD.
///
/// Coverage map (gate G2 in the doc):
///   R1 disk warn >=80% / critical >=90% (per mount)
///   R2 every failed systemd unit fires critical; blanks skipped
///   R3 brute force: quiet <5, warn >=5, critical >=20 + label
///   R4 load: quiet at cap, warn above nproc, critical past 2x nproc
///   R5 kernel: OOM line critical, other err/warn lines warning
///   R6 reboot tripwire: uptime <1h warns, null/>=1h quiet
///   R7 credential audit: plaintext flagged, secure: refs + blanks clean
///   R8 agent install contract: port 9108, script + unit markers present
const _rules = AlertRules();

List<AlertEntryLite> _eval(HostSignals s) => _rules
    .evaluate('s1', 'web-01', s)
    .map((a) => AlertEntryLite(a.severity, a.title, a.source))
    .toList();

class AlertEntryLite {
  final String severity;
  final String title;
  final String source;
  const AlertEntryLite(this.severity, this.title, this.source);
}

void main() {
  group('release gate R1: disk thresholds per mount', () {
    test('79% quiet, 80% warning, 90% critical', () {
      expect(_eval(const HostSignals(diskByMount: {'/': 0.79})), isEmpty);
      final warn = _eval(const HostSignals(diskByMount: {'/': 0.80}));
      expect(warn, hasLength(1));
      expect(warn.single.severity, 'warning');
      expect(warn.single.source, contains('disk'));
      final crit = _eval(const HostSignals(diskByMount: {'/data': 0.90}));
      expect(crit.single.severity, 'critical');
      expect(crit.single.title, contains('/data'));
    });
  });

  group('release gate R2: failed systemd units', () {
    test('every unit critical, blanks skipped', () {
      final out = _eval(const HostSignals(
          failedUnits: ['nginx.service', '  ', 'cron.service']));
      expect(out, hasLength(2));
      expect(out.map((a) => a.severity).toSet(), {'critical'});
      expect(out.first.title, 'Service failed: nginx');
      expect(out.every((a) => a.source.startsWith('systemd')), isTrue);
    });

    test('no failed units fires nothing', () {
      expect(_eval(const HostSignals(failedUnits: [])), isEmpty);
    });
  });

  group('release gate R3: brute-force thresholds', () {
    test('4 quiet, 5 warning, 20 critical with label', () {
      expect(_eval(const HostSignals(failedLogins24h: 4)), isEmpty);
      final warn = _eval(const HostSignals(failedLogins24h: 5));
      expect(warn.single.severity, 'warning');
      final crit = _eval(const HostSignals(failedLogins24h: 20));
      expect(crit.single.severity, 'critical');
      expect(crit.single.title, contains('brute force'));
    });
  });

  group('release gate R4: load vs cpu count', () {
    test('at cap quiet, above warn, past 2x critical', () {
      List<String> sevs(double load) =>
          _eval(HostSignals(load1: load, nproc: 4))
              .map((a) => a.severity)
              .toList();
      expect(sevs(4.0), isEmpty);
      expect(sevs(4.5), ['warning']);
      expect(sevs(8.5), ['critical']);
    });

    test('unknown cpu count skips instead of guessing', () {
      expect(_eval(const HostSignals(load1: 99, nproc: 0)), isEmpty);
    });
  });

  group('release gate R5: kernel lines', () {
    test('OOM critical, other warnings warn', () {
      final oom = _eval(const HostSignals(
          kernelLines: ['Out of memory: Killed process 1']));
      expect(oom.single.severity, 'critical');
      final warn = _eval(
          const HostSignals(kernelLines: ['EXT4-fs error on sda1', '  ']));
      expect(warn.single.severity, 'warning');
    });
  });

  group('release gate R6: reboot tripwire', () {
    test('under 1h warns, null and >=1h stay quiet', () {
      List<String> titles(int? up) => _eval(HostSignals(uptimeSecs: up))
          .map((a) => a.title)
          .toList();
      expect(titles(null), isEmpty);
      expect(titles(3599), hasLength(1));
      expect(titles(3599).single, contains('restart'));
      expect(titles(3600), isEmpty);
    });
  });

  group('release gate R7: credential audit stays clean', () {
    test('plaintext flagged, secure refs and blanks clean', () {
      expect(
          SecretHygiene.findRawCredentials([
            {'id': 'a', 'credential': 'secure:srv_cred_a'},
            {'id': 'b', 'credential': 'plaintext-password'},
            {'id': 'c', 'credential': ''},
          ]),
          ['b']);
      expect(
          SecretHygiene.findRawCredentials([
            {'id': 'a', 'credential': 'secure:srv_cred_a'},
          ]),
          isEmpty);
    });
  });

  group('release gate R8: agent install contract', () {
    test('agent port is 9108 everywhere the gate assumes it', () {
      expect(AgentService.agentPort, 9108);
    });

    test('install script carries the read-back markers the gate requires', () {
      expect(AgentService.agentScript.contains('9108'), isTrue);
      expect(AgentService.serviceUnit.contains('9108'), isTrue);
      expect(AgentService.serviceUnit.contains('mcp-agent'), isTrue);
    });
  });
}
