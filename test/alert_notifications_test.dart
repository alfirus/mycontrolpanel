import 'package:flutter_test/flutter_test.dart';
import 'package:my_control_panel/services/alert_notifications.dart';

void main() {
  group('AlertNotifications.buildSummary', () {
    test('single title shows verbatim under the app banner', () {
      final s = AlertNotifications.buildSummary(['CI failed: api #42']);
      expect(s.title, 'MyControlPanel alert');
      expect(s.body, 'CI failed: api #42');
    });

    test('several titles fold into a count + preview', () {
      final s = AlertNotifications.buildSummary(['a', 'b', 'c', 'd']);
      expect(s.title, '4 new alerts');
      expect(s.body, 'a\nb\nc');
    });

    test('blank titles are ignored', () {
      final s =
          AlertNotifications.buildSummary(['  ', '', 'real alert']);
      expect(s.title, 'MyControlPanel alert');
      expect(s.body, 'real alert');
    });

    test('empty list yields an empty-count banner', () {
      final s = AlertNotifications.buildSummary([]);
      expect(s.title, '0 new alerts');
      expect(s.body, isEmpty);
    });
  });

  group('AlertNotifications.shouldNotify', () {
    test('fires when enabled with fresh titles', () {
      expect(
          AlertNotifications.shouldNotify(
              enabled: true, freshTitles: ['boom']),
          isTrue);
    });

    test('silent when the user opted out', () {
      expect(
          AlertNotifications.shouldNotify(
              enabled: false, freshTitles: ['boom']),
          isFalse);
    });

    test('silent with no fresh titles', () {
      expect(
          AlertNotifications.shouldNotify(
              enabled: true, freshTitles: []),
          isFalse);
    });

    test('silent when titles are all blank', () {
      expect(
          AlertNotifications.shouldNotify(
              enabled: true, freshTitles: ['  ']),
          isFalse);
    });
  });
}
