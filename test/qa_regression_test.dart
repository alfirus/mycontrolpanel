import 'package:flutter_test/flutter_test.dart';
import 'package:my_control_panel/models/alert_entry.dart';
import 'package:my_control_panel/models/cron_entry.dart';
import 'package:my_control_panel/models/mock_data.dart';
import 'package:my_control_panel/services/alert_watch.dart';

/// QA regression coverage (Balqis): Alerts watcher diff + cron discovery
/// edges. Pure logic — no SSH, no plugins, safe for CI.
void main() {
  group('CronEntry.parse user crontab (no user field)', () {
    test('parses a basic 5-field line', () {
      final entries = CronEntry.parse(
        output: '0 * * * * /opt/mcp-agent/hourly.sh\n',
        source: 'crontab',
        hasUserField: false,
        serverId: 's1',
        serverName: 'host1',
      );
      expect(entries, hasLength(1));
      expect(entries.first.schedule, '0 * * * *');
      expect(entries.first.command, '/opt/mcp-agent/hourly.sh');
      expect(entries.first.source, 'crontab');
      expect(entries.first.rawLine, isNotEmpty);
    });

    test('accepts step values like */5', () {
      final entries = CronEntry.parse(
        output: '*/5 * * * * /usr/bin/health-ping\n',
        source: 'crontab',
        hasUserField: false,
        serverId: 's1',
        serverName: 'host1',
      );
      expect(entries, hasLength(1));
      expect(entries.first.schedule, '*/5 * * * *');
    });

    test('skips comments, blanks, env assignments, malformed lines', () {
      final entries = CronEntry.parse(
        output: '# nightly jobs\n\nPATH=/usr/bin:/bin\n'
            'MAILTO=ops@example.com\n'
            'not a cron line\n'
            '0 2 * * * /opt/backup.sh\n',
        source: 'crontab',
        hasUserField: false,
        serverId: 's1',
        serverName: 'host1',
      );
      expect(entries, hasLength(1));
      expect(entries.first.command, '/opt/backup.sh');
    });

    test('empty output yields no entries', () {
      final entries = CronEntry.parse(
        output: '',
        source: 'crontab',
        hasUserField: false,
        serverId: 's1',
        serverName: 'host1',
      );
      expect(entries, isEmpty);
    });
  });

  group('CronEntry.parse system files (user field)', () {
    test('strips the user field from /etc/crontab lines', () {
      final entries = CronEntry.parse(
        output: '17 * * * * root cd / && run-parts --report /etc/cron.hourly\n',
        source: '/etc/crontab',
        hasUserField: true,
        serverId: 's1',
        serverName: 'host1',
      );
      expect(entries, hasLength(1));
      expect(entries.first.schedule, '17 * * * *');
      expect(entries.first.command, 'cd / && run-parts --report /etc/cron.hourly');
    });

    test('parses @reboot with and without a user field', () {
      final plain = CronEntry.parse(
        output: '@reboot /opt/mcp-agent/start.sh\n',
        source: 'crontab',
        hasUserField: false,
        serverId: 's1',
        serverName: 'host1',
      );
      expect(plain, hasLength(1));
      expect(plain.first.schedule, '@reboot');
      expect(plain.first.command, '/opt/mcp-agent/start.sh');

      final withUser = CronEntry.parse(
        output: '@daily root /opt/mcp-agent/daily.sh\n',
        source: '/etc/cron.d/agent',
        hasUserField: true,
        serverId: 's1',
        serverName: 'host1',
      );
      expect(withUser, hasLength(1));
      expect(withUser.first.command, '/opt/mcp-agent/daily.sh');
    });
  });

  group('AlertWatch.currentKeys', () {
    AlertEntry alert(String title, {String status = 'firing'}) => AlertEntry(
          title: title,
          source: 'disk • host1',
          severity: 'warning',
          serverId: 's1',
          serverName: 'host1',
          status: status,
        );

    test('badges firing alerts only', () {
      final keys = AlertWatch.currentKeys(
        [alert('Disk 82% full on /'), alert('old one', status: 'resolved')],
        const [],
      );
      expect(keys, hasLength(1));
      expect(keys.single, contains('Disk 82% full on /'));
    });

    test('badges failed CI runs', () {
      final runs = [
        DeployItem(
            app: 'api-gateway',
            version: 'v2.14.3',
            env: 'prod',
            actor: 'ci',
            time: DateTime(2026, 10, 1),
            status: 'failed',
            duration: '3m'),
        DeployItem(
            app: 'web',
            version: 'v1.0',
            env: 'prod',
            actor: 'ci',
            time: DateTime(2026, 10, 1),
            status: 'success',
            duration: '1m'),
      ];
      final keys = AlertWatch.currentKeys(const [], runs);
      expect(keys, hasLength(1));
      expect(keys.single, contains('api-gateway'));
    });

    test('empty inputs yield an empty badge set', () {
      expect(AlertWatch.currentKeys(const [], const []), isEmpty);
    });
  });

  group('AlertWatch.freshTitles', () {
    test('reports only newly-appeared titles, capped at 3', () {
      final alerts = [
        for (var i = 0; i < 5; i++)
          AlertEntry(
            title: 'alert $i',
            source: 'disk • host1',
            severity: 'warning',
            serverId: 's1',
            serverName: 'host1',
          ),
      ];
      final current = AlertWatch.currentKeys(alerts, const []);
      final fresh = AlertWatch.freshTitles(current, <String>{}, alerts, const []);
      expect(fresh, hasLength(3));
    });

    test('seen keys are not reported again', () {
      final alerts = [
        AlertEntry(
          title: 'Disk 82% full on /',
          source: 'disk • host1',
          severity: 'warning',
          serverId: 's1',
          serverName: 'host1',
        ),
      ];
      final current = AlertWatch.currentKeys(alerts, const []);
      final fresh = AlertWatch.freshTitles(current, Set.of(current), alerts, const []);
      expect(fresh, isEmpty);
    });
  });
}
