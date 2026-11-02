import 'package:flutter_test/flutter_test.dart';
import 'package:my_control_panel/services/anomaly_scoring.dart';

void main() {
  group('AnomalySensitivity', () {
    test('labels + query values mirror the agent contract', () {
      expect(AnomalySensitivity.low.label, 'Low');
      expect(AnomalySensitivity.medium.label, 'Medium');
      expect(AnomalySensitivity.high.label, 'High');
      expect(AnomalySensitivity.low.queryValue, 'low');
      expect(AnomalySensitivity.medium.queryValue, 'medium');
      expect(AnomalySensitivity.high.queryValue, 'high');
    });

    test('parse defaults to medium on unknown/null', () {
      expect(AnomalySensitivity.parse('low'), AnomalySensitivity.low);
      expect(AnomalySensitivity.parse('high'), AnomalySensitivity.high);
      expect(AnomalySensitivity.parse('medium'), AnomalySensitivity.medium);
      expect(AnomalySensitivity.parse('ultra'), AnomalySensitivity.medium);
      expect(AnomalySensitivity.parse(null), AnomalySensitivity.medium);
    });
  });

  group('AnomalyScore.parse', () {
    Map<String, dynamic> payload() => {
          'version': 6,
          'metric': 'cpu',
          'value': 0.87,
          'sensitivity': 'medium',
          'hour': 14,
          'score': 78.0,
          'reason': '0.87 vs usual 0.31 at 14:00 (score 78)',
          'firing': true,
          'z': 4.4,
          'baseline': 0.31,
        };

    test('parses a v6 payload', () {
      final s = AnomalyScore.parse(payload())!;
      expect(s.metric, 'cpu');
      expect(s.score, 78.0);
      expect(s.firing, isTrue);
      expect(s.sensitivity, AnomalySensitivity.medium);
      expect(s.reason, contains('usual'));
    });

    test('rejects pre-v6 payloads (caller falls back)', () {
      final p = payload()..['version'] = 5;
      expect(AnomalyScore.parse(p), isNull);
    });

    test('rejects bad shapes without throwing', () {
      expect(AnomalyScore.parse({}), isNull);
      expect(AnomalyScore.parse({'version': 6}), isNull);
      final p = payload()..['firing'] = 'yes';
      expect(AnomalyScore.parse(p), isNull);
    });

    test('clamps score to 0..100', () {
      final p = payload()..['score'] = 140.0;
      expect(AnomalyScore.parse(p)!.score, 100.0);
    });

    test('alertTitle carries metric + why-copy', () {
      final s = AnomalyScore.parse(payload())!;
      expect(s.alertTitle, contains('cpu'));
      expect(s.alertTitle, contains('87%'));
      expect(s.alertTitle, contains('Medium'));
    });
  });

  group('anomalyWhyCopy', () {
    test('agent-score form shows value vs baseline + magnitude', () {
      final copy = anomalyWhyCopy(
        metric: 'CPU',
        value: 0.87,
        baseline: 0.31,
        scoreText: 'score 78/100',
        sensitivity: AnomalySensitivity.medium,
        hourBasis: '14:00',
      );
      expect(copy, 'CPU 87% vs usual 31% at 14:00 · score 78/100 (Medium)');
    });

    test('omits the hour clause when no bucket basis', () {
      final copy = anomalyWhyCopy(
        metric: 'RAM',
        value: 0.5,
        baseline: 0.4,
        scoreText: 'score 3.9',
        sensitivity: AnomalySensitivity.high,
      );
      expect(copy, contains('RAM 50% vs usual 40%'));
      expect(copy.contains(' at '), isFalse);
      expect(copy, contains('(High)'));
    });

    test('clamps out-of-range ratios', () {
      final copy = anomalyWhyCopy(
        metric: 'CPU',
        value: 9.9,
        baseline: -0.2,
        scoreText: 'score 1.0',
        sensitivity: AnomalySensitivity.low,
      );
      expect(copy, contains('100%'));
      expect(copy, contains('0%'));
    });
  });

  group('privacy note', () {
    test('says fully on-device, nothing leaves', () {
      expect(anomalyPrivacyNote, contains('on-device'));
      expect(anomalyPrivacyNote, contains('Nothing leaves'));
    });
  });
}
