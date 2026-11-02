// SPDX-License-Identifier: MIT
// Tray quiet-hours tests (Elizabeth): Kira §5 window math + prefs shell.
import 'package:flutter_test/flutter_test.dart';
import 'package:my_control_panel/tray/quiet_hours.dart';
import 'package:shared_preferences/shared_preferences.dart';

DateTime at(int h, int m) => DateTime(2026, 5, 4, h, m);

void main() {
  group('isQuietAt window math (Kira §5)', () {
    test('day window is inclusive-start, exclusive-end', () {
      expect(
          isQuietAtDay(at(9, 0), 9 * 60, 17 * 60), isTrue);
      expect(
          isQuietAtDay(at(8, 59), 9 * 60, 17 * 60), isFalse);
      expect(
          isQuietAtDay(at(17, 0), 9 * 60, 17 * 60), isFalse);
    });

    test('overnight wrap (default 22:00-07:00)', () {
      const s = TrayQuietHours.defaultStartMinutes;
      const e = TrayQuietHours.defaultEndMinutes;
      expect(TrayQuietHours.isQuietAt(now: at(23, 30), enabled: true, startMinutes: s, endMinutes: e), isTrue);
      expect(TrayQuietHours.isQuietAt(now: at(6, 59), enabled: true, startMinutes: s, endMinutes: e), isTrue);
      expect(TrayQuietHours.isQuietAt(now: at(7, 0), enabled: true, startMinutes: s, endMinutes: e), isFalse);
      expect(TrayQuietHours.isQuietAt(now: at(21, 59), enabled: true, startMinutes: s, endMinutes: e), isFalse);
      expect(TrayQuietHours.isQuietAt(now: at(12, 0), enabled: true, startMinutes: s, endMinutes: e), isFalse);
    });

    test('start == end means never quiet, never always', () {
      for (final t in [at(0, 0), at(12, 0), at(23, 59)]) {
        expect(
            TrayQuietHours.isQuietAt(
                now: t,
                enabled: true,
                startMinutes: 600,
                endMinutes: 600),
            isFalse);
      }
    });

    test('disabled master switch is never quiet', () {
      expect(
          TrayQuietHours.isQuietAt(
              now: at(23, 0),
              enabled: false,
              startMinutes: 22 * 60,
              endMinutes: 7 * 60),
          isFalse);
    });
  });

  group('one-shot mute', () {
    test('active before the stamp, expired after', () {
      final now = DateTime(2026, 5, 4, 23, 0);
      expect(
          TrayQuietHours.isMutedAt(
              now: now,
              mutedUntilMs:
                  now.add(const Duration(hours: 1)).millisecondsSinceEpoch),
          isTrue);
      expect(
          TrayQuietHours.isMutedAt(
              now: now,
              mutedUntilMs:
                  now.subtract(const Duration(seconds: 1)).millisecondsSinceEpoch),
          isFalse);
      expect(TrayQuietHours.isMutedAt(now: now, mutedUntilMs: null),
          isFalse);
    });

    test('nextMorning targets the coming 07:00', () {
      expect(TrayQuietHours.nextMorning(DateTime(2026, 5, 4, 23, 0)),
          DateTime(2026, 5, 5, 7));
      expect(TrayQuietHours.nextMorning(DateTime(2026, 5, 4, 6, 0)),
          DateTime(2026, 5, 4, 7));
      // Exactly 07:00 rolls to tomorrow (strictly after).
      expect(TrayQuietHours.nextMorning(DateTime(2026, 5, 4, 7, 0)),
          DateTime(2026, 5, 5, 7));
    });

    test('shouldSuppress is mute OR window', () {
      final night = at(23, 30);
      const s = 22 * 60;
      const e = 7 * 60;
      expect(
          TrayQuietHours.shouldSuppress(
              now: night,
              quietEnabled: true,
              startMinutes: s,
              endMinutes: e,
              mutedUntilMs: null),
          isTrue);
      expect(
          TrayQuietHours.shouldSuppress(
              now: at(12, 0),
              quietEnabled: true,
              startMinutes: s,
              endMinutes: e,
              mutedUntilMs:
                  at(13, 0).millisecondsSinceEpoch),
          isTrue);
      expect(
          TrayQuietHours.shouldSuppress(
              now: at(12, 0),
              quietEnabled: false,
              startMinutes: s,
              endMinutes: e,
              mutedUntilMs: null),
          isFalse);
    });
  });

  group('prefs shell', () {
    test('defaults are OFF + 22:00-07:00 + no mute', () async {
      SharedPreferences.setMockInitialValues({});
      final q = await TrayQuietHours.read();
      expect(q.enabled, isFalse);
      expect(q.start, TrayQuietHours.defaultStartMinutes);
      expect(q.end, TrayQuietHours.defaultEndMinutes);
      expect(q.mutedUntil, isNull);
    });

    test('muteUntilMorning stamps; clearMute removes', () async {
      SharedPreferences.setMockInitialValues({});
      final target = await TrayQuietHours.muteUntilMorning(
          now: DateTime(2026, 5, 4, 23, 0));
      expect(target, DateTime(2026, 5, 5, 7));
      final q = await TrayQuietHours.read();
      expect(q.mutedUntil, target.millisecondsSinceEpoch);
      await TrayQuietHours.clearMute();
      final cleared = await TrayQuietHours.read();
      expect(cleared.mutedUntil, isNull);
    });
  });
}

/// Day-window helper used to keep the inclusive/exclusive test readable.
bool isQuietAtDay(DateTime now, int s, int e) =>
    TrayQuietHours.isQuietAt(
        now: now, enabled: true, startMinutes: s, endMinutes: e);
