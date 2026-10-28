import 'package:flutter/material.dart';
import '../models/mock_data.dart';
import '../services/github_service.dart';
import '../services/gitlab_service.dart';
import '../services/run_actions.dart';
import '../theme/app_theme.dart';

/// Run detail dialog for the live CI/CD timeline.
///
/// Read-only detail (repo, branch, actor, duration) plus the approved
/// write actions: RERUN for GitHub Actions runs, RETRY for GitLab
/// pipelines. Every write is approve-first: tapping the action reveals
/// an inline confirm step — nothing executes without the second tap.
/// Matches the AI write-gating policy (each ask = one approval).
Future<void> showRunDetailSheet({
  required BuildContext context,
  required DeployItem run,
  required String githubToken,
  required List<String> githubRepos,
  required String gitlabBaseUrl,
  required String gitlabToken,
  required VoidCallback onChanged,
}) {
  final actions = RunActions.actionsFor(run);
  RunAction? pending;
  bool busy = false;
  String? error;

  String repoFor(DeployItem r) {
    if (r.ghRepo != null && r.ghRepo!.isNotEmpty) return r.ghRepo!;
    // Fallback for runs stamped before ghRepo existed: resolve the
    // short name against tracked repos (ambiguous names pick first).
    final short = r.app;
    for (final repo in githubRepos) {
      if (repo == short || repo.split('/').last == short) return repo;
    }
    return short;
  }

  Future<void> execute(
    BuildContext ctx,
    void Function(void Function()) setD,
    RunAction action,
  ) async {
    setD(() { busy = true; error = null; });
    try {
      if (action == RunAction.rerunGithub) {
        await GithubService(githubToken).rerunRun(repoFor(run), run.runId!);
      } else {
        final svc = GitlabService(baseUrl: gitlabBaseUrl, token: gitlabToken);
        await svc.retryPipeline(run.glProject!, run.pipelineId!);
      }
      if (!ctx.mounted) return;
      Navigator.pop(ctx, true);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        backgroundColor: AppColors.success.withValues(alpha: 0.14),
        content: Text(
          '${RunActions.label(action)} accepted for ${run.app} ${run.version}',
          style: const TextStyle(fontSize: 12, color: AppColors.success),
        ),
        duration: const Duration(seconds: 3),
      ));
      onChanged();
    } catch (e) {
      if (!ctx.mounted) return;
      setD(() {
        busy = false;
        error = e.toString().replaceFirst('Exception: ', '').split('\n').first;
      });
    }
  }

  return showDialog(
    context: context,
    builder: (ctx) => StatefulBuilder(builder: (ctx, setD) {
      return AlertDialog(
        backgroundColor: AppColors.surface1,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: const BorderSide(color: AppColors.border)),
        title: Row(children: [
          Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                  color: AppColors.accentCyan.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(7)),
              child: const Icon(Icons.play_circle_outline,
                  size: 15, color: AppColors.accentCyan)),
          const SizedBox(width: 10),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text('${run.app} ${run.version}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                        fontFamily: AppFonts.mono)),
                Text(
                    '${run.vcs == 'gitlab' ? 'GitLab pipeline' : 'GitHub Actions'} • ${run.env} • by ${run.actor}',
                    style: const TextStyle(
                        fontSize: 10, color: AppColors.textMuted)),
              ])),
          IconButton(
              onPressed: () => Navigator.pop(ctx),
              icon: const Icon(Icons.close, size: 16, color: AppColors.textMuted)),
        ]),
        content: SizedBox(
          width: 420,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            _kv('Status', run.status.toUpperCase()),
            _kv('When', '${run.time.toLocal()}'.split('.').first),
            _kv('Duration', run.duration),
            if (run.vcs == 'github') _kv('Repo', repoFor(run)),
            if (run.vcs == 'gitlab' && run.glProject != null)
              _kv('Project', run.glProject!),
            if (actions.isEmpty)
              const Padding(
                padding: EdgeInsets.only(top: 10),
                child: Text(
                    'No actions available — running runs cannot be re-run, and demo rows are read-only.',
                    style: TextStyle(fontSize: 11, color: AppColors.textMuted)),
              ),
            if (error != null)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Text(error!,
                    style: const TextStyle(
                        fontSize: 11, color: AppColors.critical)),
              ),
            if (pending != null && !busy)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Text(RunActions.confirmText(pending!, run),
                    style: const TextStyle(
                        fontSize: 11, color: AppColors.warning)),
              ),
          ]),
        ),
        actions: [
          TextButton(
              onPressed: busy ? null : () => Navigator.pop(ctx),
              child: const Text('CLOSE',
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textMuted))),
          for (final a in actions)
            pending == a
                ? FilledButton(
                    onPressed: busy ? null : () => execute(ctx, setD, a),
                    style: FilledButton.styleFrom(
                        backgroundColor: AppColors.accentCyan,
                        foregroundColor: Colors.black),
                    child: busy
                        ? const SizedBox(
                            width: 12,
                            height: 12,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.black))
                        : Text('CONFIRM ${RunActions.label(a)}',
                            style: const TextStyle(
                                fontSize: 11, fontWeight: FontWeight.w800)),
                  )
                : OutlinedButton(
                    onPressed: busy
                        ? null
                        : () => setD(() { pending = a; error = null; }),
                    style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.accentCyan,
                        side: const BorderSide(
                            color: AppColors.accentCyan)),
                    child: Text(RunActions.label(a),
                        style: const TextStyle(
                            fontSize: 11, fontWeight: FontWeight.w800)),
                  ),
        ],
      );
    }),
  );
}

Widget _kv(String k, String v) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(children: [
        SizedBox(
            width: 70,
            child: Text(k,
                style: const TextStyle(
                    fontSize: 10, color: AppColors.textMuted))),
        Expanded(
            child: Text(v,
                style: const TextStyle(
                    fontSize: 11, color: AppColors.textPrimary))),
      ]),
    );
