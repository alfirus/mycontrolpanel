// SPDX-License-Identifier: MIT
/// Policy unit tests for one-click host remediation ([HostFixes]).
/// Pure table: what each alert state offers, dry-run preview copy,
/// and the exact SSH command — shared by the alert UI and the AI tools.
import 'package:flutter_test/flutter_test.dart';
import 'package:my_control_panel/models/alert_entry.dart';
import 'package:my_control_panel/services/run_actions.dart';

AlertEntry alert(String title, String host,
        {String source = '', String severity = 'critical'}) =>
    AlertEntry(
      title: title,
      source: source.isEmpty ? 'src • $host' : '$source • $host',
      severity: severity,
      serverId: 's-$host',
      serverName: host,
    );

void main() {
  group('HostFixes.actionsFor', () {
    test('failed service offers restart', () {
      expect(
        HostFixes.actionsFor(alert('Service failed: nginx', 'web-01', source: 'systemd')),
        [HostFixAction.restartService],
      );
    });

    test('failed service with .service suffix still offers restart', () {
      final a = alert('Service failed: nginx.service', 'web-01', source: 'systemd');
      expect(HostFixes.unitFor(a), 'nginx');
      expect(HostFixes.actionsFor(a), [HostFixAction.restartService]);
    });

    test('service title with injected shell is offered nothing', () {
      expect(
        HostFixes.actionsFor(alert('Service failed: nginx; rm -rf /', 'web-01', source: 'systemd')),
        isEmpty,
      );
    });

    test('non-service titles offer no restart', () {
      expect(HostFixes.unitFor(alert('Disk 91% full on /', 'db-01', source: 'disk')), isNull);
    });

    test('disk alert offers prune + vacuum, in order', () {
      expect(
        HostFixes.actionsFor(alert('Disk 91% full on /', 'db-01', source: 'disk')),
        [HostFixAction.pruneDisk, HostFixAction.vacuumJournal],
      );
    });

    test('ml disk forecast offers prune + vacuum', () {
      expect(
        HostFixes.actionsFor(
            alert('Disk filling: ~30h to 90%', 'db-01', source: 'ml-pipeline/disk')),
        [HostFixAction.pruneDisk, HostFixAction.vacuumJournal],
      );
    });

    test('load alert offers clear-queue', () {
      expect(
        HostFixes.actionsFor(
            alert('Load average 9.2 on 4 CPUs (overloaded)', 'web-01', source: 'load')),
        [HostFixAction.clearQueue],
      );
    });

    test('load spike forecast offers clear-queue', () {
      expect(
        HostFixes.actionsFor(
            alert('Load spike on web-01 (1-min 8.10)', 'web-01', source: 'ml-pipeline/load')),
        [HostFixAction.clearQueue],
      );
    });

    test('oom kernel alert offers clear-queue', () {
      expect(
        HostFixes.actionsFor(alert(
            'Out-of-memory killer fired in last 24h', 'web-01', source: 'kernel')),
        [HostFixAction.clearQueue],
      );
    });

    test('unrelated alerts offer nothing', () {
      expect(
        HostFixes.actionsFor(alert('3 failed SSH logins in 24h', 'web-01', source: 'auth')),
        isEmpty,
      );
      expect(
        HostFixes.actionsFor(
            alert('Server rebooted 12m ago — unexpected restart?', 'web-01', source: 'uptime')),
        isEmpty,
      );
      expect(
        HostFixes.actionsFor(
            alert('4 kernel warnings in last 24h', 'web-01', source: 'kernel')),
        isEmpty,
      );
    });
  });

  group('HostFixes copy + commands', () {
    test('labels are short caps', () {
      expect(HostFixes.label(HostFixAction.restartService), 'RESTART');
      expect(HostFixes.label(HostFixAction.pruneDisk), 'PRUNE DISK');
      expect(HostFixes.label(HostFixAction.vacuumJournal), 'VACUUM LOGS');
      expect(HostFixes.label(HostFixAction.clearQueue), 'CLEAR QUEUE');
    });

    test('restart command embeds only the allowlisted unit', () {
      expect(HostFixes.commandFor(HostFixAction.restartService, unit: 'nginx'),
          'sudo systemctl restart nginx && sleep 1 && systemctl is-active nginx');
    });

    test('restart command rejects shell metacharacters', () {
      expect(() => HostFixes.commandFor(HostFixAction.restartService, unit: 'a;id'),
          throwsArgumentError);
      expect(() => HostFixes.commandFor(HostFixAction.restartService),
          throwsArgumentError);
    });

    test('disk/journal/queue commands are stdlib-only', () {
      final prune = HostFixes.commandFor(HostFixAction.pruneDisk);
      expect(prune, contains('df -h /'));
      final vacuum = HostFixes.commandFor(HostFixAction.vacuumJournal);
      expect(vacuum, contains('journalctl'));
      final queue = HostFixes.commandFor(HostFixAction.clearQueue);
      expect(queue, contains('systemctl reset-failed'));
      for (final cmd in [prune, vacuum, queue]) {
        expect(cmd, isNot(contains('curl')));
        expect(cmd, isNot(contains('wget')));
      }
    });

    test('confirm text is a dry-run preview naming host + exact command', () {
      final svc = alert('Service failed: nginx', 'web-01', source: 'systemd');
      final restart = HostFixes.confirmText(HostFixAction.restartService, svc);
      expect(restart, contains('web-01'));
      expect(restart, contains('Will run: sudo systemctl restart nginx'));

      final disk = alert('Disk 91% full on /', 'db-01', source: 'disk');
      final prune = HostFixes.confirmText(HostFixAction.pruneDisk, disk);
      expect(prune, contains('db-01'));
      expect(prune, contains('Will run: '));
      expect(prune, contains(HostFixes.commandFor(HostFixAction.pruneDisk)));
    });
  });
}
