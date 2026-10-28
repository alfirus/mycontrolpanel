import 'package:flutter_test/flutter_test.dart';
import 'package:my_control_panel/models/alert_entry.dart';
import 'package:my_control_panel/services/alert_poller.dart';
import 'package:my_control_panel/services/alert_rules.dart';
import 'package:my_control_panel/services/polling_alerts.dart';

AlertEntry mk(String title, {String severity = 'critical'}) => AlertEntry(
      title: title,
      source: 'test',
      severity: severity,
      serverId: 's1',
      serverName: 'web-01',
    );

void main() {
  group('buildAgentHostSignals', () {
    test('maps metrics disk + sysstats load/nproc', () {
      final s = buildAgentHostSignals(
        metrics: {'cpu': 0.1, 'ram': 0.2, 'disk': 0.86, 'version': 4},
        sysstats: {'load1': 9.0, 'nproc': 4},
      );
      expect(s.diskByMount, {'/': 0.86});
      expect(s.load1, 9.0);
      expect(s.nproc, 4);
    });

    test('unknown fields stay unknown (rules skip, never assume)', () {
      final s = buildAgentHostSignals(metrics: {'cpu': 0.1});
      expect(s.diskByMount, isEmpty);
      expect(s.load1, 0.0);
      expect(s.nproc, 0);
      // Evaluates clean: no disk, no load, no uptime tripwires.
      expect(const AlertRules().evaluate('s1', 'web-01', s), isEmpty);
    });

    test('hostile values clamp, never throw', () {
      final s = buildAgentHostSignals(
        metrics: {'disk': 1.5},
        sysstats: {'load1': -3.0, 'nproc': -2},
      );
      expect(s.diskByMount['/'], 1.0);
      expect(s.load1, 0.0);
      expect(s.nproc, 0);
      // Non-finite is unknown (skipped), not a bogus alert.
      final inf = buildAgentHostSignals(metrics: {'disk': double.infinity});
      expect(inf.diskByMount, isEmpty);
    });

    test('disk thresholds fire from the agent leg', () {
      final warn = buildAgentHostSignals(metrics: {'disk': 0.82});
      final crit = buildAgentHostSignals(metrics: {'disk': 0.95});
      final warnOut = const AlertRules().evaluate('s1', 'web-01', warn);
      final critOut = const AlertRules().evaluate('s1', 'web-01', crit);
      expect(warnOut.single.severity, 'warning');
      expect(critOut.single.severity, 'critical');
    });
  });

  group('unionAlerts', () {
    test('dedupes by title, first occurrence wins', () {
      final a = [mk('Disk 90% full on /')];
      final b = [mk('Disk 90% full on /'), mk('Service failed: nginx')];
      final out = unionAlerts(a, b);
      expect(out.map((e) => e.title),
          ['Disk 90% full on /', 'Service failed: nginx']);
    });

    test('empty legs union cleanly', () {
      expect(unionAlerts([], []), isEmpty);
      expect(unionAlerts([mk('x')], []).single.title, 'x');
    });
  });

  group('AlertPollJob', () {
    AlertPollJob job() => AlertPollJob(
          serverId: 's1',
          serverName: 'web-01',
          policy: const PollPolicy(
            baseInterval: Duration(minutes: 5),
            maxInterval: Duration(hours: 1),
          ),
          notifyCooldown: const Duration(hours: 6),
        );

    test('success surfaces fresh titles + payload, base delay', () async {
      final j = job();
      var notified = <String>[];
      final t = await j.tick(
        () async => [mk('Service failed: nginx'), mk('Disk 91% full on /')],
        onNotify: (title, body) => notified.add('$title::$body'),
        now: DateTime.utc(2026, 10, 28, 12),
      );
      expect(t.consecutiveFailures, 0);
      expect(t.nextDelay, const Duration(minutes: 5));
      expect(t.freshTitles, hasLength(2));
      expect(t.notification, isNotNull);
      expect(notified, hasLength(1));
      // Second tick, same alerts: nothing fresh, no re-notify.
      final t2 = await j.tick(
        () async => [mk('Service failed: nginx'), mk('Disk 91% full on /')],
        now: DateTime.utc(2026, 10, 28, 12, 5),
      );
      expect(t2.freshTitles, isEmpty);
      expect(t2.notification, isNull);
    });

    test('failures back off, success resets the streak', () async {
      final j = job();
      Future<List<AlertEntry>> boom() async =>
          throw Exception('agent + ssh down');
      var t = await j.tick(boom);
      expect(t.consecutiveFailures, 1);
      expect(t.nextDelay, const Duration(minutes: 10));
      t = await j.tick(boom);
      expect(t.consecutiveFailures, 2);
      expect(t.nextDelay, const Duration(minutes: 20));
      // Recovery resets to base.
      t = await j.tick(() async => []);
      expect(t.consecutiveFailures, 0);
      expect(t.nextDelay, const Duration(minutes: 5));
    });

    test('cooldown suppresses flapping re-notify', () async {
      final j = job();
      final at = DateTime.utc(2026, 10, 28, 12);
      await j.tick(() async => [mk('Load average high')],
          now: at, onNotify: (_, _) {});
      // Alert clears, then the SAME title fires again inside cooldown:
      // seen-set diff treats it as fresh, cooldown still suppresses it.
      await j.tick(() async => [], now: at.add(const Duration(minutes: 5)));
      final t = await j.tick(() async => [mk('Load average high')],
          now: at.add(const Duration(minutes: 10)));
      expect(t.freshTitles, isEmpty);
      expect(t.notification, isNull);
      // After the window it notifies again.
      await j.tick(() async => [], now: at.add(const Duration(hours: 7)));
      final t2 = await j.tick(() async => [mk('Load average high')],
          now: at.add(const Duration(hours: 7, minutes: 5)));
      expect(t2.freshTitles, hasLength(1));
    });

    test('resolved alerts leave the seen-set (re-fire notifies)', () async {
      final j = job();
      final at = DateTime.utc(2026, 10, 28, 12);
      await j.tick(() async => [mk('Service failed: nginx')],
          now: at, onNotify: (_, _) {});
      await j.tick(() async => [], now: at.add(const Duration(hours: 7)));
      final t = await j.tick(() async => [mk('Service failed: nginx')],
          now: at.add(const Duration(hours: 7, minutes: 5)));
      expect(t.freshTitles, hasLength(1));
    });

    test('notify hook errors never fail the tick', () async {
      final j = job();
      final t = await j.tick(
        () async => [mk('Service failed: nginx')],
        onNotify: (_, _) => throw Exception('rail down'),
      );
      expect(t.consecutiveFailures, 0);
      expect(t.freshTitles, hasLength(1));
    });
  });
}
