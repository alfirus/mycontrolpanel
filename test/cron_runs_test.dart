import 'package:flutter_test/flutter_test.dart';
import 'package:my_control_panel/services/cron_runs.dart';

void main() {
  final now = DateTime(2026, 10, 28, 12, 0);

  group('CronRuns.parse', () {
    test('finds the newest syslog CRON execution', () {
      const log = '''Oct 28 06:20:01 web CRON[101]: (root) CMD (/opt/billing-sync --run)
Oct 28 06:30:01 web CRON[102]: (root) CMD (/opt/billing-sync --run)
Oct 28 06:30:02 web CRON[103]: (root) CMD (/usr/bin/other --x)''';
      final r = CronRuns.parse(
          command: '/opt/billing-sync --run', logText: log, now: now);
      expect(r.known, isTrue);
      expect(r.ranAt, DateTime(2026, 10, 28, 6, 30, 1));
      expect(r.status, CronRunStatus.ok);
    });

    test('matches ISO/journal timestamps', () {
      const log =
          '2026-10-28T05:15:00 web CRON[9]: (deploy) CMD (/srv/report-daily)';
      final r = CronRuns.parse(
          command: '/srv/report-daily', logText: log, now: now);
      expect(r.ranAt, DateTime(2026, 10, 28, 5, 15, 0));
    });

    test('unwraps bash -lc wrappers to the real program', () {
      const log =
          'Oct 28 06:30:01 web CRON[7]: (root) CMD (bash -lc /opt/health-ping.sh)';
      final r = CronRuns.parse(
          command: 'bash -lc /opt/health-ping.sh', logText: log, now: now);
      expect(r.known, isTrue);
    });

    test('flags failed executions', () {
      const log =
          'Oct 28 06:30:01 web CRON[7]: (root) CMD (/opt/purge-sessions) failed: permission denied';
      final r = CronRuns.parse(
          command: '/opt/purge-sessions', logText: log, now: now);
      expect(r.status, CronRunStatus.error);
    });

    test('adopts the agent [exit N] marker', () {
      const log =
          '[exit 2]\nOct 28 06:30:01 web CRON[7]: (root) CMD (/opt/purge-sessions) failed: exit 1';
      final r = CronRuns.parse(
          command: '/opt/purge-sessions', logText: log, now: now);
      expect(r.exitCode, 2);
    });

    test('unknown when no lines match the job', () {
      const log = 'Oct 28 06:30:01 web CRON[7]: (root) CMD (/bin/unrelated)';
      final r = CronRuns.parse(
          command: '/opt/billing-sync', logText: log, now: now);
      expect(r.known, isFalse);
      expect(r.status, CronRunStatus.unknown);
    });

    test('never throws on garbage input', () {
      expect(
          () => CronRuns.parse(command: '', logText: '\n\x00\xff\n   '),
          returnsNormally);
      expect(
          () => CronRuns.parse(command: 'x', logText: ''),
          returnsNormally);
    });

    test('December log read in January rolls back a year', () {
      const log =
          'Dec 31 23:59:01 web CRON[7]: (root) CMD (/opt/yearly-roll)';
      final r = CronRuns.parse(
          command: '/opt/yearly-roll',
          logText: log,
          now: DateTime(2026, 1, 2, 1));
      expect(r.ranAt?.year, 2025);
    });
  });

  group('CronLastRun.caption', () {
    test('same-day runs read as today', () {
      const r = CronLastRun(
          ranAt: null, status: CronRunStatus.unknown);
      expect(r.caption(now), contains('unknown'));
      final ok = CronLastRun(
          ranAt: DateTime(2026, 10, 28, 6, 30), status: CronRunStatus.ok);
      expect(ok.caption(now), 'last run 06:30 today ✓');
      final err = CronLastRun(
          ranAt: DateTime(2026, 10, 27, 6, 30),
          status: CronRunStatus.error,
          exitCode: 1);
      expect(err.caption(now), 'last run Oct 27 06:30 ✗ (exit 1)');
    });
  });
}
