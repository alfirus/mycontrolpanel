import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:my_control_panel/models/mock_data.dart';
import 'package:my_control_panel/models/server_connection.dart';
import 'package:my_control_panel/screens/control_center_screen.dart';
import 'package:my_control_panel/services/github_service.dart';
import 'package:my_control_panel/services/gitlab_service.dart';
import 'package:my_control_panel/services/mock_services.dart';
import 'package:my_control_panel/services/security_posture.dart';
import 'package:my_control_panel/services/service_contracts.dart';
import 'package:my_control_panel/services/service_locator.dart';

/// Elizabeth's live-wiring slice (t_ffb40ba3): the four VCS/security
/// sections consume the [GithubRepo] abstraction (never a hardcoded
/// token), paginate Issues/PRs, surface rate-limit + empty + error
/// frames through the shared StateView pattern, and fall back to DEMO
/// only when no server/token is configured.

GithubItem _issue(String title, String repo, int number) => GithubItem(
      title: title,
      repo: repo,
      author: 'tester',
      number: number,
      state: 'open',
      labels: const ['bug'],
      updatedAt: DateTime.utc(2026, 10, 29, 12),
      comments: 1,
    );

DeployItem _run(String version) => DeployItem(
      app: 'api',
      version: version,
      env: 'main',
      actor: 'tester',
      time: DateTime.utc(2026, 10, 29, 12),
      status: 'success',
      duration: '2m',
    );

/// Controllable GithubRepo: scripted pages per tab, or a thrown failure.
class _FakeGithub implements GithubRepo {
  List<GithubItem> issues;
  List<GithubItem> page2Issues;
  List<GithubItem> prs;
  List<GithubItem> tasks;
  List<DeployItem> runs;
  Object? failure;
  final List<String> calls = [];

  _FakeGithub({
    this.issues = const [],
    this.page2Issues = const [],
    this.prs = const [],
    this.tasks = const [],
    this.runs = const [],
    this.failure,
  });

  @override
  Future<String> validate() async {
    if (failure != null) throw failure!;
    return 'tester';
  }

  @override
  Future<List<GithubItem>> repoIssues(String repo,
      {int page = 1, int perPage = 30}) async {
    calls.add('issues:$repo:$page:$perPage');
    return List.of(page == 1 ? issues : page2Issues);
  }

  @override
  Future<List<GithubItem>> repoPRs(String repo,
      {int page = 1, int perPage = 30}) async {
    calls.add('prs:$repo:$page:$perPage');
    return List.of(prs);
  }

  @override
  Future<List<Map<String, dynamic>>> projectsV2() async => [];

  @override
  Future<List<GithubItem>> projectTasks() async => List.of(tasks);

  @override
  Future<List<GithubItem>> myTasks(List<String> repos) async => [];

  @override
  Future<List<DeployItem>> repoRuns(String repo, {int limit = 8}) async =>
      List.of(runs);

  @override
  Future<bool> rerunRun(String repo, int runId) async => true;

  @override
  Future<int> createIssue(String repo, String title,
          {String body = '', List<String> labels = const []}) async =>
      1;
}

Services _servicesWith(GithubRepo github) => Services(
      metrics: const MockMetricsPoller(),
      procStats: const MockProcStatsPoller(),
      crons: const MockCronRepository(),
      apps: const MockAppRepository(),
      alerts: const MockAlertRepository(),
      keys: const MockKeyLoader(),
      secrets: MockSecretStore(),
      github: github,
    );

const _secureChannel =
    MethodChannel('plugins.it_nomads.com/flutter_secure_storage');

Map<String, Object> _basePrefs() => {
      'github_repos': ['o/r'],
      'github_user': 'tester',
      'auto_update_check': false,
      'auto_refresh': false,
      'notifications': false,
      'secrets_migrated_v1': true,
    };

Future<void> _pumpScreen(
  WidgetTester tester, {
  Map<String, Object>? prefs,
  Map<String, String?> secrets = const {},
  required GithubRepo github,
}) async {
  SharedPreferences.setMockInitialValues(prefs ?? _basePrefs());
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(_secureChannel, (call) async {
    if (call.method == 'read') {
      final args = call.arguments as Map;
      return secrets[args['key']];
    }
    return null;
  });
  Services.overrideCurrent(_servicesWith(github));
  addTearDown(() {
    Services.overrideCurrent(null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_secureChannel, null);
  });
  await tester.pumpWidget(const MaterialApp(home: ControlCenterScreen()));
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 200));
  }
}

ServerConnection _server(String id, String credential) => ServerConnection(
      id: id,
      name: id,
      host: '127.0.0.1',
      port: 22,
      username: 'root',
      authMethod: AuthMethod.password,
      credential: credential,
      region: 'us-east-1',
      os: 'Ubuntu 24.04',
      env: ServerEnv.dev,
      createdAt: DateTime.utc(2026, 10, 1),
    );

void main() {
  group('GithubService.describeApiError (rate-limit copy)', () {
    test('403 with exhausted bucket names the limit + reset', () {
      final msg = GithubService.describeApiError(403,
          {'x-ratelimit-remaining': '0', 'x-ratelimit-reset': '1760000000'},
          '{"message":"API rate limit exceeded"}', 'issues');
      expect(msg.startsWith('GitHub rate limit exceeded'), isTrue);
      expect(msg, contains('resets'));
      expect(msg, contains('slim the repo list'));
    });

    test('403 body mentioning rate limit counts without headers', () {
      final msg = GithubService.describeApiError(
          403, {}, '{"message":"API rate limit exceeded for user"}', 'pulls');
      expect(msg.startsWith('GitHub rate limit exceeded'), isTrue);
    });

    test('plain 403 keeps the legacy shape', () {
      final msg = GithubService.describeApiError(
          403, {}, '{"message":"Resource not accessible"}', 'issues');
      expect(msg, 'GitHub issues failed (403): Resource not accessible');
    });

    test('429 gets the backoff line', () {
      final msg = GithubService.describeApiError(429, {}, '', 'issues');
      expect(msg, contains('secondary limit'));
      expect(msg, contains('SYNC retries'));
    });

    test('non-JSON body falls back to status only', () {
      expect(GithubService.describeApiError(500, {}, 'boom', 'issues'),
          'GitHub issues failed (500)');
    });
  });

  group('GitlabService.describeApiError (throttle copy)', () {
    test('429 gets the backoff line', () {
      final msg = GitlabService.describeApiError(429, '', 'issues');
      expect(msg, contains('throttle'));
      expect(msg, contains('SYNC retries'));
    });

    test('other failures keep the legacy shape', () {
      expect(
          GitlabService.describeApiError(
              404, '{"message":"404 Not found"}', 'issues'),
          'GitLab issues failed (404): 404 Not found');
    });
  });

  group('MockGithubRepository (extended contract)', () {
    test('accepts pagination params, stays deterministic', () async {
      const repo = MockGithubRepository();
      final p1 = await repo.repoIssues('o/r', page: 2, perPage: 10);
      expect(p1, isNotEmpty);
      final prs = await repo.repoPRs('o/r', page: 1);
      expect(prs, isNotEmpty);
    });

    test('projects/tasks lanes return deterministic data', () async {
      const repo = MockGithubRepository();
      expect(await repo.projectsV2(), isNotEmpty);
      expect(await repo.projectTasks(), isNotEmpty);
      expect(await repo.myTasks(['o/r']), isNotEmpty);
    });
  });

  group('LiveGithubRepo (no token, no call)', () {
    test('new lanes throw StateError without a token', () async {
      final live = LiveGithubRepo(() async => null);
      expect(() => live.projectsV2(), throwsStateError);
      expect(() => live.projectTasks(), throwsStateError);
      expect(() => live.myTasks(['o/r']), throwsStateError);
    });
  });

  group('SecurityPosture.findingsFor (live security source)', () {
    test('raw pre-migration credential is critical', () {
      final findings = SecurityPosture.findingsFor([_server('web-1', 'hunter2')]);
      expect(findings, hasLength(1));
      expect(findings.single.severity, 'critical');
      expect(findings.single.title, contains('web-1'));
    });

    test('empty credential is a warning', () {
      final findings = SecurityPosture.findingsFor([_server('web-1', '')]);
      expect(findings, hasLength(1));
      expect(findings.single.severity, 'warning');
    });

    test('keychain-backed credential is clean', () {
      expect(
          SecurityPosture.findingsFor(
              [_server('web-1', 'secure:srv_cred_web-1')]),
          isEmpty);
    });

    test('critical sorts before warning', () {
      final findings = SecurityPosture.findingsFor(
          [_server('b-blank', ''), _server('a-raw', 'hunter2')]);
      expect(findings.map((f) => f.severity), ['critical', 'warning']);
    });
  });

  group('GitHub panel on the live screen', () {
    testWidgets('demo fallback when no token/repos are configured',
        (tester) async {
      await _pumpScreen(
        tester,
        prefs: {
          'auto_update_check': false,
          'auto_refresh': false,
          'notifications': false,
          'secrets_migrated_v1': true,
        },
        github: _FakeGithub(),
      );
      expect(find.text('GITHUB • DEMO'), findsWidgets);
      expect(find.text('GITLAB • DEMO'), findsWidgets);
      expect(find.text('CI/CD • DEMO'), findsWidgets);
      expect(find.text('SECURITY • DEMO'), findsWidgets);
    });

    testWidgets('live issues + CI runs render from the contract',
        (tester) async {
      await _pumpScreen(
        tester,
        secrets: const {'github_token': 'ghp_test'},
        github: _FakeGithub(
          issues: [_issue('Live: fix login redirect', 'o/r', 7)],
          prs: [_issue('Live: add pagination', 'o/r', 8)],
          tasks: [_issue('Live: rotate token', 'o/r', 9)],
          runs: [_run('#42 • abc1234')],
        ),
      );
      expect(find.text('GITHUB • @tester'), findsOneWidget);
      expect(find.text('Live: fix login redirect'), findsOneWidget);
      expect(find.text('CI/CD • LIVE'), findsWidgets);
    });

    testWidgets('rate-limit error renders the StateView error frame',
        (tester) async {
      await _pumpScreen(
        tester,
        secrets: const {'github_token': 'ghp_test'},
        github: _FakeGithub(
          failure: Exception(
              'GitHub rate limit exceeded — retry shortly or slim the repo list.'),
        ),
      );
      expect(find.text('GITHUB SYNC FAILED'), findsWidgets);
      expect(find.text('RETRY'), findsWidgets);
      expect(find.textContaining('rate limit exceeded'), findsWidgets);
    });

    testWidgets('empty lanes render the StateView empty frames',
        (tester) async {
      await _pumpScreen(
        tester,
        secrets: const {'github_token': 'ghp_test'},
        github: _FakeGithub(),
      );
      expect(find.text('QUEUE IS CLEAR'), findsWidgets);
      expect(find.text('NO RUNS YET'), findsWidgets);
    });

    testWidgets('LOAD MORE appends page 2 on the full GitHub tab',
        (tester) async {
      final github = _FakeGithub(
        issues: List.generate(30, (i) => _issue('Page1 issue $i', 'o/r', i)),
        page2Issues: [_issue('Page2 straggler', 'o/r', 100)],
      );
      await _pumpScreen(
        tester,
        secrets: const {'github_token': 'ghp_test'},
        github: github,
      );
      expect(find.text('GITHUB • @tester'), findsOneWidget);
      await tester.tap(find.text('GitHub'));
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pump(const Duration(milliseconds: 200));
      final loadMore = find.text('LOAD MORE');
      expect(loadMore, findsOneWidget);
      await tester.ensureVisible(loadMore);
      await tester.pump(const Duration(milliseconds: 200));
      await tester.tap(loadMore);
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text('Page2 straggler'), findsOneWidget);
      expect(github.calls, contains('issues:o/r:2:30'));
    });
  });
}
