import 'package:flutter_test/flutter_test.dart';
import 'package:my_control_panel/models/cron_entry.dart';
import 'package:my_control_panel/services/agent_service.dart';
import 'package:my_control_panel/services/cron_run_tracker.dart';
import 'package:shared_preferences/shared_preferences.dart';

CronEntry entry(String command) => CronEntry(
      schedule: '0 * * * *',
      command: command,
      source: 'crontab',
      serverId: 's1',
      serverName: 'web-01',
    );

void main() {
  group('CronRunRecord.programOf', () {
    test('basenames the first token', () {
      expect(CronRunRecord.programOf('/usr/bin/backup --full'), 'backup');
      expect(CronRunRecord.programOf('/opt/mcp-agent/hourly.sh'), 'hourly.sh');
    });

    test('unwraps shell interpreters', () {
      expect(CronRunRecord.programOf("bash -lc '/opt/x/run.sh --fast'"), 'run.sh');
      expect(CronRunRecord.programOf('sh -c backup'), 'backup');
      expect(CronRunRecord.programOf('/usr/bin/env backup'), 'backup');
    });

    test('empty command has no program', () {
      expect(CronRunRecord.programOf('   '), isEmpty);
    });
  });

  group('CronRunRecord.fromAgent', () {
    test('parses epoch seconds + exit + duration', () {
      final r = CronRunRecord.fromAgent(
          {'at': 1793085600, 'name': 'backup', 'exit': 0, 'dur_s': 73});
      expect(r, isNotNull);
      expect(r!.name, 'backup');
      expect(r.exit, 0);
      expect(r.durSecs, 73);
      expect(r.status, CronRunStatus.ok);
      expect(
          r.ranAt!.millisecondsSinceEpoch, 1793085600 * 1000);
    });

    test('non-zero exit is an error', () {
      final r =
          CronRunRecord.fromAgent({'at': 1793085600, 'name': 'x', 'exit': 2});
      expect(r!.status, CronRunStatus.error);
    });

    test('hostile rows are skipped, never fatal', () {
      expect(CronRunRecord.fromAgent({}), isNull);
      expect(CronRunRecord.fromAgent({'name': '', 'at': 1}), isNull);
      expect(
          CronRunRecord.fromAgent({'name': 'x', 'at': 'soon', 'exit': 0}),
          isNull);
      expect(CronRunRecord.fromAgent({'name': 'x'} )!.status,
          CronRunStatus.unknown);
    });
  });

  group('CronRunRecord.formatDur', () {
    test('short/long/unknown durations', () {
      expect(CronRunRecord.formatDur(null), '—');
      expect(CronRunRecord.formatDur(12), '12s');
      expect(CronRunRecord.formatDur(184), '3m 4s');
      expect(CronRunRecord.formatDur(3720), '1h 2m');
    });
  });

  group('CronRunTracker.matchRecord', () {
    final runs = [
      const CronRunRecord(
          name: 'backup',
          ranAt: null,
          exit: null,
          source: 'agent'),
      CronRunRecord(
          name: 'backup',
          ranAt: DateTime(2026, 10, 27, 6),
          exit: 0,
          durSecs: 12),
      CronRunRecord(
          name: 'backup',
          ranAt: DateTime(2026, 10, 28, 6),
          exit: 1,
          durSecs: 3),
      CronRunRecord(
          name: 'purge', ranAt: DateTime(2026, 10, 28, 3), exit: 0),
    ];

    test('matches by program and picks the newest run', () {
      final m = CronRunTracker.matchRecord(runs, entry('/usr/bin/backup --full'));
      expect(m, isNotNull);
      expect(m!.exit, 1);
      expect(m.status, CronRunStatus.error);
    });

    test('no match returns null (screen shows SCHEDULED)', () {
      expect(CronRunTracker.matchRecord(runs, entry('/bin/nothing-here')), isNull);
    });

    test('empty program never matches', () {
      expect(CronRunTracker.matchRecord(runs, entry('   ')), isNull);
    });

    test('jobKey is stable across wrapper edits', () {
      expect(CronRunTracker.jobKey('s1', '/usr/bin/backup --full'),
          CronRunTracker.jobKey('s1', 'bash -lc backup'));
    });
  });

  group('CronRunTracker.parseAgentRuns', () {
    test('parses rows, drops hostile ones', () {
      final out = CronRunTracker.parseAgentRuns([
        {'at': 1793085600, 'name': 'a', 'exit': 0},
        {'bogus': true},
        'not-a-map',
        {'at': 1793085700, 'name': 'b', 'exit': 3, 'dur_s': 5},
      ]);
      expect(out.map((r) => r.name), ['a', 'b']);
    });
  });

  group('CronRunStore', () {
    test('round-trips last-good runs per host', () async {
      SharedPreferences.setMockInitialValues({});
      final runs = [
        CronRunRecord(
            name: 'backup',
            ranAt: DateTime(2026, 10, 28, 6),
            exit: 0,
            durSecs: 12),
      ];
      await CronRunStore.save('web-01', runs);
      final back = await CronRunStore.read('web-01');
      expect(back, hasLength(1));
      expect(back.single.name, 'backup');
      expect(back.single.source, 'cache');
      expect(back.single.durSecs, 12);
      expect(await CronRunStore.savedAt('web-01'), isNotNull);
      // Other hosts are isolated.
      expect(await CronRunStore.read('db-01'), isEmpty);
      expect(await CronRunStore.savedAt('db-01'), isNull);
    });

    test('corrupt cache reads as empty, never throws', () async {
      SharedPreferences.setMockInitialValues(
          {'cronruns_web-01': 'not json at all'});
      expect(await CronRunStore.read('web-01'), isEmpty);
    });
  });

  group('agent v5 contract', () {
    test('agentVersion is 5', () {
      expect(AgentService.agentVersion, 5);
    });

    test('script declares AGENT_VERSION = 5', () {
      expect(AgentService.agentScript.contains('AGENT_VERSION = 5'), isTrue);
    });

    test('script serves /cronruns from the run log', () {
      expect(AgentService.agentScript.contains("'/cronruns'"), isTrue);
      expect(AgentService.agentScript.contains('CRONRUNS_LOG'), isTrue);
      expect(AgentService.agentScript.contains('read_cronruns'), isTrue);
    });
  });
}
