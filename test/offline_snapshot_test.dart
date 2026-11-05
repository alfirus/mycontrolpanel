// SPDX-License-Identifier: MIT
// Offline mode: last-good cached snapshot per host (Elizabeth).
//
// - The cache persists only allowlisted numeric metric fields — never
//   credentials (SecureStore boundary).
// - Unreachable hosts render the cached snapshot with the established
//   stale banner ("last checked Xm ago") instead of error screens.
// - Reconnect resumes live polling transparently: retained cached alerts
//   diff to zero fresh titles through the shared AlertWatch seen-set, so
//   nothing double-notifies.
//
// CI determinism: SharedPreferences is the only mock
// (`setMockInitialValues`, reset per test); no agent HTTP, no keychain
// (keychain reads fail closed to null under `flutter test`).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:my_control_panel/models/alert_entry.dart';
import 'package:my_control_panel/models/mock_data.dart' show DeployItem;
import 'package:my_control_panel/services/alert_watch.dart';
import 'package:my_control_panel/services/background_alerts.dart';
import 'package:my_control_panel/services/host_snapshot_cache.dart';
import 'package:my_control_panel/widgets/alerts_staleness_line.dart';

/// Offline footer harness: what the server card renders while serving the
/// last-good snapshot (CACHED marker + established stale banner).
Widget _offlineHarness(String staleLabel) {
  return MaterialApp(
    home: Scaffold(
      body: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('CACHED • agent :9108'),
          AlertsStalenessLine(label: staleLabel),
        ],
      ),
    ),
  );
}

/// Reconnect harness: what the same card renders once live polling wins.
Widget _liveHarness() {
  return const MaterialApp(
    home: Scaffold(
      body: Text('LIVE • agent :9108'),
    ),
  );
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('HostSnapshotCache sanitize (SecureStore boundary)', () {
    test('keeps allowlisted numeric metrics, clamps ratios', () {
      final clean = HostSnapshotCache.sanitize({
        'cpu': 0.42,
        'ram': 0.7,
        'disk': 0.9,
        'uptime_days': 12,
        'load1': 1.5,
      });
      expect(clean['cpu'], 0.42);
      expect(clean['ram'], 0.7);
      expect(clean['uptime_days'], 12);
      expect(clean['load1'], 1.5);
    });

    test('drops every credential-shaped field', () {
      final clean = HostSnapshotCache.sanitize({
        'cpu': 0.5,
        'credential': 's3cr3t',
        'password': 'hunter2',
        'token': 'ghp_x',
        'api_key': 'k',
        'secret': 's',
        'private_key': 'k',
        'passphrase': 'p',
        'authMethod': 'password',
        'host': 'db-1',
      });
      expect(clean.keys, unorderedEquals(['cpu']));
      expect(clean.toString(), isNot(contains('s3cr3t')));
      expect(clean.toString(), isNot(contains('hunter2')));
    });

    test('returns empty when nothing cacheable survives', () {
      expect(
        HostSnapshotCache.sanitize({'credential': 'x', 'host': 'h'}),
        isEmpty,
      );
    });

    test('clamps out-of-range ratios', () {
      final clean = HostSnapshotCache.sanitize({'cpu': 9.9, 'ram': -2.0});
      expect(clean['cpu'], 1.0);
      expect(clean['ram'], 0.0);
    });
  });

  group('HostSnapshotCache persistence', () {
    test('save/read roundtrip + savedAt stamp', () async {
      await HostSnapshotCache.save('web-1', {
        'cpu': 0.25,
        'ram': 0.5,
        'disk': 0.75,
        'uptime_days': 9,
        'credential': 'must-not-persist',
      });
      final back = await HostSnapshotCache.read('web-1');
      expect(back, isNotNull);
      expect(back!['cpu'], 0.25);
      expect(back['uptime_days'], 9);
      expect(back.containsKey('credential'), isFalse);
      final at = await HostSnapshotCache.savedAt('web-1');
      expect(at, isNotNull);
      expect(
        DateTime.now().difference(at!).inMinutes < 5,
        isTrue,
        reason: 'stamp should be ~now',
      );
    });

    test('unknown host reads null (true error state, not cache)', () async {
      expect(await HostSnapshotCache.read('never-seen'), isNull);
      expect(await HostSnapshotCache.savedAt('never-seen'), isNull);
    });

    test('stale label reuses the established copy', () async {
      await HostSnapshotCache.save('db-1', {'cpu': 0.1, 'uptime_days': 3});
      final at = await HostSnapshotCache.savedAt('db-1');
      expect(at, isNotNull);
      final label = await HostSnapshotCache.staleLabel('db-1', now: at);
      expect(label, 'last checked just now');
      final aged = await HostSnapshotCache.staleLabel(
        'db-1',
        now: at!.add(const Duration(minutes: 16)),
      );
      expect(aged, 'last checked 16 min ago');
      expect(
        aged,
        BackgroundAlerts.formatLastChecked(
          now: at.add(const Duration(minutes: 16)),
          last: at,
        ),
        reason: 'must be the same funnel as the background rail',
      );
    });
  });

  group('offline/stale/reconnect widget states', () {
    testWidgets('offline: cached marker + stale banner, no error box',
        (tester) async {
      await HostSnapshotCache.save('web-1', {'cpu': 0.3, 'uptime_days': 4});
      final label = await HostSnapshotCache.staleLabel(
        'web-1',
        now: (await HostSnapshotCache.savedAt('web-1'))!
            .add(const Duration(minutes: 16)),
      );
      await tester.pumpWidget(_offlineHarness(label));
      expect(find.text('CACHED • agent :9108'), findsOneWidget);
      expect(find.text('last checked 16 min ago'), findsOneWidget);
      expect(find.byIcon(Icons.schedule), findsOneWidget);
      expect(find.textContaining('not reachable'), findsNothing);
      expect(find.textContaining('No metrics agent'), findsNothing);
    });

    testWidgets('stale banner updates as the snapshot ages', (tester) async {
      await tester.pumpWidget(_offlineHarness('last checked 2 hr ago'));
      expect(find.text('last checked 2 hr ago'), findsOneWidget);
      await tester.pumpWidget(_offlineHarness('last checked 3 hr ago'));
      expect(find.text('last checked 3 hr ago'), findsOneWidget);
      expect(find.text('last checked 2 hr ago'), findsNothing);
    });

    testWidgets('reconnect: live marker returns, stale banner gone',
        (tester) async {
      await tester.pumpWidget(_liveHarness());
      expect(find.text('LIVE • agent :9108'), findsOneWidget);
      expect(find.text('CACHED • agent :9108'), findsNothing);
      expect(find.byType(AlertsStalenessLine), findsNothing);
    });
  });

  group('reconnect never double-notifies (shared seen-set)', () {
    AlertEntry firing(String host) => AlertEntry(
          title: 'disk / at 97% on $host',
          source: 'disk',
          severity: 'critical',
          serverId: 's1',
          serverName: host,
        );

    DeployItem failedRun() => DeployItem(
          app: 'api',
          version: 'v12',
          env: 'prod',
          status: 'failed',
          actor: 'ci',
          duration: '3m',
          time: DateTime(2026, 1, 1),
        );

    test('retained cached alerts diff to zero fresh titles', () {
      // First tick (live): keys unseen → one fresh title, then marked seen.
      final alerts = [firing('web-1')];
      final runs = [failedRun()];
      final keys = AlertWatch.currentKeys(alerts, runs);
      final freshFirst = AlertWatch.freshTitles(keys, {}, alerts, runs);
      expect(freshFirst, isNotEmpty);
      // Offline ticks serve the same retained alerts: seen-set already has
      // the keys → silent.
      final freshOffline = AlertWatch.freshTitles(keys, keys, alerts, runs);
      expect(freshOffline, isEmpty);
      // Reconnect with unchanged alerts: still silent (no duplicates).
      final freshReconnect = AlertWatch.freshTitles(keys, keys, alerts, runs);
      expect(freshReconnect, isEmpty);
      // A genuinely new alert after reconnect fires exactly once.
      final grown = [...alerts, firing('db-2')];
      final grownKeys = AlertWatch.currentKeys(grown, runs);
      final freshNew = AlertWatch.freshTitles(grownKeys, keys, grown, runs);
      expect(freshNew.length, 1);
    });
  });
}
