// SPDX-License-Identifier: MIT
/// Routing-table unit tests (Farah — alert channel routing).
///
/// Covers the pure surface of `lib/services/alert_routing.dart`:
/// severity filtering, host patterns, channel grouping, consent defaults,
/// payload reuse (`NotificationHook.build` verbatim), and the fan-out
/// contract (consent × rules × quiet suppression, one sick channel never
/// sinks its siblings).
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:my_control_panel/models/alert_entry.dart';
import 'package:my_control_panel/services/alert_routing.dart';
import 'package:my_control_panel/services/alert_watch.dart';
import 'package:my_control_panel/services/polling_alerts.dart';

AlertEntry entry(
  String title,
  String host, {
  String severity = 'critical',
  String status = 'firing',
  String serverId = 's1',
}) =>
    AlertEntry(
      title: title,
      source: 'disk',
      severity: severity,
      serverId: serverId,
      serverName: host,
      status: status,
    );

RoutingRule rule({
  String id = 'r1',
  Set<String> severities = const {},
  String host = '',
  Set<AlertChannel> channels = const {AlertChannel.telegram},
}) =>
    RoutingRule(
        id: id, severities: severities, hostPattern: host, channels: channels);

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('routing table matching', () {
    test('empty rule shape matches everything (until channels empty)', () {
      final any = entry('disk / at 97%', 'web-01');
      expect(
          rule(channels: const {AlertChannel.telegram}).matches(any), isTrue);
      expect(rule(channels: const {}).matches(any), isFalse,
          reason: 'channel-less rule is inert, never an accidental send');
    });

    test('severity filter: critical-only skips warnings', () {
      final r = rule(
        severities: {'critical'},
        channels: const {AlertChannel.telegram, AlertChannel.email},
      );
      expect(r.matches(entry('svc down', 'h', severity: 'critical')), isTrue);
      expect(r.matches(entry('disk 82%', 'h', severity: 'warning')), isFalse);
      expect(r.matches(entry('note', 'h', severity: 'info')), isFalse);
    });

    test('severity match is case-insensitive', () {
      final r = rule(
        severities: {'critical'},
        channels: const {AlertChannel.email},
      );
      expect(
          r.matches(entry('x', 'h', severity: 'Critical')), isTrue);
    });

    test('empty severities match all severities', () {
      final r = rule(channels: const {AlertChannel.email});
      for (final s in ['critical', 'warning', 'info']) {
        expect(r.matches(entry('x', 'h', severity: s)), isTrue);
      }
    });

    test('host pattern: empty and star match every host', () {
      for (final p in ['', '  ', '*']) {
        final r = rule(host: p, channels: const {AlertChannel.email});
        expect(r.matches(entry('x', 'web-01', serverId: 's9')), isTrue,
            reason: 'pattern "$p"');
      }
    });

    test('host pattern: substring over serverName + serverId', () {
      final r = rule(host: 'web', channels: const {AlertChannel.email});
      expect(r.matches(entry('x', 'web-01')), isTrue);
      expect(r.matches(entry('x', 'WEB-02')), isTrue,
          reason: 'case-insensitive');
      expect(r.matches(entry('x', 'db-01')), isFalse);
      final byId =
          rule(host: 's9', channels: const {AlertChannel.email});
      expect(
          byId.matches(entry('x', 'other-name', serverId: 's9')), isTrue);
    });

    test('matchChannels unions across rules', () {
      final rules = [
        rule(
            id: 'sev',
            severities: {'critical'},
            channels: const {AlertChannel.telegram}),
        rule(
            id: 'host',
            host: 'db',
            channels: const {AlertChannel.whatsapp}),
      ];
      expect(
        AlertRouting.matchChannels(rules, entry('svc down', 'db-01')),
        {AlertChannel.telegram, AlertChannel.whatsapp},
      );
      expect(
        AlertRouting.matchChannels(
            rules, entry('disk 82%', 'db-01', severity: 'warning')),
        {AlertChannel.whatsapp},
      );
      expect(
        AlertRouting.matchChannels(
            rules, entry('disk 82%', 'web-01', severity: 'warning')),
        isEmpty,
      );
    });

    test('matchEntries groups firing and clearing entries', () {
      final rules = [
        rule(id: 'all', channels: AlertChannel.values.toSet()),
      ];
      final entries = [
        entry('disk / at 97%', 'web-01'),
        entry('rebooted', 'db-01', status: 'resolved'),
      ];
      final grouped = AlertRouting.matchEntries(rules, entries);
      expect(grouped.keys.toSet(), AlertChannel.values.toSet());
      for (final channel in AlertChannel.values) {
        expect(grouped[channel], hasLength(2));
      }
    });

    test('titlesFor marks clearing entries honestly', () {
      final titles = AlertRouting.titlesFor([
        entry('disk / at 97%', 'web-01'),
        entry('svc down', 'db-01', status: 'resolved'),
      ]);
      expect(titles.first, contains('web-01'));
      expect(titles.first, isNot(contains('Cleared')));
      expect(titles.last, startsWith('Cleared:'));
      expect(titles.last, contains('db-01'));
    });

    test('rule JSON round-trips; hostile severities/channels drop out', () {
      final r = RoutingRule.fromJson({
        'id': 'r1',
        'severities': ['critical', 'bogus', 'WARNING'],
        'host': 'web',
        'channels': ['telegram', 'pigeon'],
      });
      expect(r.severities, {'critical', 'warning'});
      expect(r.channels, {AlertChannel.telegram});
      final back = RoutingRule.fromJson(
          r.toJson().map((k, v) => MapEntry(k, v)));
      expect(back.id, 'r1');
      expect(back.severities, {'critical', 'warning'});
      expect(back.hostPattern, 'web');
      expect(back.channels, {AlertChannel.telegram});
    });

    test('rules persist shape-only and reload', () async {
      await AlertRouting.saveRules([
        rule(
            id: 'crit-tele',
            severities: {'critical'},
            channels: const {AlertChannel.telegram}),
      ]);
      final loaded = await AlertRouting.loadRules();
      expect(loaded, hasLength(1));
      expect(loaded.single.id, 'crit-tele');
      expect(loaded.single.channels, {AlertChannel.telegram});
    });
  });

  group('consent gating (default OFF)', () {
    test('every outbound channel is denied by default', () async {
      for (final channel in AlertChannel.values) {
        expect(await AlertRouting.isChannelEnabled(channel), isFalse,
            reason: channel.label);
      }
      expect(await AlertRouting.areAnyChannelsEnabled(), isFalse);
    });

    test('opt-in persists per channel', () async {
      await AlertRouting.setChannelEnabled(AlertChannel.telegram, true);
      expect(await AlertRouting.isChannelEnabled(AlertChannel.telegram),
          isTrue);
      expect(await AlertRouting.isChannelEnabled(AlertChannel.whatsapp),
          isFalse);
      expect(await AlertRouting.areAnyChannelsEnabled(), isTrue);
      await AlertRouting.setChannelEnabled(AlertChannel.telegram, false);
      expect(await AlertRouting.areAnyChannelsEnabled(), isFalse);
    });

    test('consent keys are distinct per channel', () {
      final keys = [
        for (final c in AlertChannel.values) AlertRouting.consentKeyFor(c)
      ];
      expect(keys.toSet(), hasLength(3));
    });

    test('secret keys live outside prefs (SecureStore namespace)', () {
      for (final k in [
        AlertRouting.whatsappWebhookSecretKey,
        AlertRouting.telegramBotTokenSecretKey,
        AlertRouting.telegramChatIdSecretKey,
        AlertRouting.emailWebhookSecretKey,
      ]) {
        expect(k, startsWith('alert_routing_'));
      }
    });
  });

  group('payload reuse (NotificationHook.build verbatim)', () {
    test('channel payload equals NotificationHook.build on every shape',
        () {
      const shapes = [
        <String>[],
        ['  ', ''],
        ['a'],
        ['a', 'b', 'c'],
        ['a', 'b', 'c', 'd', 'e'],
      ];
      for (final titles in shapes) {
        expect(
          AlertRouting.buildChannelPayload('t', titles),
          NotificationHook.build(
              't', titles.where((t) => t.trim().isNotEmpty).toList()),
        );
      }
    });
  });

  group('fan-out contract', () {
    test('no consent ⇒ no send, sender never called', () async {
      var calls = 0;
      final sent = await AlertRoutingFanout.fanOutClaimed(
        fresh: [entry('disk / at 97%', 'web-01')],
        rules: [rule(channels: AlertChannel.values.toSet())],
        enabled: const {},
        sender: (c, p, e) async {
          calls++;
          return true;
        },
      );
      expect(sent, isEmpty);
      expect(calls, 0);
    });

    test('no matching rule ⇒ no send', () async {
      var calls = 0;
      final sent = await AlertRoutingFanout.fanOutClaimed(
        fresh: [entry('disk 82%', 'web-01', severity: 'warning')],
        rules: [
          rule(severities: {'critical'},
              channels: const {AlertChannel.telegram})
        ],
        enabled: AlertChannel.values.toSet(),
        sender: (c, p, e) async {
          calls++;
          return true;
        },
      );
      expect(sent, isEmpty);
      expect(calls, 0);
    });

    test('empty fresh batch ⇒ no send', () async {
      var calls = 0;
      final sent = await AlertRoutingFanout.fanOutClaimed(
        fresh: const [],
        rules: [rule(channels: AlertChannel.values.toSet())],
        enabled: AlertChannel.values.toSet(),
        sender: (c, p, e) async {
          calls++;
          return true;
        },
      );
      expect(sent, isEmpty);
      expect(calls, 0);
    });

    test('quiet suppression drops every channel', () async {
      var calls = 0;
      final sent = await AlertRoutingFanout.fanOutClaimed(
        fresh: [entry('disk / at 97%', 'web-01')],
        rules: [rule(channels: AlertChannel.values.toSet())],
        enabled: AlertChannel.values.toSet(),
        quietSuppressed: true,
        sender: (c, p, e) async {
          calls++;
          return true;
        },
      );
      expect(sent, isEmpty);
      expect(calls, 0);
    });

    test('one sick channel never sinks its siblings', () async {
      final sent = await AlertRoutingFanout.fanOutClaimed(
        fresh: [entry('disk / at 97%', 'web-01')],
        rules: [rule(channels: AlertChannel.values.toSet())],
        enabled: AlertChannel.values.toSet(),
        sender: (c, p, e) async {
          if (c == AlertChannel.whatsapp) throw Exception('radio dead');
          if (c == AlertChannel.email) return false;
          return true;
        },
      );
      expect(sent.keys, {AlertChannel.telegram});
      expect(sent[AlertChannel.telegram]!['body'], isNotEmpty);
    });

    test('freshEntries narrows candidates to the winning claim keys', () {
      final a = entry('disk / at 97% on web-01', 'web-01');
      final b = entry('disk / at 97% on db-01', 'db-01');
      final keys = {
        AlertWatch.keyFor('alert', a.title, a.serverName),
      };
      final fresh = AlertRouting.freshEntries([a, b], keys);
      expect([for (final e in fresh) e.serverName], ['web-01']);
    });
  });
}
