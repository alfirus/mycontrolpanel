// SPDX-License-Identifier: MIT
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:my_control_panel/services/agent_operability.dart';
import 'package:my_control_panel/services/alert_reliability.dart';

void main() {
  group('parseLogLines', () {
    test('parses mixed delivery + tick + sample lines', () {
      const delivery = AlertDeliveryRecord(
        id: 'alert::web::disk',
        scheduledMs: 1000,
        executedMs: 1100,
        notifiedMs: 1200,
        transport: 'both',
      );
      final lines = [
        jsonEncode(delivery.toJson()),
        jsonEncode({'tickMs': 150.0, 'atMs': 1300}),
        jsonEncode({'memMb': 20.5, 'cpu': 0.1, 'battery': 0.8, 'atMs': 1300}),
      ];
      final log = parseLogLines(lines);
      expect(log.rows.single.id, 'alert::web::disk');
      expect(log.tickDurationsMs, [150.0]);
      expect(log.samples.single.memMb, 20.5);
      expect(log.samples.single.battery, 0.8);
      expect(log.isEmpty, isFalse);
    });

    test('hostile lines are skipped, never fatal', () {
      final log = parseLogLines([
        'not json at all',
        '{"tickMs": -5}',
        '{"memMb": "huge"}',
        '{}',
        '   ',
        '[1,2,3]',
      ]);
      expect(log.isEmpty, isTrue);
    });
  });

  group('buildCheckReport', () {
    test('empty log is no-data with exit 2', () {
      final report = buildCheckReport(
        log: parseLogLines([]),
        nowMs: 999,
        logPath: 'delivery.log',
        logBytes: 0,
      );
      expect(report.status, 'no-data');
      expect(report.exitCode, 2);
      expect(report.healthy, isFalse);
      expect(report.reason, isNotNull);
      expect(report.rotationDue, isFalse);
    });

    test('healthy window exits 0 with no reason', () {
      final lines = <String>[];
      for (var i = 0; i < 100; i++) {
        lines.add(jsonEncode(AlertDeliveryRecord(
          id: 's$i',
          scheduledMs: 0,
          executedMs: 100,
          notifiedMs: 60 * 1000,
        ).toJson()));
      }
      lines.add(jsonEncode({'tickMs': 120.0, 'atMs': 1}));
      lines.add(jsonEncode({'memMb': 20.0, 'atMs': 1}));
      final report = buildCheckReport(
        log: parseLogLines(lines),
        nowMs: 400 * 1000,
        logPath: 'delivery.log',
        logBytes: 1024,
      );
      expect(report.status, 'healthy');
      expect(report.exitCode, 0);
      expect(report.healthy, isTrue);
      expect(report.reason, isNull);
    });

    test('breach exits 1 and names the SLO', () {
      final lines = <String>[];
      for (var i = 0; i < 100; i++) {
        lines.add(jsonEncode(AlertDeliveryRecord(
          id: 's$i',
          scheduledMs: 0,
        ).toJson()));
      }
      final report = buildCheckReport(
        log: parseLogLines(lines),
        nowMs: 400 * 1000,
        logPath: 'delivery.log',
        logBytes: 1024,
      );
      expect(report.status, 'breach');
      expect(report.exitCode, 1);
      expect(report.reason, contains('drops'));
    });

    test('rotation flag follows the 512 KiB cap', () {
      final lines = [
        jsonEncode(const AlertDeliveryRecord(
          id: 's',
          scheduledMs: 0,
          notifiedMs: 1000,
        ).toJson()),
      ];
      final due = buildCheckReport(
        log: parseLogLines(lines),
        nowMs: 400 * 1000,
        logPath: 'delivery.log',
        logBytes: 512 * 1024,
      );
      expect(due.rotationDue, isTrue);
      final fresh = buildCheckReport(
        log: parseLogLines(lines),
        nowMs: 400 * 1000,
        logPath: 'delivery.log',
        logBytes: 10,
      );
      expect(fresh.rotationDue, isFalse);
    });

    test('report JSON carries titles and rates, never secrets', () {
      final lines = [
        jsonEncode(const AlertDeliveryRecord(
          id: 'alert::web::disk',
          scheduledMs: 0,
          notifiedMs: 1000,
        ).toJson()),
      ];
      final report = buildCheckReport(
        log: parseLogLines(lines),
        nowMs: 400 * 1000,
        logPath: 'delivery.log',
        logBytes: 10,
      );
      final json = report.toJson();
      expect(json['tool'], 'agent_check');
      expect(json['version'], 1);
      final text = jsonEncode(json);
      expect(text, isNot(contains('token')));
      expect(text, isNot(contains('secure:')));
      expect((json['slo'] as Map)['scheduled'], 1);
    });
  });
}
