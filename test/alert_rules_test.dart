import 'package:flutter_test/flutter_test.dart';
import 'package:my_control_panel/services/alert_rules.dart';

const rules = AlertRules();

void main() {
  group('AlertRules.evaluate', () {
    test('empty signals fire nothing', () {
      expect(rules.evaluate('s1', 'web-01', const HostSignals()), isEmpty);
    });

    test('disk warn at 80, critical at 90 (boundaries)', () {
      var out = rules.evaluate(
          's1', 'web-01', const HostSignals(diskByMount: {'/': 0.79}));
      expect(out, isEmpty);

      out = rules.evaluate(
          's1', 'web-01', const HostSignals(diskByMount: {'/': 0.80}));
      expect(out, hasLength(1));
      expect(out.single.severity, 'warning');
      expect(out.single.title, contains('80%'));
      expect(out.single.source, contains('disk'));

      out = rules.evaluate('s1', 'web-01',
          const HostSignals(diskByMount: {'/data': 0.93}));
      expect(out.single.severity, 'critical');
      expect(out.single.title, contains('/data'));
    });

    test('out-of-range ratios clamp without firing spuriously', () {
      final out = rules.evaluate(
          's1', 'web-01', const HostSignals(diskByMount: {'/': 9.9}));
      expect(out.single.severity, 'critical');
      expect(out.single.title, contains('100%'));
    });

    test('every failed unit is critical; blanks skipped', () {
      final out = rules.evaluate('s1', 'web-01',
          const HostSignals(failedUnits: ['nginx.service', '  ', 'cron']));
      expect(out, hasLength(2));
      expect(out.map((a) => a.severity).toSet(), {'critical'});
      expect(out.first.title, 'Service failed: nginx');
      expect(out.any((a) => a.source.startsWith('systemd')), isTrue);
    });

    test('brute-force warn at 5, critical at 20', () {
      expect(
          rules.evaluate(
              's1', 'web-01', const HostSignals(failedLogins24h: 4)),
          isEmpty);
      final warn = rules.evaluate(
          's1', 'web-01', const HostSignals(failedLogins24h: 5));
      expect(warn.single.severity, 'warning');
      final crit = rules.evaluate(
          's1', 'web-01', const HostSignals(failedLogins24h: 20));
      expect(crit.single.severity, 'critical');
      expect(crit.single.title, contains('brute force'));
    });

    test('load vs nproc: quiet at cap, warn above, critical past 2x', () {
      List<String> sevs(double load) => rules
          .evaluate('s1', 'web-01',
              HostSignals(load1: load, nproc: 4))
          .map((a) => a.severity)
          .toList();
      expect(sevs(4.0), isEmpty);
      expect(sevs(4.5), ['warning']);
      expect(sevs(8.0), ['warning']);
      expect(sevs(8.5), ['critical']);
    });

    test('unknown cpu count skips the load rule', () {
      expect(
          rules.evaluate('s1', 'web-01',
              const HostSignals(load1: 99, nproc: 0)),
          isEmpty);
    });

    test('OOM kernel line is critical, other lines warn', () {
      final oom = rules.evaluate('s1', 'web-01',
          const HostSignals(kernelLines: ['Out of memory: Killed process 1']));
      expect(oom.single.severity, 'critical');
      expect(oom.single.title, contains('Out-of-memory'));

      final warn = rules.evaluate('s1', 'web-01',
          const HostSignals(kernelLines: ['EXT4-fs error on sda1', '  ']));
      expect(warn.single.severity, 'warning');
      expect(warn.single.title, contains('1 kernel warnings'));
    });

    test('reboot tripwire: under 1h warns, at/over stays quiet', () {
      List<String> titles(int? up) => rules
          .evaluate('s1', 'web-01', HostSignals(uptimeSecs: up))
          .map((a) => a.title)
          .toList();
      expect(titles(null), isEmpty);
      expect(titles(3599), hasLength(1));
      expect(titles(3599).single, contains('unexpected restart'));
      expect(titles(3600), isEmpty);
    });

    test('a sick host fans out one entry per rule', () {
      final out = rules.evaluate(
        's1',
        'web-01',
        const HostSignals(
          diskByMount: {'/': 0.91},
          failedUnits: ['nginx.service'],
          failedLogins24h: 42,
          load1: 9,
          nproc: 4,
          kernelLines: ['oom-killer invoked'],
          uptimeSecs: 600,
        ),
      );
      expect(out, hasLength(6));
      expect(out.where((a) => a.severity == 'critical'), hasLength(4));
      expect(out.where((a) => a.severity == 'warning'), hasLength(2));
      expect(out.every((a) => a.serverId == 's1'), isTrue);
      expect(out.every((a) => a.source.contains('web-01')), isTrue);
    });
  });
}
