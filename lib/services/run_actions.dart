// SPDX-License-Identifier: MIT
import '../models/alert_entry.dart';
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

/// Which one-click host fix an alert supports.
///
/// Agent-side stdlib actions only, executed over the existing SSH
/// [AgentService.runCommand] path — no new agent dependencies.
enum HostFixAction {
  restartService,
  pruneDisk,
  vacuumJournal,
  clearQueue,
}

/// Pure policy behind alert remediation. Same contract as [RunActions]:
/// the alert UI and the AI tools share [actionsFor]/[label]/[confirmText]
/// so both surfaces offer exactly the same fixes for the same alert.
class HostFixes {
  /// Unit names accepted into the restart command (mirrors the AI
  /// `restart_service` tool allowlist — no shell metacharacters).
  static final RegExp unitName = RegExp(r'^[A-Za-z0-9@._:\-]+$');

  /// Unit parsed from a `Service failed: <unit>` title, or null when the
  /// alert is not a service failure or the unit is not allowlisted.
  static String? unitFor(AlertEntry alert) {
    const prefix = 'Service failed: ';
    if (!alert.title.startsWith(prefix)) return null;
    var unit = alert.title.substring(prefix.length).trim();
    unit = unit.replaceAll('.service', '');
    if (unit.isEmpty || !unitName.hasMatch(unit)) return null;
    return unit;
  }

  /// Fixes offered for [alert], in display order. Pure — no network.
  static List<HostFixAction> actionsFor(AlertEntry alert) {
    // Failed systemd unit → restart it.
    if (unitFor(alert) != null) return const [HostFixAction.restartService];
    final title = alert.title;
    final source = alert.source.split('•').first.trim();
    // Disk pressure (SSH sweep or ML forecast) → free space.
    if (source == 'disk' ||
        source == 'ml-pipeline/disk' ||
        title.startsWith('Disk ')) {
      return const [HostFixAction.pruneDisk, HostFixAction.vacuumJournal];
    }
    // Load pressure or OOM → shed backlog.
    final lower = title.toLowerCase();
    if (source == 'load' ||
        source == 'ml-pipeline/load' ||
        title.startsWith('Load ') ||
        lower.contains('out-of-memory') ||
        lower.contains('oom-killer')) {
      return const [HostFixAction.clearQueue];
    }
    return const [];
  }

  /// Short button label, e.g. 'RESTART'.
  static String label(HostFixAction action) => switch (action) {
        HostFixAction.restartService => 'RESTART',
        HostFixAction.pruneDisk => 'PRUNE DISK',
        HostFixAction.vacuumJournal => 'VACUUM LOGS',
        HostFixAction.clearQueue => 'CLEAR QUEUE',
      };

  /// Exact SSH command this fix runs. stdlib only; [unit] is required
  /// for [HostFixAction.restartService] and must match [unitName].
  static String commandFor(HostFixAction action, {String? unit}) {
    switch (action) {
      case HostFixAction.restartService:
        final u = (unit ?? '').replaceAll('.service', '');
        if (u.isEmpty || !unitName.hasMatch(u)) {
          throw ArgumentError.value(unit, 'unit', 'not an allowlisted unit name');
        }
        return 'sudo systemctl restart $u && sleep 1 && systemctl is-active $u';
      case HostFixAction.pruneDisk:
        return 'df -h / | tail -1 && '
            '(command -v apt-get >/dev/null && sudo apt-get clean || true) && '
            '(command -v docker >/dev/null && sudo docker system prune -f || true) && '
            'sudo find /tmp /var/tmp -mindepth 1 -mtime +7 -delete 2>/dev/null; '
            'df -h / | tail -1';
      case HostFixAction.vacuumJournal:
        return 'sudo journalctl --vacuum-size=200M --vacuum-time=14d 2>&1 | tail -3; '
            'journalctl --disk-usage';
      case HostFixAction.clearQueue:
        return 'sudo systemctl reset-failed && '
            'for j in \$(systemctl list-jobs --no-legend 2>/dev/null | awk \'{print \$1}\'); do '
            'sudo systemctl cancel \$j; done; '
            'systemctl list-jobs --no-legend --no-pager | wc -l';
    }
  }

  /// Dry-run preview copy shown in the approve-first dialog: what the
  /// fix will do plus the exact command, so approval is informed.
  static String confirmText(HostFixAction action, AlertEntry alert, {String? unit}) {
    final resolvedUnit = unit ?? unitFor(alert);
    switch (action) {
      case HostFixAction.restartService:
        return 'Restart `${resolvedUnit ?? '<unknown>'}` on ${alert.serverName}? '
            'Will run: ${commandFor(action, unit: resolvedUnit)}';
      case HostFixAction.pruneDisk:
        return 'Free disk on ${alert.serverName}? '
            'Clears package caches, unused docker layers, and /tmp files older than 7 days. '
            'Will run: ${commandFor(action)}';
      case HostFixAction.vacuumJournal:
        return 'Vacuum system logs on ${alert.serverName} to 200M / 14 days? '
            'Will run: ${commandFor(action)}';
      case HostFixAction.clearQueue:
        return 'Shed load on ${alert.serverName}? '
            'Resets failed units and cancels queued systemd jobs (they re-trigger normally). '
            'Will run: ${commandFor(action)}';
    }
  }
}
