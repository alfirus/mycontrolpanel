// SPDX-License-Identifier: MIT
import 'package:flutter_test/flutter_test.dart';
import 'package:my_control_panel/services/alert_log_rotation.dart';

void main() {
  group('AlertLogRotation', () {
    test('rotation trips at exactly the cap', () {
      expect(AlertLogRotation.rotationDue(0), isFalse);
      expect(
        AlertLogRotation.rotationDue(AlertLogRotation.maxBytes - 1),
        isFalse,
      );
      expect(
        AlertLogRotation.rotationDue(AlertLogRotation.maxBytes),
        isTrue,
      );
      expect(
        AlertLogRotation.rotationDue(AlertLogRotation.maxBytes + 1),
        isTrue,
      );
    });

    test('cap is 512 KiB with base + 2 generations', () {
      expect(AlertLogRotation.maxBytes, 512 * 1024);
      expect(AlertLogRotation.generations, 2);
      expect(AlertLogRotation.baseName, 'delivery.log');
    });

    test('generation paths and live set', () {
      expect(AlertLogRotation.generationPath('delivery.log', 0), 'delivery.log');
      expect(
        AlertLogRotation.generationPath('delivery.log', 1),
        'delivery.log.1',
      );
      expect(
        AlertLogRotation.generationPath('delivery.log', 2),
        'delivery.log.2',
      );
      expect(
        AlertLogRotation.livePaths('delivery.log'),
        ['delivery.log', 'delivery.log.1', 'delivery.log.2'],
      );
    });

    test('prune keeps gens 1..N, drops older, never the live log', () {
      expect(AlertLogRotation.pruneAbove({0, 1, 2}), isEmpty);
      expect(AlertLogRotation.pruneAbove({0, 1, 2, 3, 4}), [3, 4]);
      expect(AlertLogRotation.pruneAbove({5}), [5]);
    });

    test('generationOf round-trips live paths', () {
      const base = '/tmp/x/delivery.log';
      expect(AlertLogRotation.generationOf(base, base), 0);
      expect(
        AlertLogRotation.generationOf(base, '$base.1'),
        1,
      );
      expect(
        AlertLogRotation.generationOf(base, '$base.2'),
        2,
      );
      expect(AlertLogRotation.generationOf(base, '$base.3'), 3);
      expect(AlertLogRotation.generationOf(base, '$base.0'), isNull);
      expect(AlertLogRotation.generationOf(base, '$base.x'), isNull);
      expect(AlertLogRotation.generationOf(base, '/other/delivery.log'), isNull);
      expect(AlertLogRotation.generationOf(base, '$base.123'), isNull);
    });
  });
}
