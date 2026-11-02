// SPDX-License-Identifier: MIT
/// Nurul inbox contract: store logic (identity/order/filter/stale/snooze/
/// deep link/settings prefs) + widget tests (filters, rows, detail sheet,
/// settings section) + the a11y bar (targets, names-not-colors, live region).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_control_panel/models/alert_entry.dart';
import 'package:my_control_panel/services/alert_inbox_store.dart';
import 'package:my_control_panel/services/alert_rules.dart';
import 'package:my_control_panel/services/alert_watch.dart';
import 'package:my_control_panel/theme/alert_tokens.dart';
import 'package:my_control_panel/theme/app_theme.dart';
import 'package:my_control_panel/widgets/alert_inbox.dart';
import 'package:my_control_panel/widgets/alert_settings_section.dart';
import 'package:shared_preferences/shared_preferences.dart';

AlertEntry _entry(String title, String host, String severity,
        {String status = 'firing'}) =>
    AlertEntry(
      title: title,
      source: 'disk • $host',
      severity: severity,
      serverId: 's-$host',
      serverName: host,
      status: status,
    );

Widget _harness(Widget child) =>
    MaterialApp(home: Scaffold(body: child));

/// Scrollable harness for tall sections (production mounts them in a
/// scroll view; the 800x600 test viewport would otherwise overflow).
Widget _scrollHarness(Widget child) => MaterialApp(
      home: Scaffold(body: SingleChildScrollView(child: child)),
    );

void main() {
  group('inbox identity + ordering (spec §4)', () {
    test('keys reuse AlertWatch.keyFor verbatim (one shared set)', () {
      final items = buildInboxItems(
        alerts: [_entry('Disk 90% full on /', 'web-01', 'critical')],
      );
      expect(
        items.single.key,
        AlertWatch.keyFor('alert', 'Disk 90% full on /', 'web-01'),
      );
    });

    test('ordering: critical, warning, info; stale sinks; newest first', () {
      final items = buildInboxItems(
        alerts: [
          _entry('info old', 'h', 'info'),
          _entry('warn fresh', 'h', 'warning'),
          _entry('crit stale', 'h', 'critical'),
          _entry('crit fresh', 'h', 'critical'),
        ],
        staleKeys: {
          AlertWatch.keyFor('alert', 'crit stale', 'h'),
        },
        firedAtMs: {
          AlertWatch.keyFor('alert', 'crit stale', 'h'): 100,
          AlertWatch.keyFor('alert', 'crit fresh', 'h'): 200,
        },
      );
      final titles = items.map((i) => i.entry.title).toList();
      expect(titles, [
        'crit fresh', // critical first, fresh before stale
        'crit stale', // stale sinks within its severity, never vanishes
        'warn fresh',
        'info old',
      ]);
      expect(items[1].stale, isTrue);
      expect(items[0].stale, isFalse);
    });

    test('unknown severity strings fall to info (never crash)', () {
      final items = buildInboxItems(
        alerts: [_entry('weird', 'h', 'banana')],
      );
      expect(items.single.traySeverity, TrayAlertSeverity.info);
    });

    test('seen/snoozed flags ride the shared inputs', () {
      final key = AlertWatch.keyFor('alert', 't', 'h');
      final items = buildInboxItems(
        alerts: [_entry('t', 'h', 'warning')],
        seenKeys: {key},
        snoozedMs: {key: 999},
      );
      expect(items.single.seen, isTrue);
      expect(items.single.isSnoozedAt(100), isTrue);
      expect(items.single.isSnoozedAt(1000), isFalse);
    });
  });

  group('filters (spec §10: All / Unread / Critical)', () {
    late List<InboxItem> items;
    setUp(() {
      final critKey = AlertWatch.keyFor('alert', 'c', 'h');
      items = buildInboxItems(
        alerts: [
          _entry('c', 'h', 'critical'),
          _entry('w', 'h', 'warning'),
        ],
        seenKeys: {critKey},
      );
    });

    test('all keeps everything, unread drops seen, critical drops warning',
        () {
      expect(filterInbox(items, InboxFilter.all), hasLength(2));
      expect(
        filterInbox(items, InboxFilter.unread).map((i) => i.entry.title),
        ['w'],
      );
      expect(
        filterInbox(items, InboxFilter.critical).map((i) => i.entry.title),
        ['c'],
      );
    });

    test('snoozed rows stay visible (snooze suppresses re-toast, not the row)',
        () {
      final now = DateTime.now().millisecondsSinceEpoch;
      final key = AlertWatch.keyFor('alert', 'w', 'h');
      final snoozed = AlertSnooze.snooze({}, {key}, now);
      final rows = buildInboxItems(
        alerts: [_entry('w', 'h', 'warning')],
        snoozedMs: snoozed,
      );
      expect(filterInbox(rows, InboxFilter.unread), hasLength(1));
    });

    test('unreadCount counts unseen rows', () {
      expect(unreadCount(items), 1);
    });
  });

  group('staleness (spec §4.4: older than 2 poll intervals)', () {
    test('null firedAt is never stale (unknown, not old)', () {
      expect(isStaleItem(firedAtMs: null, nowMs: 1000, pollIntervalMs: 10),
          isFalse);
    });

    test('fresh fire is not stale; 2-interval-old fire is', () {
      expect(
          isStaleItem(firedAtMs: 990, nowMs: 1000, pollIntervalMs: 10),
          isFalse);
      expect(
          isStaleItem(firedAtMs: 900, nowMs: 1000, pollIntervalMs: 10), isTrue);
    });
  });

  group('AlertSnooze (1h, spec §6 mcp.snooze.1h)', () {
    test('parse/encode round-trip; garbage lines dropped', () {
      const raw = ['k1=100', 'junk', 'k2=abc', 'k2=200'];
      final map = AlertSnooze.parse(raw);
      expect(map, {'k1': 100, 'k2': 200});
      expect(AlertSnooze.parse(AlertSnooze.encode(map)), map);
    });

    test('snooze adds untilMs and prunes elapsed entries', () {
      final out = AlertSnooze.snooze({'old': 50}, {'new'}, 1000);
      expect(out['new'],
          1000 + AlertSnooze.snoozeDuration.inMilliseconds);
      expect(out.containsKey('old'), isFalse);
    });
  });

  group('AlertDeepLink (spec §6 tap payload, no secrets)', () {
    test('build/parse round-trip with keys', () {
      final payload = AlertDeepLink.build(
        action: AlertNotificationActions.open,
        keys: ['alert::t::h', 'ci::x::y'],
      );
      final link = AlertDeepLink.parse(payload);
      expect(link, isNotNull);
      expect(link!.action, AlertNotificationActions.open);
      expect(link.keys, ['alert::t::h', 'ci::x::y']);
    });

    test('unknown action falls back to mcp.open on build', () {
      final link =
          AlertDeepLink.parse(AlertDeepLink.build(action: 'mcp.nope'));
      expect(link!.action, AlertNotificationActions.tapDefault);
    });

    test('garbage / foreign schemes / unknown actions parse to null', () {
      expect(AlertDeepLink.parse(null), isNull);
      expect(AlertDeepLink.parse(''), isNull);
      expect(AlertDeepLink.parse('not a uri [[[ '), isNull);
      expect(AlertDeepLink.parse('https://example.com/inbox'), isNull);
      expect(AlertDeepLink.parse('mcp://elsewhere?action=mcp.open'), isNull);
      expect(
          AlertDeepLink.parse('mcp://inbox?action=mcp.nope'), isNull);
    });

    test('body tap carries no keys (open the inbox unfiltered)', () {
      final link = AlertDeepLink.parse(AlertDeepLink.build());
      expect(link!.keys, isEmpty);
    });

    test('store/consume pending round-trips once, then clears', () async {
      SharedPreferences.setMockInitialValues({});
      final payload = AlertDeepLink.build(keys: ['k']);
      await AlertDeepLink.storePending(payload);
      expect(await AlertDeepLink.consumePending(), payload);
      expect(await AlertDeepLink.consumePending(), isNull);
    });
  });

  group('AlertSettingsPrefs (spec §8)', () {
    test('severity sanitizes to critical_only by default', () async {
      SharedPreferences.setMockInitialValues({});
      expect(await AlertSettingsPrefs.loadSeverity(),
          AlertSettingsPrefs.severityCriticalOnly);
      expect(AlertSettingsPrefs.sanitizeSeverity('all'), 'all');
      expect(AlertSettingsPrefs.sanitizeSeverity('junk'),
          AlertSettingsPrefs.severityCriticalOnly);
    });

    test('threshold repair: warn>=crit resets to AlertRules defaults',
        () async {
      SharedPreferences.setMockInitialValues({
        AlertSettingsPrefs.prefDiskWarnKey: 0.95,
        AlertSettingsPrefs.prefDiskCritKey: 0.90,
        AlertSettingsPrefs.prefBruteWarnKey: 50,
        AlertSettingsPrefs.prefBruteCritKey: 5,
      });
      final rules = await AlertSettingsPrefs.loadThresholds();
      expect(rules.diskWarnAt, const AlertRules().diskWarnAt);
      expect(rules.diskCritAt, const AlertRules().diskCritAt);
      expect(rules.bruteWarnAt, const AlertRules().bruteWarnAt);
      expect(rules.bruteCritAt, const AlertRules().bruteCritAt);
    });

    test('IA order contract: all six rows in Kira order', () {
      expect(AlertSettingsOrder.rows, [
        'background_alerts',
        'severity_filter',
        'quiet_hours',
        'per_metric_thresholds',
        'battery_prompt',
        'last_checked',
      ]);
    });
  });

  group('inbox widgets', () {
    testWidgets('filter bar: three labeled chips, critical tap filters',
        (tester) async {
      var current = InboxFilter.all;
      await tester.pumpWidget(_harness(AlertInboxFilterBar(
        value: current,
        onChanged: (f) => current = f,
        unread: 2,
        critical: 1,
      )));
      expect(find.text('ALL'), findsOneWidget);
      expect(find.text('UNREAD'), findsOneWidget);
      expect(find.text('CRITICAL'), findsOneWidget);
      await tester.tap(find.text('CRITICAL'));
      expect(current, InboxFilter.critical);
    });

    testWidgets('filter chips meet the 48px touch target (spec §9.3)',
        (tester) async {
      await tester.pumpWidget(_harness(AlertInboxFilterBar(
        value: InboxFilter.all,
        onChanged: (_) {},
      )));
      for (final label in ['ALL', 'UNREAD', 'CRITICAL']) {
        final box = tester.getSize(find.ancestor(
          of: find.text(label),
          matching: find.byType(ConstrainedBox),
        ).first);
        expect(box.height, greaterThanOrEqualTo(48.0), reason: label);
      }
    });

    testWidgets('rows render pill + stale badge + unread semantics',
        (tester) async {
      final items = buildInboxItems(
        alerts: [_entry('Disk 90% full on /', 'web-01', 'critical')],
        staleKeys: {
          AlertWatch.keyFor('alert', 'Disk 90% full on /', 'web-01'),
        },
      );
      await tester.pumpWidget(_harness(Column(
        children: items.map((i) => AlertInboxRow(item: i)).toList(),
      )));
      expect(find.text('Disk 90% full on /'), findsOneWidget);
      expect(find.text('CRITICAL'), findsOneWidget);
      expect(find.text('STALE'), findsOneWidget);
      expect(find.byType(Dismissible), findsOneWidget);
    });

    testWidgets('empty inbox shows ALL CLEAR verbatim copy', (tester) async {
      await tester.pumpWidget(_harness(AlertsInboxView(
        items: const [],
        filter: InboxFilter.all,
        onFilterChanged: (_) {},
      )));
      expect(find.text(AlertCopy.inboxClearHeadline), findsOneWidget);
      expect(find.text(AlertCopy.inboxClearBody), findsOneWidget);
    });

    testWidgets('error frame offers RETRY with the a11y announcement',
        (tester) async {
      var retried = false;
      await tester.pumpWidget(_harness(AlertsInboxView(
        items: const [],
        filter: InboxFilter.all,
        onFilterChanged: (_) {},
        error: 'boom',
        onRetry: () async => retried = true,
      )));
      expect(find.text(AlertA11y.errorAnnouncement), findsOneWidget);
      await tester.tap(find.text('RETRY'));
      await tester.pump();
      expect(retried, isTrue);
    });

    testWidgets('detail sheet: snapshot + stale + 48px actions',
        (tester) async {
      final items = buildInboxItems(
        alerts: [_entry('Disk 90% full on /', 'web-01', 'warning')],
        staleKeys: {
          AlertWatch.keyFor('alert', 'Disk 90% full on /', 'web-01'),
        },
      );
      var acked = false;
      var snoozed = false;
      var opened = false;
      await tester.pumpWidget(_harness(AlertDetailSheet(
        item: items.single,
        staleLabel: 'last checked 40 min ago',
        onAck: () async => acked = true,
        onSnooze: () async => snoozed = true,
        onOpenHost: () => opened = true,
      )));
      await tester.pumpAndSettle();
      expect(find.text('METRIC SNAPSHOT'), findsOneWidget);
      expect(find.textContaining('STALE'), findsOneWidget);
      expect(find.text('last checked 40 min ago'), findsOneWidget);
      final ackSize = tester.getSize(
        find.widgetWithText(FilledButton, 'ACKNOWLEDGE'),
      );
      expect(ackSize.height, greaterThanOrEqualTo(48.0));
      final snoozeSize = tester.getSize(
        find.widgetWithText(OutlinedButton, 'SNOOZE 1H'),
      );
      expect(snoozeSize.height, greaterThanOrEqualTo(48.0));
      await tester.tap(find.text('SNOOZE 1H'));
      await tester.pumpAndSettle();
      expect(snoozed, isTrue);
      expect(acked, isFalse);
      expect(opened, isFalse);
    });

    testWidgets('detail body copy is textSecondary 11px, never muted',
        (tester) async {
      final items = buildInboxItems(
        alerts: [_entry('t', 'web-01', 'info')],
      );
      await tester.pumpWidget(_harness(AlertDetailSheet(item: items.single)));
      await tester.pumpAndSettle();
      final texts = tester
          .widgetList<Text>(find.byType(Text))
          .where((t) => t.style?.fontSize == 11.0);
      expect(texts, isNotEmpty);
      for (final t in texts) {
        expect(
          t.style!.color,
          isNot(AppColors.textMuted),
          reason: '"${t.data}" must not use textMuted (fails AA)',
        );
      }
    });
  });

  group('AlertSettingsSection (spec §8 IA)', () {
    testWidgets('renders all six IA rows with verbatim copy', (tester) async {
      SharedPreferences.setMockInitialValues({});
      await tester.pumpWidget(_scrollHarness(const AlertSettingsSection()));
      await tester.pumpAndSettle();
      expect(find.text('ALERTS'), findsOneWidget);
      expect(find.text('Toast severities'), findsOneWidget);
      expect(find.text('CRITICAL ONLY'), findsOneWidget);
      expect(find.text('ALL'), findsOneWidget);
      expect(find.text('Quiet hours'), findsWidgets);
      expect(find.text('Thresholds'), findsOneWidget);
      expect(find.text('Disk warn'), findsOneWidget);
      expect(find.text('SSH brute-force critical / 24h'), findsOneWidget);
    });

    testWidgets('severity segmented persists the choice', (tester) async {
      SharedPreferences.setMockInitialValues({});
      await tester.pumpWidget(_scrollHarness(const AlertSettingsSection()));
      await tester.pumpAndSettle();
      await tester.tap(find.text('ALL'));
      await tester.pumpAndSettle();
      expect(await AlertSettingsPrefs.loadSeverity(), 'all');
    });

    testWidgets('denied banner shows blocked copy + OS settings action',
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      var opened = false;
      await tester.pumpWidget(_scrollHarness(AlertSettingsSection(
        notificationsDenied: true,
        onOpenOsSettings: () => opened = true,
      )));
      await tester.pumpAndSettle();
      expect(
          find.text(AlertCopy.permissionDeniedHeadline), findsOneWidget);
      expect(find.text(AlertCopy.permissionDeniedBody), findsOneWidget);
      await tester.tap(find.text(AlertCopy.permissionDeniedAction));
      expect(opened, isTrue);
    });
  });
}
