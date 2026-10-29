import 'package:flutter_test/flutter_test.dart';
import 'package:my_control_panel/services/github_service.dart';
import 'package:my_control_panel/services/mock_services.dart';
import 'package:my_control_panel/services/service_locator.dart';

void main() {
  group('MockGithubRepository (GithubRepo contract)', () {
    const repo = MockGithubRepository();
    const slug = 'owner/repo';

    test('validate returns the mock login', () async {
      expect(await repo.validate(), 'mock-user');
    });

    test('issues are open and carry the repo slug', () async {
      final issues = await repo.repoIssues(slug);
      expect(issues, isNotEmpty);
      expect(issues.every((i) => i.state == 'open'), isTrue);
      expect(issues.every((i) => i.repo == slug), isTrue);
    });

    test('PRs are open and distinct from issues', () async {
      final prs = await repo.repoPRs(slug);
      final issues = await repo.repoIssues(slug);
      expect(prs, isNotEmpty);
      expect(
          prs.map((p) => p.number).toSet().intersection(
              issues.map((i) => i.number).toSet()),
          isEmpty);
    });

    test('runs cover success/failed/running for the CI badge', () async {
      final runs = await repo.repoRuns(slug);
      expect(runs.map((r) => r.status).toSet(),
          containsAll(['success', 'failed', 'running']));
      expect(runs.any((r) => r.runId != null), isTrue);
    });

    test('runs honor limit', () async {
      expect(await repo.repoRuns(slug, limit: 1), hasLength(1));
    });

    test('rerun is accepted, createIssue returns a number', () async {
      expect(await repo.rerunRun(slug, 9001), isTrue);
      expect(await repo.createIssue(slug, 't'), greaterThan(0));
    });
  });

  group('MockServices wires the mock github repo', () {
    test('current mock container serves MockGithubRepository', () {
      expect(MockServices().github, isA<MockGithubRepository>());
    });
  });

  group('LiveGithubRepo', () {
    test('every method throws StateError without a token', () async {
      final live = LiveGithubRepo(() async => null);
      expect(() => live.validate(), throwsStateError);
      expect(() => live.repoIssues('o/r'), throwsStateError);
      expect(() => live.repoPRs('o/r'), throwsStateError);
      expect(() => live.repoRuns('o/r'), throwsStateError);
      expect(() => live.rerunRun('o/r', 1), throwsStateError);
      expect(() => live.createIssue('o/r', 't'), throwsStateError);
    });

    test('blank token counts as unconfigured', () async {
      final live = LiveGithubRepo(() async => '  ');
      expect(() => live.validate(), throwsStateError);
    });
  });
}
