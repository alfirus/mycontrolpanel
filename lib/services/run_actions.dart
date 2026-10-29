import '../models/mock_data.dart';

/// Which write action a CI/CD timeline run supports.
///
/// Pure policy so the timeline UI and the AI tools agree on what is
/// offered: GitHub completed runs can be re-run (needs `runId` + the
/// full `owner/repo` in [DeployItem.ghRepo]); GitLab failed pipelines
/// can be retried (needs `pipelineId` + [DeployItem.glProject]).
/// Running runs offer nothing — re-running them is a no-op server-side
/// and confusing in the UI.
enum RunAction { rerunGithub, retryGitlab }

/// Pure helpers behind the run detail sheet. No network, no plugins.
class RunActions {
  /// Actions offered for [run], in display order.
  static List<RunAction> actionsFor(DeployItem run) {
    final out = <RunAction>[];
    if (run.vcs == 'github' &&
        run.runId != null &&
        run.ghRepo != null &&
        run.ghRepo!.isNotEmpty &&
        run.status != 'running') {
      out.add(RunAction.rerunGithub);
    }
    if (run.vcs == 'gitlab' &&
        run.pipelineId != null &&
        run.glProject != null &&
        run.glProject!.isNotEmpty &&
        run.status == 'failed') {
      out.add(RunAction.retryGitlab);
    }
    return out;
  }

  /// Short button label, e.g. 'RERUN'.
  static String label(RunAction action) => switch (action) {
        RunAction.rerunGithub => 'RERUN',
        RunAction.retryGitlab => 'RETRY',
      };

  /// One-line confirm copy shown in the approve-first dialog.
  static String confirmText(RunAction action, DeployItem run) => switch (action) {
        RunAction.rerunGithub =>
          'Re-run ${run.app} ${run.version} on ${run.ghRepo}? Uses your saved GitHub token.',
        RunAction.retryGitlab =>
          'Retry pipeline ${run.version} on ${run.glProject}? Uses your saved GitLab token.',
      };
}
