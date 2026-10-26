import '../models/alert_entry.dart';
import '../models/app_entry.dart';
import '../models/cron_entry.dart';
import '../models/mock_data.dart';
import '../models/server_connection.dart';
import 'agent_service.dart';
import 'github_service.dart';
import 'gitlab_service.dart';

/// Tool-calling for the AI assistant (Stage 2).
/// Read tools run immediately. Write tools are `gated` — the UI must show
/// an Approve/Deny prompt before [execute] is called for them.
/// Destructive commands (reboot, raw shell, user management) are deliberately absent.
class AiTools {
  static const int maxIterations = 5;

  static List<Map<String, dynamic>> schemas() => const [
        {
          'type': 'function',
          'function': {
            'name': 'get_server_metrics',
            'description': 'Get live CPU/RAM/disk/uptime for one saved server (by exact server name), or all servers if omitted.',
            'parameters': {
              'type': 'object',
              'properties': {
                'server': {'type': 'string', 'description': 'Exact server name, e.g. prod-core-01. Omit for all.'},
              },
            },
          },
        },
        {
          'type': 'function',
          'function': {
            'name': 'list_crons',
            'description': 'List discovered cronjobs, optionally filtered to one server (exact name).',
            'parameters': {
              'type': 'object',
              'properties': {
                'server': {'type': 'string', 'description': 'Exact server name. Omit for all.'},
              },
            },
          },
        },
        {
          'type': 'function',
          'function': {
            'name': 'list_apps',
            'description': 'List discovered apps/services, optionally filtered to one server (exact name).',
            'parameters': {
              'type': 'object',
              'properties': {
                'server': {'type': 'string', 'description': 'Exact server name. Omit for all.'},
              },
            },
          },
        },
        {
          'type': 'function',
          'function': {
            'name': 'list_alerts',
            'description': 'List current alert signals harvested from servers.',
            'parameters': {'type': 'object', 'properties': {}},
          },
        },
        {
          'type': 'function',
          'function': {
            'name': 'list_issues',
            'description': 'List open GitHub issues across tracked repos.',
            'parameters': {'type': 'object', 'properties': {}},
          },
        },
        {
          'type': 'function',
          'function': {
            'name': 'list_prs',
            'description': 'List open GitHub pull requests across tracked repos.',
            'parameters': {'type': 'object', 'properties': {}},
          },
        },
        {
          'type': 'function',
          'function': {
            'name': 'get_workflow_runs',
            'description': 'List recent GitHub Actions runs (newest first), with run ids for rerun.',
            'parameters': {'type': 'object', 'properties': {}},
          },
        },
        {
          'type': 'function',
          'function': {
            'name': 'restart_service',
            'description': 'REQUIRES USER APPROVAL. Restart a systemd service on a server via sudo systemctl restart. Use only for a service discovered by list_apps. Report the resulting active state.',
            'parameters': {
              'type': 'object',
              'properties': {
                'server': {'type': 'string', 'description': 'Exact server name.'},
                'unit': {'type': 'string', 'description': 'Service name WITHOUT .service, e.g. nginx.'},
              },
              'required': ['server', 'unit'],
            },
          },
        },
        {
          'type': 'function',
          'function': {
            'name': 'run_ssh_command',
            'description': 'REQUIRES USER APPROVAL. Run a diagnostic command on a server. ONLY these are allowed: systemctl status|is-active <unit>, journalctl --no-pager -u <unit> -n <lines>, ls -l[a] <absolute-path> (directory listings), cat <absolute-path> (only .log/.conf/.yaml/.yml/.toml/.json/.service/.timer files), df -h, uptime, free -m. Anything else is rejected.',
            'parameters': {
              'type': 'object',
              'properties': {
                'server': {'type': 'string', 'description': 'Exact server name.'},
                'command': {'type': 'string', 'description': 'The exact command to run.'},
              },
              'required': ['server', 'command'],
            },
          },
        },
        {
          'type': 'function',
          'function': {
            'name': 'rerun_workflow',
            'description': 'REQUIRES USER APPROVAL. Re-run a failed GitHub Actions run by its run id (see get_workflow_runs).',
            'parameters': {
              'type': 'object',
              'properties': {
                'repo': {'type': 'string', 'description': 'owner/repo.'},
                'run_id': {'type': 'integer', 'description': 'The numeric run id.'},
              },
              'required': ['repo', 'run_id'],
            },
          },
        },
        {
          'type': 'function',
          'function': {
            'name': 'retry_gitlab_pipeline',
            'description': 'REQUIRES USER APPROVAL. Retry a failed GitLab pipeline by its numeric id (see CI/CD timeline).',
            'parameters': {
              'type': 'object',
              'properties': {
                'project': {'type': 'string', 'description': 'group/project path or numeric id. Must be a tracked project.'},
                'pipeline_id': {'type': 'integer', 'description': 'The numeric pipeline id.'},
              },
              'required': ['project', 'pipeline_id'],
            },
          },
        },
        {
          'type': 'function',
          'function': {
            'name': 'create_github_issue',
            'description': 'REQUIRES USER APPROVAL. File a GitHub issue in a tracked repo (e.g. from an alert). Keep title short, body factual.',
            'parameters': {
              'type': 'object',
              'properties': {
                'repo': {'type': 'string', 'description': 'owner/repo. Must be a tracked repo.'},
                'title': {'type': 'string'},
                'body': {'type': 'string'},
                'labels': {
                  'type': 'array',
                  'items': {'type': 'string'},
                },
              },
              'required': ['repo', 'title'],
            },
          },
        },
      ];

  static const gated = {'restart_service', 'run_ssh_command', 'rerun_workflow', 'retry_gitlab_pipeline', 'create_github_issue'};

  /// Allowlist for run_ssh_command. Units: [a-zA-Z0-9@._:-]+, lines 1-200,
  /// ls restricted to absolute paths (no .., no ~, no $() or backticks).
  static final _allowedCmd = RegExp(
      r'^(systemctl (status|is-active) [A-Za-z0-9@._:\-]+'
      r'|journalctl --no-pager -u [A-Za-z0-9@._:\-]+( -n (?:[1-9]|[1-9][0-9]|1[0-9][0-9]|200))?'
      r'|ls -la? /(?:[A-Za-z0-9@._\-]+/)*[A-Za-z0-9@._\-]*'
      r'|cat /[A-Za-z0-9@._\-/]*\.(?:log|conf|yaml|yml|toml|json|service|timer)'
      r'|df -h'
      r'|uptime'
      r'|free -m)$');

  static final _unitName = RegExp(r'^[A-Za-z0-9@._:\-]+$');
}

/// Live state snapshot the tool executor reads from (built by the UI).
class ToolDeps {
  final List<ServerConnection> servers;
  final Map<String, Map<String, dynamic>> metrics;
  final Map<String, List<CronEntry>> crons;
  final Map<String, List<AppEntry>> apps;
  final Map<String, List<AlertEntry>> alerts;
  final List<GithubItem> issues;
  final List<GithubItem> prs;
  final List<GithubItem> tasks;
  final List<DeployItem> runs;
  final String githubToken;
  final List<String> githubRepos;
  final String gitlabToken;
  final String gitlabBaseUrl;
  final List<String> gitlabProjects;
  final AgentService agent;

  const ToolDeps({
    required this.servers,
    required this.metrics,
    required this.crons,
    required this.apps,
    required this.alerts,
    required this.issues,
    required this.prs,
    required this.tasks,
    required this.runs,
    required this.githubToken,
    required this.githubRepos,
    required this.gitlabToken,
    required this.gitlabBaseUrl,
    required this.gitlabProjects,
    required this.agent,
  });

  ServerConnection? findServer(String? name) {
    if (name == null || name.isEmpty) return null;
    final q = name.toLowerCase();
    for (final s in servers) {
      if (s.name.toLowerCase() == q) return s;
    }
    return null;
  }
}

class ToolResult {
  final String output;
  const ToolResult(this.output);
}

Future<ToolResult> executeTool(String name, Map<String, dynamic> args, ToolDeps d) async {
  switch (name) {
    case 'get_server_metrics': {
      final only = args['server']?.toString();
      final buf = StringBuffer();
      final found = only == null || only.isEmpty ? null : d.findServer(only);
      final targets = only == null || only.isEmpty ? d.servers : [if (found != null) found];
      if (targets.isEmpty) return ToolResult('No server named "$only". Known: ${d.servers.map((s) => s.name).join(', ')}');
      for (final s in targets) {
        final m = d.metrics[s.id];
        buf.writeln(m == null
            ? '${s.name}: no live metrics (agent not reachable)'
            : '${s.name}: cpu=${((m['cpu'] as num).toDouble() * 100).toInt()}% ram=${((m['ram'] as num).toDouble() * 100).toInt()}% disk=${((m['disk'] as num).toDouble() * 100).toInt()}% up=${m['uptime_days']}d');
      }
      return ToolResult(buf.toString().trim());
    }
    case 'list_crons': {
      final only = args['server']?.toString();
      final all = d.crons.values.expand((e) => e).toList();
      final list = only == null || only.isEmpty ? all : all.where((c) => c.serverName.toLowerCase() == only.toLowerCase()).toList();
      if (list.isEmpty) return const ToolResult('No cronjobs discovered.');
      return ToolResult(list.take(20).map((c) => '${c.command} [${c.schedule}] on ${c.serverName} (${c.source})').join('\n'));
    }
    case 'list_apps': {
      final only = args['server']?.toString();
      final all = d.apps.values.expand((e) => e).toList();
      final list = only == null || only.isEmpty ? all : all.where((a) => a.serverName.toLowerCase() == only.toLowerCase()).toList();
      if (list.isEmpty) return const ToolResult('No apps discovered.');
      return ToolResult(list.take(20).map((a) => '${a.name} — ${a.detail} on ${a.serverName} [${a.source}]').join('\n'));
    }
    case 'list_alerts': {
      final all = d.alerts.values.expand((e) => e).toList();
      if (all.isEmpty) return const ToolResult('No firing alerts — all healthy.');
      return ToolResult(all.map((a) => '${a.title} [${a.severity}] on ${a.serverName} (${a.source})').join('\n'));
    }
    case 'list_issues': {
      if (d.issues.isEmpty) return const ToolResult('No open issues.');
      return ToolResult(d.issues.take(15).map((i) => '#${i.number} ${i.title} (${i.repo}, by ${i.author}, ${i.comments} comments)').join('\n'));
    }
    case 'list_prs': {
      if (d.prs.isEmpty) return const ToolResult('No open PRs.');
      return ToolResult(d.prs.take(15).map((p) => '#${p.number} ${p.title} (${p.repo}, by ${p.author}, ${p.comments} comments)').join('\n'));
    }
    case 'get_workflow_runs': {
      if (d.runs.isEmpty) return const ToolResult('No workflow runs found.');
      return ToolResult(d.runs.take(10).map((r) => 'run_id=${r.runId} ${r.app} ${r.version} ${r.status} on ${r.env} by ${r.actor}').join('\n'));
    }
    case 'restart_service': {
      final s = d.findServer(args['server']?.toString());
      if (s == null) return ToolResult('Unknown server "${args['server']}". Known: ${d.servers.map((e) => e.name).join(', ')}');
      final unit = (args['unit'] ?? '').toString();
      if (!AiTools._unitName.hasMatch(unit)) return const ToolResult('Invalid service name.');
      try {
        final out = await d.agent.runCommand(s, 'sudo systemctl restart $unit && sleep 1 && systemctl is-active $unit');
        return ToolResult('restart $unit on ${s.name}:\n$out');
      } catch (e) {
        return ToolResult('restart failed: ${e.toString().split('\n').first}');
      }
    }
    case 'run_ssh_command': {
      final s = d.findServer(args['server']?.toString());
      if (s == null) return ToolResult('Unknown server "${args['server']}". Known: ${d.servers.map((e) => e.name).join(', ')}');
      final cmd = (args['command'] ?? '').toString().trim();
      if (!AiTools._allowedCmd.hasMatch(cmd)) {
        return const ToolResult('Command rejected by allowlist. Allowed: systemctl status|is-active <unit>, journalctl --no-pager -u <unit> -n <lines>, ls -l[a] <abs-path>, cat <abs-path> (.log/.conf/.yaml/.yml/.toml/.json/.service/.timer), df -h, uptime, free -m.');
      }
      try {
        final out = await d.agent.runCommand(s, cmd);
        return ToolResult('$cmd on ${s.name}:\n$out');
      } catch (e) {
        return ToolResult('command failed: ${e.toString().split('\n').first}');
      }
    }
    case 'rerun_workflow': {
      final repo = (args['repo'] ?? '').toString();
      final runId = (args['run_id'] as num?)?.toInt();
      if (!d.githubRepos.contains(repo)) return ToolResult('Repo "$repo" is not tracked. Tracked: ${d.githubRepos.join(', ')}');
      if (runId == null) return const ToolResult('Missing run_id.');
      if (d.githubToken.isEmpty) return const ToolResult('GitHub not connected.');
      try {
        await GithubService(d.githubToken).rerunRun(repo, runId);
        return ToolResult('Re-run accepted for $repo run $runId ✓ (check Actions for progress).');
      } catch (e) {
        return ToolResult('Rerun failed: ${e.toString().replaceFirst('Exception: ', '').split('\n').first}');
      }
    }
    case 'retry_gitlab_pipeline': {
      final project = (args['project'] ?? '').toString();
      final pipelineId = (args['pipeline_id'] as num?)?.toInt();
      if (!d.gitlabProjects.contains(project)) return ToolResult('Project "$project" is not tracked. Tracked: ${d.gitlabProjects.join(', ')}');
      if (pipelineId == null) return const ToolResult('Missing pipeline_id.');
      if (d.gitlabToken.isEmpty) return const ToolResult('GitLab not connected.');
      try {
        await GitlabService(baseUrl: d.gitlabBaseUrl, token: d.gitlabToken).retryPipeline(project, pipelineId);
        return ToolResult('Retry accepted for $project pipeline $pipelineId ✓ (check CI/CD for progress).');
      } catch (e) {
        return ToolResult('Retry failed: ${e.toString().replaceFirst('Exception: ', '').split('\n').first}');
      }
    }
    case 'create_github_issue': {
      final repo = (args['repo'] ?? '').toString();
      final title = (args['title'] ?? '').toString();
      if (!d.githubRepos.contains(repo)) return ToolResult('Repo "$repo" is not tracked. Tracked: ${d.githubRepos.join(', ')}');
      if (title.isEmpty) return const ToolResult('Missing title.');
      if (d.githubToken.isEmpty) return const ToolResult('GitHub not connected.');
      try {
        final n = await GithubService(d.githubToken).createIssue(
          repo,
          title,
          body: (args['body'] ?? '').toString(),
          labels: ((args['labels'] as List?) ?? []).map((e) => e.toString()).toList(),
        );
        return ToolResult('Issue created: $repo#$n ✓');
      } catch (e) {
        return ToolResult('Create failed: ${e.toString().replaceFirst('Exception: ', '').split('\n').first}');
      }
    }
    default:
      return ToolResult('Unknown tool: $name');
  }
}
