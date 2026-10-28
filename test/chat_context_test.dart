import 'package:flutter_test/flutter_test.dart';
import 'package:my_control_panel/services/chat_context.dart';

void main() {
  group('ChatContextBuilder', () {
    test('builds a grounded block with servers, metrics, sections', () {
      final ctx = ChatContextBuilder.build(
        servers: const [
          {'id': 's1', 'name': 'prod-core-01', 'ip': '10.0.0.1', 'region': 'sg', 'status': 'online'},
        ],
        metrics: const {
          's1': {'cpu': 0.91, 'ram': 0.78, 'disk': 0.62, 'uptime_days': 17},
        },
        alerts: const ['CRITICAL disk 82% on / [critical]'],
        crons: const ['0 * * * * /opt/mcp-agent/hourly.sh'],
        apps: const ['nginx (active)'],
        recentLogs: const ['sshd Failed password for root — repeated'],
      );
      expect(ctx, contains('prod-core-01'));
      expect(ctx, contains('cpu=91%'));
      expect(ctx, contains('Never invent servers'));
      expect(ctx, contains('RECENT LOGS'));
    });

    test('caps output length', () {
      // Each section renders at most 10 items, so overflow needs LONG
      // items: 10 log lines x 800 chars each blows past the 6k ceiling.
      final big = List.generate(10, (i) => 'log line $i ' + 'x' * 800);
      final ctx = ChatContextBuilder.build(
        servers: List.generate(60, (i) => {'name': 'h$i', 'ip': 'x', 'region': 'r', 'status': 'online'}),
        metrics: const {},
        alerts: List.generate(60, (i) => 'alert number $i with a fairly long description text'),
        crons: const [],
        apps: const [],
        recentLogs: big,
      );
      expect(ctx.length, lessThanOrEqualTo(ChatContextBuilder.maxChars + 100));
      expect(ctx, contains('truncated'));
    });
  });

  group('ChatRetriever', () {
    test('finds the cpu culprit first', () {
      final hits = ChatRetriever.retrieve('which server has high cpu?', ChatEvalSet.docs);
      expect(hits, isNotEmpty);
      expect(hits.first.doc.server, 'prod-core-01');
    });

    test('empty query returns nothing', () {
      expect(ChatRetriever.retrieve('   ', ChatEvalSet.docs), isEmpty);
    });

    test('offline eval set meets the recall bar', () {
      expect(ChatEvalSet.recall(), greaterThanOrEqualTo(ChatEvalSet.minRecall));
    });
  });
}
