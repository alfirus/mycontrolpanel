import '../models/mock_data.dart';

/// Unified CI/CD timeline: GitHub Actions runs + GitLab pipelines.
///
/// The screen polls each VCS separately (`_ghRuns`, `_glPipes`); this
/// service owns everything downstream: merge, newest-first sort, cap,
/// and the failure/scope filters the timeline UI needs. Pure logic —
/// no network, no plugins, safe for CI.
class DeploymentsService {
  /// Merge GitHub runs + GitLab pipelines, newest first.
  static List<DeployItem> merge(
    List<DeployItem> githubRuns,
    List<DeployItem> gitlabPipelines,
  ) {
    final all = [...githubRuns, ...gitlabPipelines];
    all.sort((a, b) => b.time.compareTo(a.time));
    return all;
  }

  /// Newest-first merge capped at [limit] (timeline pages, default 12).
  static List<DeployItem> timeline(
    List<DeployItem> githubRuns,
    List<DeployItem> gitlabPipelines, {
    int limit = 12,
  }) =>
      merge(githubRuns, gitlabPipelines).take(limit).toList();

  /// Runs that need attention (failed only), newest first.
  static List<DeployItem> failures(List<DeployItem> runs) =>
      runs.where((r) => r.status == 'failed').toList()
        ..sort((a, b) => b.time.compareTo(a.time));

  /// Filter a merged timeline to one VCS (`'github'`/`'gitlab'`).
  /// Anything else returns the list unchanged (defensive: demo rows
  /// default to `'github'` and must never vanish behind a filter).
  static List<DeployItem> onlyVcs(List<DeployItem> runs, String vcs) {
    if (vcs != 'github' && vcs != 'gitlab') return List.of(runs);
    return runs.where((r) => r.vcs == vcs).toList();
  }

  /// One-line source summary for the timeline subtitle,
  /// e.g. `7 runs (GH:4 • GL:3)`. Empty timeline reports `No runs yet`.
  static String summary(List<DeployItem> githubRuns, List<DeployItem> gitlabPipelines) {
    final total = githubRuns.length + gitlabPipelines.length;
    if (total == 0) return 'No runs yet';
    final parts = <String>[];
    if (githubRuns.isNotEmpty) parts.add('GH:${githubRuns.length}');
    if (gitlabPipelines.isNotEmpty) parts.add('GL:${gitlabPipelines.length}');
    return '$total run${total == 1 ? '' : 's'} (${parts.join(' • ')})';
  }
}
