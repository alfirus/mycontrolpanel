import 'package:flutter_test/flutter_test.dart';
import 'package:my_control_panel/services/log_tail_service.dart';
import 'package:my_control_panel/services/metrics_history.dart';

/// QA MOCK-vs-real pins (Balqis): the real-path helpers behind Log Tail +
/// Metrics p95. Pure logic — no SSH, no plugins, safe for CI.
/// These tests lock the verified-real behavior from docs/qa/mock-vs-real-gap-report.md.
void main() {
  group('LogTailService.parse (real SSH log path)', () {
    test('strips the [exit N] header line', () {
      final lines = LogTailService.parse(
        '[exit 0]\nOct 28 journald: started\nOct 28 app: ok\n',
      );
      expect(lines, hasLength(2));
      expect(lines.any((l) => l.message.contains('[exit')), isFalse);
    });

    test('skips blank lines and bare [stderr] markers', () {
      final lines = LogTailService.parse('line one\n\n[stderr]\nline two\n');
      expect(lines.map((l) => l.message), containsAll(['line one', 'line two']));
      expect(lines, hasLength(2));
    });

    test('guesses levels: error/warn/debug/info', () {
      final lines = LogTailService.parse(
        'connection ERROR timeout\nretry WARN limit\ngot DEBUG trace\nall systems normal\n',
      );
      final byMsg = {for (final l in lines) l.message: l.level};
      expect(byMsg['connection ERROR timeout'], 'ERROR');
      expect(byMsg['retry WARN limit'], 'WARN');
      expect(byMsg['got DEBUG trace'], 'DEBUG');
      expect(byMsg['all systems normal'], 'INFO');
    });

    test('flags failures, denials, and exceptions as ERROR', () {
      final lines = LogTailService.parse(
        'Failed password for root\nPermission denied\nNullPointerException boom\n',
      );
      expect(lines.map((l) => l.level).toSet(), {'ERROR'});
    });

    test('truncates very long lines at 300 chars', () {
      final long = 'x' * 400;
      final lines = LogTailService.parse('$long\n');
      expect(lines, hasLength(1));
      expect(lines.first.message.length, lessThanOrEqualTo(302));
    });

    test('never throws on garbage input', () {
      expect(() => LogTailService.parse('\n\x00\xff\n   \n'), returnsNormally);
    });

    test('uses the fallback source label', () {
      final lines = LogTailService.parse('hello\n', fallbackSource: 'prod-core-01');
      expect(lines.first.source, 'prod-core-01');
    });
  });

  group('MetricsHistory.p95 (real latency KPI)', () {
    test('returns null when empty', () {
      expect(MetricsHistory.p95(const []), isNull);
    });

    test('single sample returns that sample', () {
      expect(MetricsHistory.p95(const [12.0]), 12.0);
    });

    test('computes the 95th percentile of 1..100', () {
      final values = List.generate(100, (i) => (i + 1).toDouble());
      expect(MetricsHistory.p95(values), 95.0);
    });

    test('sorts unsorted input first', () {
      expect(MetricsHistory.p95(const [50.0, 10.0, 90.0, 30.0, 70.0]), 90.0);
    });

    test('small series: ceil behavior', () {
      // n=20 → ceil(19.0)-1 = 18 → max value
      final values = List.generate(20, (i) => (i + 1).toDouble());
      expect(MetricsHistory.p95(values), 20.0);
    });
  });

  group('MetricsHistory.formatMs', () {
    test('null renders as em dash', () {
      expect(MetricsHistory.formatMs(null), '—');
    });

    test('sub-second renders as ms', () {
      expect(MetricsHistory.formatMs(48.4), '48ms');
    });

    test('seconds render as s with 2 decimals', () {
      expect(MetricsHistory.formatMs(1500.0), '1.50s');
    });
  });
}
