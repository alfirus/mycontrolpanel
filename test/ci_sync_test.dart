import 'package:flutter_test/flutter_test.dart';
import 'package:my_control_panel/models/mock_data.dart';
import 'package:my_control_panel/services/ci_sync.dart';
import 'package:my_control_panel/services/mock_services.dart';
import 'package:my_control_panel/services/polling_alerts.dart';
import 'package:my_control_panel/services/service_contracts.dart';
import 'package:shared_preferences/shared_preferences.dart';

DeployItem run(String repo, int id, String status, DateTime at) => DeployItem(
      app: 'ci',
      version: '#$id',
      env: repo,
      actor: 'bot',
      time: at,
      status: status,
      duration: '1m',
      runId: id,
    );

/// Controllable GithubRepo: per-repo script of runs (or throw).
class FakeGithub implements GithubRepo {
  final Map<String, List<DeployItem>> scripts;
  final Set<String> failing;
  int calls = 0;

  FakeGithub({this.scripts = const {}, this.failing = const {}});

  @override
  Future<List<DeployItem>> repoRuns(String repo, {int limit = 8}) async {
    calls++;
    if (failing.contains(repo)) throw Exception('GitHub actions runs failed (403): rate limited');
    return (scripts[repo] ?? []).take(limit).toList();
  }

  @override
  Future<String> validate() async => 'fake';
  @override
  Future<List<GithubItem>> repoIssues(String repo) async => [];
  @override
  Future<List<GithubItem>> repoPRs(String repo) async => [];
  @override
  Future<bool> rerunRun(String repo, int runId) async => true;
  @override
  Future<int> createIssue(String repo, String title,
          {String body = '', List<String> labels = const []}) async =>
      1;
}

void main() {
  CiSyncService svc() => CiSyncService(
        policy: const PollPolicy(
          baseInterval: Duration(minutes: 5),
          maxInterval: Duration(hours: 1),
        ),
      );

  group('CiSyncService.syncRepos', () {
    test('merges repos newest-first and stamps withRepo', () async {
      SharedPreferences.setMockInitialValues({});
      final at = DateTime.utc(2026, 10, 28, 12);
      final gh = FakeGithub(scripts: {
        'o/a': [run('o/a', 1, 'success', at)],
        'o/b': [run('o/b', 2, 'failed', at.add(const Duration(minutes: 1)))],
      });
      final r = await svc().syncRepos(gh, ['o/a', 'o/b']);
      expect(r.runs.map((d) => d.version), ['#2', '#1']);
      expect(r.runs.every((d) => (d.ghRepo ?? '').isNotEmpty), isTrue);
      expect(r.errors, isEmpty);
      expect(r.servedCache, isFalse);
      expect(r.cacheNote, isEmpty);
      // Failures surface for the alert watcher.
      expect(r.failures.single.version, '#2');
      // Dedupes blank/repeated slugs without extra calls.
      final calls = gh.calls;
      await svc().syncRepos(gh, ['o/a', 'o/a', ' ']);
      expect(gh.calls, calls + 1);
    });

    test('live errors fall back to cache, errors collected', () async {
      SharedPreferences.setMockInitialValues({});
      final at = DateTime.utc(2026, 10, 28, 12);
      final good = FakeGithub(scripts: {
        'o/a': [run('o/a', 1, 'success', at)],
      });
      final s = svc();
      final first = await s.syncRepos(good, ['o/a']);
      expect(first.servedCache, isFalse);
      // API now fails (forced retry, as the SYNC button does): cache
      // stands, error recorded, note set.
      final bad = FakeGithub(failing: {'o/a'});
      final second = await s.syncRepos(bad, ['o/a'], force: true);
      expect(second.runs.single.version, '#1');
      expect(second.servedCache, isTrue);
      expect(second.errors.keys, ['o/a']);
      expect(second.cacheNote, isNotEmpty);
    });

    test('backoff skips network for a failing repo, cache stands', () async {
      SharedPreferences.setMockInitialValues({});
      final at = DateTime.utc(2026, 10, 28, 12);
      final good = FakeGithub(scripts: {
        'o/a': [run('o/a', 1, 'success', at)],
      });
      final s = svc();
      await s.syncRepos(good, ['o/a'], now: at);
      final bad = FakeGithub(failing: {'o/a'});
      // Past the base cadence: live attempt fails (streak 1, 10m window).
      await s.syncRepos(bad, ['o/a'], now: at.add(const Duration(minutes: 6)));
      expect(bad.calls, 1);
      // Inside the window: no new call, cache stands.
      final r = await s.syncRepos(bad, ['o/a'],
          now: at.add(const Duration(minutes: 7)));
      expect(bad.calls, 1);
      expect(r.runs.single.version, '#1');
      expect(r.servedCache, isTrue);
      // After the window the repo is retried.
      await s.syncRepos(bad, ['o/a'],
          now: at.add(const Duration(minutes: 17)));
      expect(bad.calls, 2);
      // ...unless the user forces a retry.
      await s.syncRepos(bad, ['o/a'],
          now: at.add(const Duration(minutes: 18)), force: true);
      expect(bad.calls, 3);
    });

    test('empty repo list returns empty without touching prefs', () async {
      SharedPreferences.setMockInitialValues({});
      final gh = FakeGithub();
      final r = await svc().syncRepos(gh, []);
      expect(r.runs, isEmpty);
      expect(gh.calls, 0);
    });

    test('timeline cap applies across repos', () async {
      SharedPreferences.setMockInitialValues({});
      final at = DateTime.utc(2026, 10, 28, 12);
      final gh = FakeGithub(scripts: {
        'o/a': List.generate(
            10, (i) => run('o/a', i, 'success', at.add(Duration(minutes: i)))),
      });
      final r = await CiSyncService(perRepoLimit: 12, timelineLimit: 5)
          .syncRepos(gh, ['o/a']);
      expect(r.runs, hasLength(5));
      expect(r.runs.first.version, '#9');
    });
  });

  group('CiSyncCache', () {
    test('round-trips DeployItem fields incl. withRepo stamp', () async {
      SharedPreferences.setMockInitialValues({});
      final at = DateTime.utc(2026, 10, 28, 12);
      await CiSyncCache.save('o/a', [run('o/a', 7, 'failed', at).withRepo('o/a')]);
      final back = await CiSyncCache.read('o/a');
      expect(back.single.version, '#7');
      expect(back.single.ghRepo, 'o/a');
      expect(back.single.status, 'failed');
      expect(back.single.runId, 7);
      expect(back.single.time.millisecondsSinceEpoch,
          at.millisecondsSinceEpoch);
    });

    test('corrupt cache reads as empty, never throws', () async {
      SharedPreferences.setMockInitialValues({'ci_runs_o/a': 'garbage'});
      expect(await CiSyncCache.read('o/a'), isEmpty);
    });
  });

  group('mock parity', () {
    test('MockGithubRepository flows through the sync', () async {
      SharedPreferences.setMockInitialValues({});
      const mock = MockGithubRepository();
      final r = await svc().syncRepos(mock, ['owner/repo']);
      expect(r.runs.map((d) => d.status).toSet(),
          containsAll(['success', 'failed', 'running']));
      expect(r.errors, isEmpty);
    });
  });
}
