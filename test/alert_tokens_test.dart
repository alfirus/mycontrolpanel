import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_control_panel/theme/alert_tokens.dart';
import 'package:my_control_panel/theme/app_theme.dart';
import 'dart:math' as math;

/// Kira UX contract: severity tokens, copy tone, grouping, quiet-hours,
/// notification actions, and the a11y bar. Nurul's inbox builds on these.
void main() {
  double luminance(Color c) {
    double chan(double v) {
      return v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
    }

    return 0.2126 * chan(c.r) + 0.7152 * chan(c.g) + 0.0722 * chan(c.b);
  }

  double contrast(Color a, Color b) {
    final l1 = luminance(a);
    final l2 = luminance(b);
    final hi = l1 > l2 ? l1 : l2;
    final lo = l1 > l2 ? l2 : l1;
    return (hi + 0.05) / (lo + 0.05);
  }

  group('severity tokens (status set only, AA on surface0)', () {
    test('every severity has color + icon + pill + semantic label', () {
      for (final s in TrayAlertSeverity.values) {
        expect(AppAlertTokens.color[s], isNotNull);
        expect(AppAlertTokens.icon[s]!.trim(), isNotEmpty);
        expect(AppAlertTokens.pill[s]!.trim(), isNotEmpty);
        expect(AppAlertTokens.semanticLabel[s]!.trim(), isNotEmpty);
      }
    });

    test('severity colors hit WCAG AA (4.5:1) on surface0', () {
      for (final s in TrayAlertSeverity.values) {
        final c = AppAlertTokens.color[s]!;
        expect(contrast(c, AppColors.surface0),
            greaterThanOrEqualTo(AlertA11y.minTextContrast),
            reason: '$s on surface0');
      }
    });

    test('severity colors come from the status set, not brand accents', () {
      final status = {
        AppColors.success,
        AppColors.warning,
        AppColors.critical,
        AppColors.info,
      };
      for (final s in TrayAlertSeverity.values) {
        expect(status, contains(AppAlertTokens.color[s]));
      }
      // Brand accents stay OUT of the status path (spec 01).
      expect(AppAlertTokens.color.values, isNot(contains(AppColors.accentRed)));
      expect(
          AppAlertTokens.color.values, isNot(contains(AppColors.accentAmber)));
      expect(
          AppAlertTokens.color.values, isNot(contains(AppColors.accentGreen)));
    });

    test('tray states all labelled (never color-only)', () {
      for (final s in TrayIconState.values) {
        expect(AppAlertTokens.trayColor[s], isNotNull);
        expect(AppAlertTokens.traySemanticLabel[s]!.trim(), isNotEmpty);
      }
    });
  });

  group('copy tone', () {
    test('notification titles exist per severity, short and calm', () {
      for (final s in TrayAlertSeverity.values) {
        final t = AlertCopy.notificationTitle[s]!;
        expect(t.trim(), isNotEmpty);
        expect(t.length, lessThanOrEqualTo(48));
      }
      expect(AlertCopy.notificationTitle[TrayAlertSeverity.critical],
          contains('action needed'));
    });

    test('onboarding / denied / opt-out copy is verbatim-ready', () {
      for (final c in [
        AlertCopy.onboardingTitle,
        AlertCopy.onboardingBody,
        AlertCopy.inboxClearHeadline,
        AlertCopy.inboxClearBody,
        AlertCopy.permissionDeniedHeadline,
        AlertCopy.permissionDeniedBody,
        AlertCopy.optOutHeadline,
        AlertCopy.optOutBody,
      ]) {
        expect(c.trim(), isNotEmpty);
      }
      expect(AlertCopy.onboardingBody, contains('~15 min'));
      expect(AlertCopy.optOutBody, contains('in-app watcher'));
    });
  });

  group('QuietHours', () {
    DateTime at(int h, int m) => DateTime(2026, 11, 2, h, m);

    test('disabled never quiets', () {
      const q = QuietHours(enabled: false);
      expect(q.isQuietAt(at(23, 0)), isFalse);
    });

    test('overnight wrap 22:00-07:00', () {
      const q = QuietHours(enabled: true);
      expect(q.isQuietAt(at(22, 30)), isTrue);
      expect(q.isQuietAt(at(3, 0)), isTrue);
      expect(q.isQuietAt(at(6, 59)), isTrue);
      expect(q.isQuietAt(at(7, 0)), isFalse);
      expect(q.isQuietAt(at(12, 0)), isFalse);
      expect(q.isQuietAt(at(21, 59)), isFalse);
    });

    test('daytime window without wrap', () {
      const q = QuietHours(
          enabled: true,
          startHour: 13,
          endHour: 14,
          startMinute: 0,
          endMinute: 0);
      expect(q.isQuietAt(at(13, 30)), isTrue);
      expect(q.isQuietAt(at(12, 59)), isFalse);
      expect(q.isQuietAt(at(14, 0)), isFalse);
    });

    test('zero-length window is never quiet', () {
      const q = QuietHours(
          enabled: true,
          startHour: 9,
          endHour: 9,
          startMinute: 0,
          endMinute: 0);
      expect(q.isQuietAt(at(9, 0)), isFalse);
    });

    test('label + pref keys stable (headless reads the same keys)', () {
      const q = QuietHours(enabled: true);
      expect(q.label(), '22:00 – 07:00');
      expect(const QuietHours().label(), 'Off');
      expect(QuietHours.prefEnabledKey, 'alerts_quiet_hours_enabled');
      expect(QuietHours.prefStartKey, 'alerts_quiet_hours_start_minutes');
      expect(QuietHours.prefEndKey, 'alerts_quiet_hours_end_minutes');
    });
  });

  group('AlertGrouping (presentation only, payload shape unchanged)', () {
    test('groups by (host) suffix, CI lines go to Other', () {
      final g = AlertGrouping.groupByHost([
        'Disk 85% full on / (prod-core-02)',
        'Service failed: nginx (prod-core-02)',
        'CI failed: app v1.2',
        '  ',
      ]);
      expect(g['prod-core-02']!.length, 2);
      expect(g[AlertGrouping.ungroupedKey], ['CI failed: app v1.2']);
    });

    test('flatten caps groups and items with an overflow tail', () {
      final groups = <String, List<String>>{
        for (var h = 0; h < 6; h++)
          'host-$h': List.generate(7, (i) => 'a-$h-$i (host-$h)'),
      };
      final flat = AlertGrouping.flattenForInbox(groups);
      expect(flat.last, startsWith('…and '));
      // 4 groups x 5 items + 1 tail line.
      expect(flat.length, 4 * 5 + 1);
    });

    test('small lists pass through with no tail', () {
      final g = AlertGrouping.groupByHost(['a (h1)', 'b (h2)']);
      expect(AlertGrouping.flattenForInbox(g), ['a (h1)', 'b (h2)']);
    });
  });

  group('notification actions (stable deep-link contract)', () {
    test('ids stable + labels short', () {
      expect(AlertNotificationActions.all,
          ['mcp.open', 'mcp.ack', 'mcp.snooze.1h', 'mcp.mute.till_morning']);
      for (final id in AlertNotificationActions.all) {
        expect(AlertNotificationActions.labels[id]!.length,
            lessThanOrEqualTo(14));
      }
      expect(AlertNotificationActions.tapDefault, 'mcp.open');
    });
  });

  group('a11y bar', () {
    test('targets + body floor match WCAG/spec 04', () {
      expect(AlertA11y.minTarget, 48.0);
      expect(AlertA11y.minBodySize, 11.0);
      expect(AlertA11y.minTextContrast, 4.5);
      expect(AlertA11y.minBodyColor, AppColors.textSecondary);
      expect(contrast(AppColors.textSecondary, AppColors.surface0),
          greaterThanOrEqualTo(4.5));
    });
  });

  group('settings IA order', () {
    test('consent first, read-only staleness last', () {
      expect(AlertSettingsOrder.rows.first, 'background_alerts');
      expect(AlertSettingsOrder.rows.last, 'last_checked');
      expect(AlertSettingsOrder.rows, contains('quiet_hours'));
    });
  });
}
