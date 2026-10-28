import 'package:flutter_test/flutter_test.dart';
import 'package:my_control_panel/models/mock_data.dart';
import 'package:my_control_panel/models/server_connection.dart';
import 'package:my_control_panel/services/agent_service.dart';
import 'package:my_control_panel/services/log_tail_service.dart';

LogLine line(String level, String message) => LogLine(
      time: DateTime.utc(2026, 10, 28),
      level: level,
      source: 'test',
      message: message,
    );

void main() {
  group('LogTailService.watch', () {
    test('yields the first snapshot', () async {
      final events = await LogTailService.watch(
        () async => [line('INFO', 'boot ok')],
        interval: const Duration(milliseconds: 1),
        maxPolls: 2,
      ).toList();
      expect(events, hasLength(1));
      expect(events.single.single.message, 'boot ok');
    });

    test('dedupes identical polls, yields on change', () async {
      var tick = 0;
      final events = await LogTailService.watch(
        () async {
          tick++;
          return tick < 3
              ? [line('INFO', 'steady')]
              : [line('ERROR', 'disk full')];
        },
        interval: const Duration(milliseconds: 1),
        maxPolls: 4,
      ).toList();
      expect(events, hasLength(2));
      expect(events[0].single.message, 'steady');
      expect(events[1].single.level, 'ERROR');
    });

    test('poll errors are swallowed, stream completes', () async {
      final events = await LogTailService.watch(
        () => throw Exception('ssh down'),
        interval: const Duration(milliseconds: 1),
        maxPolls: 3,
      ).toList();
      expect(events, isEmpty);
    });

    test('error then recovery yields the recovered snapshot', () async {
      var tick = 0;
      final events = await LogTailService.watch(
        () async {
          tick++;
          if (tick == 1) throw Exception('blip');
          return [line('INFO', 'back')];
        },
        interval: const Duration(milliseconds: 1),
        maxPolls: 3,
      ).toList();
      expect(events, hasLength(1));
      expect(events.single.single.message, 'back');
    });

    test('rejects unknown SSH sources fail-fast (no SSH attempted)', () {
      final server = ServerConnection(
        id: 's1',
        name: 'web-01',
        host: '127.0.0.1',
        port: 22,
        username: 'deploy',
        authMethod: AuthMethod.password,
        credential: 'x',
        region: 'test',
        os: 'Ubuntu 24.04',
        env: ServerEnv.dev,
        createdAt: DateTime.utc(2026, 1, 1),
      );
      expect(
        LogTailService().fetch(AgentService(), server, 'x',
            source: 'nope'),
        throwsA(isA<Exception>()),
      );
    });
  });
}
