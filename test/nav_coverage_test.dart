import 'package:flutter_test/flutter_test.dart';

import 'package:my_control_panel/screens/control_center_screen.dart'
    show overflowNavIndices, primaryNavIndices;

void main() {
  group('mobile nav coverage (spec 03 F3)', () {
    test('bottom nav keeps the five thumb-zone destinations', () {
      // Overview / Servers / GitHub / Deploys / Settings + AI + MORE.
      expect(primaryNavIndices, {0, 1, 4, 7, 11});
    });

    test('primary + MORE overflow cover all 13 destinations exactly once', () {
      final all = {...primaryNavIndices, ...overflowNavIndices};
      expect(all, {0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12});
      expect(primaryNavIndices.intersection(overflowNavIndices), isEmpty);
    });
  });
}
