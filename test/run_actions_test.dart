import 'package:flutter_test/flutter_test.dart';
import 'package:my_control_panel/models/mock_data.dart';
import 'package:my_control_panel/services/run_actions.dart';

DeployItem gh({
  String status = 'failed',
  int? runId = 101,
  String? ghRepo = 'alfirus/mycontrolpanel',
}) =>
    DeployItem(
      app: 'mycontrolpanel',
      version: '#42 • abc1234',
      env: 'main',
      actor: 'alfirus',
      time: DateTime(2026, 10, 28, 12),
      status: status,
      duration: '1m 2s',
      runId: runId,
      ghRepo: ghRepo,
    );

DeployItem gl({
  String status = 'failed',
  int? pipelineId = 7,
  String? project = 'group/app',
}) =>
    DeployItem(
      app: 'app',
      version: '#7 • abc12345',
      env: 'main',
      actor: 'ci',
      time: DateTime(2026, 10, 28, 12),
      status: status,
      duration: '30s',
      vcs: 'gitlab',
      glProject: project,
      pipelineId: pipelineId,
    );

void main() {
  group('RunActions.actionsFor', () {
    test('failed GH run with id+repo offers rerun', () {
      expect(RunActions.actionsFor(gh()), [RunAction.rerunGithub]);
    });

    test('successful GH run also offers rerun (completed, not running)', () {
      expect(RunActions.actionsFor(gh(status: 'success')),
          [RunAction.rerunGithub]);
    });

    test('running GH run offers nothing', () {
      expect(RunActions.actionsFor(gh(status: 'running')), isEmpty);
    });

    test('GH run without runId or repo offers nothing', () {
      expect(RunActions.actionsFor(gh(runId: null)), isEmpty);
      expect(RunActions.actionsFor(gh(ghRepo: null)), isEmpty);
      expect(RunActions.actionsFor(gh(ghRepo: '')), isEmpty);
    });

    test('failed GL pipeline offers retry', () {
      expect(RunActions.actionsFor(gl()), [RunAction.retryGitlab]);
    });

    test('successful/running GL pipeline offers nothing', () {
      expect(RunActions.actionsFor(gl(status: 'success')), isEmpty);
      expect(RunActions.actionsFor(gl(status: 'running')), isEmpty);
    });

    test('GL pipeline without ids offers nothing', () {
      expect(RunActions.actionsFor(gl(pipelineId: null)), isEmpty);
      expect(RunActions.actionsFor(gl(project: null)), isEmpty);
    });

    test('demo rows (no ids) offer nothing', () {
      final demo = DeployItem(
        app: 'api',
        version: 'v1.2',
        env: 'prod',
        actor: 'ci',
        time: DateTime(2026, 10, 28, 12),
        status: 'success',
        duration: '1m',
      );
      expect(RunActions.actionsFor(demo), isEmpty);
    });
  });

  group('RunActions copy', () {
    test('labels are short caps', () {
      expect(RunActions.label(RunAction.rerunGithub), 'RERUN');
      expect(RunActions.label(RunAction.retryGitlab), 'RETRY');
    });

    test('confirm text names the target', () {
      final ghConfirm =
          RunActions.confirmText(RunAction.rerunGithub, gh());
      expect(ghConfirm, contains('alfirus/mycontrolpanel'));
      final glConfirm = RunActions.confirmText(RunAction.retryGitlab, gl());
      expect(glConfirm, contains('group/app'));
    });
  });

  group('DeployItem.withRepo', () {
    test('stamps the full repo, keeps everything else', () {
      final stamped = gh(ghRepo: null).withRepo('alfirus/mycontrolpanel');
      expect(stamped.ghRepo, 'alfirus/mycontrolpanel');
      expect(stamped.runId, 101);
      expect(stamped.status, 'failed');
      expect(
          RunActions.actionsFor(stamped), [RunAction.rerunGithub]);
    });
  });
}
