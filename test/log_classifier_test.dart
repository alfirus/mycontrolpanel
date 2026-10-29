import 'package:flutter_test/flutter_test.dart';
import 'package:my_control_panel/services/log_classifier.dart';

void main() {
  group('LogClassifier', () {
    test('flags sshd brute force', () {
      final f = LogClassifier.classify(
        'sshd[4242]: Failed password for root from 45.9.8.7 port 512 ssh2',
      );
      expect(f.category, LogCategory.authBruteForce);
      expect(f.confidence, greaterThanOrEqualTo(0.9));
    });

    test('flags invalid-user probes', () {
      final f = LogClassifier.classify(
        'sshd[99]: Invalid user admin from 1.2.3.4 port 22',
      );
      expect(f.category, LogCategory.authBruteForce);
    });

    test('flags OOM kills as kernel issues', () {
      final f = LogClassifier.classify(
        'kernel: Out of memory: Killed process 4242 (mcp-agent) score 900',
      );
      expect(f.category, LogCategory.kernelIssue);
    });

    test('flags disk-full lines', () {
      final f = LogClassifier.classify(
        'app: write failed: No space left on device (/var/log/app.log)',
      );
      expect(f.category, LogCategory.diskError);
    });

    test('generic errors fall through to appError, not benign', () {
      final f = LogClassifier.classify(
        'worker-3: Exception in request handler: connection refused',
      );
      expect(f.category, LogCategory.appError);
      expect(f.isAlertable, isTrue);
    });

    test('routine lines stay benign', () {
      for (final line in [
        'nginx started, listening on 0.0.0.0:80',
        'systemd: Reached target Multi-User System.',
        'deploy ok: build 123 successful',
      ]) {
        expect(LogClassifier.classify(line).category, LogCategory.benign,
            reason: line);
      }
    });

    test('empty input never throws and is benign', () {
      expect(LogClassifier.classify('').category, LogCategory.benign);
    });
  });

  group('classifyBatch', () {
    test('aggregates counts and surfaces top alertables', () {
      final report = LogClassifier.classifyBatch([
        'sshd[1]: Failed password for root from 9.9.9.9 port 1 ssh2',
        'sshd[2]: Failed password for root from 9.9.9.9 port 2 ssh2',
        'kernel: Out of memory: Killed process 7 (x) score 1',
        'nginx started, listening on 0.0.0.0:80',
        'deploy ok',
      ]);
      expect(report.count(LogCategory.authBruteForce), 2);
      expect(report.count(LogCategory.kernelIssue), 1);
      expect(report.hasAlertable, isTrue);
      expect(report.topFindings.first.category, LogCategory.authBruteForce);
    });
  });
}
