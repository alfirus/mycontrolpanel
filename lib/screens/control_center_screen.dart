import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:uuid/uuid.dart';
import '../theme/app_theme.dart';
import '../theme/design_tokens.dart';
import '../models/mock_data.dart';
import '../models/alert_entry.dart';
import '../models/app_entry.dart';
import '../models/app_proc.dart';
import '../models/cron_entry.dart';
import '../models/server_connection.dart';
import 'dart:convert';
import 'package:path_provider/path_provider.dart';
import '../services/agent_service.dart';
import '../services/ai_service.dart';
import '../services/secure_store.dart';
import '../widgets/cron_dialogs.dart';
import '../services/update_installer.dart';
import '../services/update_service.dart';
import '../services/ai_tools.dart';
import '../services/audit_log.dart';
import '../models/audit_entry.dart';
import '../services/github_service.dart';
import '../services/gitlab_service.dart';
import '../services/ssh_key_loader.dart';
import '../services/log_tail_service.dart';
import '../services/metrics_history.dart';
import '../services/alert_watch.dart';
import '../services/deployments_service.dart';
import 'server_details_screen.dart';
import '../widgets/pitch_card.dart';
import '../widgets/state_view.dart';
import '../widgets/run_detail_sheet.dart';
import 'audit_screen.dart';
import 'settings_screen.dart';
import 'terminal_screen.dart';

/// Bottom-nav primary destinations (spec `docs/design/03-navigation-ia.md`
/// F3). Every other destination lives behind the MORE overflow sheet, so no
/// destination is reachable on desktop but stranded on mobile. The grouping
/// IA itself is NOT decided here — that needs Lina's sign-off (spec 03 §3).
const primaryNavIndices = {0, 1, 4, 7, 11};
const overflowNavIndices = {2, 3, 5, 6, 8, 9, 10, 12};

class ControlCenterScreen extends StatefulWidget {
  const ControlCenterScreen({super.key});
  @override
  State<ControlCenterScreen> createState() => _ControlCenterScreenState();
}

class _ControlCenterScreenState extends State<ControlCenterScreen> {
  int _navIndex = 0;
  int _githubTab = 0;
  String _logFilter = 'ALL';
  String _serverFilter = 'all';
  final TextEditingController _chatController = TextEditingController();
  final List<Map<String, String>> _chatMessages = [
    {'role': 'assistant', 'text': 'Control Center AI online. I can see your live servers, alerts, crons, apps, GitHub and deploys — ask me anything, e.g. "which servers need attention?"'},
  ];
  final ScrollController _chatScroll = ScrollController();
  final ScrollController _logScroll = ScrollController();
  Timer? _logTimer;
  Timer? _autoTimer;
  DateTime? _lastAutoPoll;
  List<LogLine> _liveLogs = List.of(mockLogs);
  String _logSource = 'journal'; // journal | syslog | docker
  String _logContainer = '';
  bool _logLoading = false;
  String? _logError;
  String? _logServerId; // null = first saved server
  Map<String, List<double>> _latHistory = {}; // host -> recent latencies
  Map<String, List<double>> _cpuHistory = {}; // host -> recent cpu 0..1
  int _alertBadge = 0;
  List<ServerConnection> _savedServers = [];
  bool get _useRealServers => _savedServers.isNotEmpty;
  final _agent = AgentService();
  Map<String, Map<String, dynamic>> _metrics = {}; // server id -> {cpu,ram,disk,uptime_days}
  Set<String> _installing = {};
  Set<String> _checking = {};
  Map<String, List<CronEntry>> _serverCrons = {}; // server id -> discovered crons
  Set<String> _cronLoading = {};
  String? _cronError;
  Map<String, List<AppEntry>> _serverApps = {}; // server id -> discovered apps
  Set<String> _appLoading = {};
  String? _appError;
  List<AppEntry> get _realApps => _serverApps.values.expand((e) => e).toList();
  Map<String, AppStats> _procStats = {}; // server id -> APM-lite snapshot
  Map<String, List<AlertEntry>> _serverAlerts = {}; // server id -> harvested alerts
  Set<String> _alertLoading = {};
  String? _alertError;
  List<AlertEntry> get _realAlerts => _serverAlerts.values.expand((e) => e).toList();
  // AI provider state (Settings → Integrations)
  bool _aiConfigured = false;
  bool _aiWriteEnabled = false; // write tools kill-switch (default OFF)
  String _aiModelName = '';
  AiProvider _aiProvider = AiProvider.openai;
  String _aiBaseUrl = '';
  String _aiKey = '';
  bool _aiTyping = false;
  String _aiSessionId = ''; // stable x-opencode-session for Go/Zen routing + caching
  // Update state (GitHub Releases, desktop)
  ReleaseInfo? _updateRel;
  bool _updateChecking = false;
  bool _updateAutoChecked = false;
  // GitHub live state (PAT + repos from Settings)
  String _ghToken = '';
  String _ghUser = '';
  List<String> _ghRepos = [];
  List<GithubItem> _ghIssues = [];
  List<GithubItem> _ghPRs = [];
  List<GithubItem> _ghTasks = [];
  List<Map<String, dynamic>> _ghProjects = [];
  String _ghTasksSource = ''; // 'projects' or 'assigned'
  bool get _ghTasksFromProjects => _ghTasksSource == 'projects';
  bool _ghLoading = false;
  String? _ghError;
  bool get _ghConfigured => _ghToken.isNotEmpty && _ghRepos.isNotEmpty;
  List<DeployItem> _ghRuns = [];
  // GitLab live state (PAT + base URL + projects from Settings)
  int _gitlabTab = 0; // 0 issues, 1 MRs, 2 tasks
  String _glToken = '';
  String _glUser = '';
  String _glBase = 'https://gitlab.com';
  List<String> _glProjects = [];
  List<GithubItem> _glIssues = [];
  List<GithubItem> _glMrs = [];
  List<GithubItem> _glTasks = [];
  List<DeployItem> _glPipes = [];
  bool _glLoading = false;
  String? _glError;
  bool get _glConfigured => _glToken.isNotEmpty && _glProjects.isNotEmpty;
  String? _terminalServerId;
  String? _terminalPrefill;
  int _terminalKey = 0;

  List<ServerInfo> get _servers => _useRealServers
      ? _savedServers.map((c) => ServerInfo(
            id: c.id, name: c.name, ip: c.host, region: c.region, os: c.os,
            cpu: 0, ram: 0, disk: 0, latencyMs: 0,
            status: c.enabled ? Status.operational : Status.maintenance,
            uptimeDays: 0, sparkline: const [0,0,0,0,0,0,0,0,0],
          )).toList()
      : mockServers;

  Future<void> _loadSavedServers() async {
    await SecureStore.migrateIfNeeded();
    final prefs = await SharedPreferences.getInstance();
    final servers = await SecureStore.readServers();
    if (!mounted) return;
    setState(() {
      _savedServers = servers;
      _ghUser = prefs.getString('github_user') ?? '';
      _ghRepos = prefs.getStringList('github_repos') ?? [];
      _aiModelName = prefs.getString('ai_model') ?? '';
      _aiWriteEnabled = prefs.getBool('ai_write_enabled') ?? false;
      _aiSessionId = prefs.getString('ai_session_id') ?? '';
      if (_aiSessionId.isEmpty) {
        _aiSessionId = const Uuid().v4();
        unawaited(prefs.setString('ai_session_id', _aiSessionId));
      }
      _aiProvider = AiProvider.values[(prefs.getInt('ai_provider') ?? 0).clamp(0, AiProvider.values.length - 1)];
      _aiBaseUrl = prefs.getString('ai_base_url') ?? _aiProvider.defaultBaseUrl;
      _aiConfigured = _aiModelName.isNotEmpty;
      _glUser = prefs.getString('gitlab_user') ?? '';
      _glBase = prefs.getString('gitlab_base_url') ?? 'https://gitlab.com';
      _glProjects = prefs.getStringList('gitlab_projects') ?? [];
    });
    // secrets (keychain) resolve async after first paint
    final ghTok = await SecureStore.readSecret('github_token') ?? '';
    final glTok = await SecureStore.readSecret('gitlab_token') ?? '';
    final aiK = await SecureStore.readSecret('ai_key') ?? '';
    if (!mounted) return;
    setState(() {
      _ghToken = ghTok;
      _glToken = glTok;
      _aiKey = aiK;
    });
    _pollAgents();
    _pollGithub();
    _pollGitlab();
  }

  /// Fetch live GitHub Issues/PRs/Tasks/Runs for tracked repos.
  /// Validates the token first so auth failures surface instead of
  /// silently falling back to demo data.
  Future<void> _pollGithub() async {
    if (!_ghConfigured || _ghLoading) return;
    setState(() { _ghLoading = true; _ghError = null; });
    try {
      final svc = GithubService(_ghToken);
      await svc.validate();
      final issues = <GithubItem>[], prs = <GithubItem>[];
      for (final repo in _ghRepos) {
        try { issues.addAll(await svc.repoIssues(repo)); } catch (_) {}
        try { prs.addAll(await svc.repoPRs(repo)); } catch (_) {}
      }
      issues.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      prs.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      // Tasks prefer Projects v2 boards; fall back to assigned issues.
      List<GithubItem> tasks = [];
      var tasksSource = '';
      List<Map<String, dynamic>> projects = [];
      try {
        projects = await svc.projectsV2();
      } catch (_) {}
      try {
        tasks = await svc.projectTasks();
        if (tasks.isNotEmpty) tasksSource = 'projects';
      } catch (_) {}
      if (tasks.isEmpty) {
        try {
          tasks = await svc.myTasks(_ghRepos);
          if (tasks.isNotEmpty) tasksSource = 'assigned';
        } catch (_) {}
      }
      final runs = <DeployItem>[];
      for (final repo in _ghRepos) {
        try { for (final d in await svc.repoRuns(repo)) { runs.add(d.withRepo(repo)); } } catch (_) {}
      }
      runs.sort((a, b) => b.time.compareTo(a.time));
      if (!mounted) return;
      setState(() {
        _ghIssues = issues;
        _ghPRs = prs;
        _ghTasks = tasks;
        _ghTasksSource = tasksSource;
        _ghProjects = projects;
        _ghRuns = runs.take(12).toList();
        _ghLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _ghLoading = false;
        _ghError = e.toString().replaceFirst('Exception: ', '').split('\n').first;
      });
    }
  }

  /// Fetch live GitLab Issues/MRs/Tasks for tracked projects.
  Future<void> _pollGitlab() async {
    if (!_glConfigured || _glLoading) return;
    setState(() { _glLoading = true; _glError = null; });
    try {
      final svc = GitlabService(baseUrl: _glBase, token: _glToken);
      await svc.validate();
      final issues = <GithubItem>[], mrs = <GithubItem>[];
      for (final p in _glProjects) {
        try { issues.addAll(await svc.projectIssues(p)); } catch (_) {}
        try { mrs.addAll(await svc.projectMRs(p)); } catch (_) {}
      }
      issues.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      mrs.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      List<GithubItem> tasks = [];
      try { tasks = await svc.myTasks(_glProjects); } catch (_) {}
      final pipes = <DeployItem>[];
      for (final p in _glProjects) {
        try { pipes.addAll(await svc.projectPipelines(p)); } catch (_) {}
      }
      pipes.sort((a, b) => b.time.compareTo(a.time));
      if (!mounted) return;
      setState(() {
        _glIssues = issues;
        _glMrs = mrs;
        _glTasks = tasks;
        _glPipes = pipes.take(12).toList();
        _glLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _glLoading = false;
        _glError = e.toString().replaceFirst('Exception: ', '').split('\n').first;
      });
    }
  }

  bool _agentsPolling = false;

  Future<void> _pollAgents() async {
    if (_agentsPolling) return; // re-entrancy guard for the interval timer
    _agentsPolling = true;
    try {
      for (final c in _savedServers) {
        final sw = Stopwatch()..start();
        final m = await _agent.fetch(c.host);
        sw.stop();
        if (!mounted) return;
        if (m != null) {
          setState(() => _metrics[c.id] = m);
          final cpu = (((m['cpu'] as num?) ?? 0).toDouble()).clamp(0.0, 1.0).toDouble();
          final ram = (((m['ram'] as num?) ?? 0).toDouble()).clamp(0.0, 1.0).toDouble();
          final disk = (((m['disk'] as num?) ?? 0).toDouble()).clamp(0.0, 1.0).toDouble();
          unawaited(MetricsHistory.record(c.host, cpu, ram, disk, sw.elapsedMilliseconds.toDouble()));
          if (mounted) {
            setState(() {
              _latHistory[c.host] = [...?_latHistory[c.host], sw.elapsedMilliseconds.toDouble()].take(40).toList();
              _cpuHistory[c.host] = [...?_cpuHistory[c.host], cpu].take(40).toList();
            });
          }
        }
        final ps = await _agent.fetchAppStats(c.host);
        if (!mounted) return;
        if (ps != null) {
          setState(() => _procStats[c.id] = ps);
        } else {
          if (mounted) setState(() => _procStats.remove(c.id));
        }
      }
      _pollCrons();
      _pollApps();
      _pollAlerts();
      _updateAlertBadge();
      _pollRealLogs();
    } finally {
      _agentsPolling = false;
    }
  }

  /// Foreground alert watcher: badge + snack on new firing alerts / failed runs.
  Future<void> _updateAlertBadge() async {
    try {
      final keys = AlertWatch.currentKeys(_realAlerts, _allRuns);
      final seen = await _readSeenKeys();
      final fresh = AlertWatch.freshTitles(keys, seen, _realAlerts, _allRuns);
      if (!mounted) return;
      setState(() => _alertBadge = keys.length);
      await AlertWatch.markSeen(keys);
      if (fresh.isNotEmpty && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('⚠ ${fresh.first}${fresh.length > 1 ? ' (+${fresh.length - 1} more)' : ''}'), backgroundColor: AppColors.critical, duration: const Duration(seconds: 4)),
        );
      }
    } catch (_) {}
  }

  Future<Set<String>> _readSeenKeys() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getStringList('alert_watch_seen_v1')?.toSet() ?? {};
    } catch (_) {
      return {};
    }
  }

  /// Real log tail for the selected saved server (read-only SSH).
  /// Runs on each agent poll tick; silent on failure (keeps last logs).
  Future<void> _pollRealLogs() async {
    if (!_useRealServers || _logLoading) return;
    final matches = _logServerId == null
        ? _savedServers
        : _savedServers.where((s) => s.id == _logServerId).toList();
    if (matches.isEmpty) return;
    final server = matches.first;
    var container = _logContainer;
    if (_logSource == 'docker' && container.isEmpty) {
      for (final a in _realApps) {
        if (a.source == 'docker' && a.serverId == server.id) { container = a.name; break; }
      }
      if (container.isEmpty) {
        for (final a in _realApps) {
          if (a.source == 'docker') { container = a.name; break; }
        }
      }
    }
    setState(() { _logLoading = true; _logError = null; });
    try {
      final lines = await LogTailService().fetch(
        _agent, server, container,
        source: _logSource, lines: 100,
      );
      if (!mounted) return;
      setState(() {
        if (lines.isNotEmpty) _liveLogs = lines.take(40).toList();
        _logLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _logLoading = false;
        _logError = e.toString().replaceFirst('Exception: ', '').split('\n').first;
      });
    }
  }

  /// Harvest alert signals from all saved servers (best-effort).
  Future<void> _pollAlerts() async {
    for (final c in _savedServers) {
      if (_alertLoading.contains(c.id) || _serverAlerts.containsKey(c.id)) continue;
      setState(() => _alertLoading.add(c.id));
      try {
        final entries = await _agent.fetchAlerts(c);
        if (!mounted) return;
        setState(() {
          _serverAlerts[c.id] = entries;
          _alertLoading.remove(c.id);
        });
      } catch (e) {
        if (!mounted) return;
        setState(() {
          _alertLoading.remove(c.id);
          _alertError = e.toString().split('\n').first;
        });
      }
    }
  }

  /// Discover apps on all saved servers (best-effort, silent on failure).
  Future<void> _pollApps() async {
    for (final c in _savedServers) {
      if (_appLoading.contains(c.id) || _serverApps.containsKey(c.id)) continue;
      setState(() => _appLoading.add(c.id));
      try {
        final entries = await _agent.fetchApps(c);
        if (!mounted) return;
        setState(() {
          _serverApps[c.id] = entries;
          _appLoading.remove(c.id);
        });
      } catch (e) {
        if (!mounted) return;
        setState(() {
          _appLoading.remove(c.id);
          _appError = e.toString().split('\n').first;
        });
      }
    }
  }

  /// Discover crontabs on all saved servers (best-effort, silent on failure).
  /// Tap a cronjob → LOG / EDIT dialogs. Rescans that server on change.
  void _openCron(CronEntry e) {
    final matches = _savedServers.where((s) => s.id == e.serverId).toList();
    if (matches.isEmpty) return;
    final conn = matches.first;
    showCronActions(
      context,
      entry: e,
      conn: conn,
      agent: _agent,
      askPassphrase: () => _cachedPassphrase(conn, actionLabel: 'VIEW LOG'),
      onBadPassphrase: () => _forgetPassphrase(conn.id),
      onChanged: () {
        setState(() {
          _serverCrons.remove(conn.id);
          _cronError = null;
        });
        _pollCrons();
      },
    );
  }

  Future<void> _pollCrons() async {
    for (final c in _savedServers) {
      if (_cronLoading.contains(c.id) || _serverCrons.containsKey(c.id)) continue;
      setState(() => _cronLoading.add(c.id));
      try {
        final entries = await _agent.fetchCrons(c);
        if (!mounted) return;
        setState(() {
          _serverCrons[c.id] = entries;
          _cronLoading.remove(c.id);
        });
      } catch (e) {
        if (!mounted) return;
        setState(() {
          _cronLoading.remove(c.id);
          _cronError = e.toString().split('\n').first;
        });
      }
    }
  }

  Future<void> _installAgent(ServerConnection s) async {
    // Re-entrancy guard: double-taps used to stack duplicate passphrase
    // dialogs, making Cancel/Install appear dead (they only closed the top copy).
    if (_installing.contains(s.id)) return;
    setState(() => _installing.add(s.id));
    try {
      await _installAgentGuarded(s);
    } finally {
      if (mounted) setState(() => _installing.remove(s.id));
    }
  }

  Future<void> _installAgentGuarded(ServerConnection s) async {
    // Key auth: resolve the key first (passphrase prompt if encrypted).
    // Only falls back to the guided manual install when the key can't be
    // loaded at all (e.g. unreadable path). Otherwise one-click runs directly.
    String? keyPassphrase;
    if (s.authMethod != AuthMethod.password) {
      final pre = await SshKeyLoader.load(s.credential);
      if (pre.keys == null && pre.needsPassphrase) {
        keyPassphrase = await _cachedPassphrase(s);
        if (keyPassphrase == null || keyPassphrase.isEmpty) return; // cancelled
      } else if (pre.keys == null) {
        _showManualInstall(s);
        return;
      }
    }
    final logLines = <String>[];
    String status = 'Starting...';
    // progress dialog
    if (mounted) {
      showDialog(
        context: context, barrierDismissible: false,
        builder: (ctx) => StatefulBuilder(builder: (ctx, setD) {
          void onLog(String l) { logLines.add(l); setD(() => status = l.split('\n').last); }
          // kick off install once — fully guarded: nothing may fail silently
          if (logLines.isEmpty) {
            () async {
              AgentInstallResult? r;
              Object? crash;
              try {
                r = await _agent.install(s, onLog, keyPassphrase: keyPassphrase);
                if (r.success && mounted) {
                  try {
                    final m = await _agent.fetch(s.host);
                    if (m != null && mounted) setState(() => _metrics[s.id] = m);
                  } catch (_) {
                    // metrics poll is best-effort; install already succeeded
                  }
                }
              } catch (e) {
                crash = e;
              }
              if (!mounted) return;
              // Always dismiss the progress dialog; _installing reset by caller finally.
              // Await the pop transition: pushing the next dialog in the same
              // frame trips Navigator._debugLocked ("is not true").
              await _dismissDialog();
              if (!mounted) return;
              if (crash != null) {
                _showInstallLog(s, 'Unexpected error (please report):\n$crash');
                return;
              }
              final result = r!;
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                backgroundColor: result.success ? AppColors.success.withValues(alpha: 0.14) : AppColors.critical.withValues(alpha: 0.14),
                content: Text(result.success ? 'Agent installed on ${s.host} — live metrics flowing ✓' : 'Install failed on ${s.host}. Log opened with details.',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: result.success ? AppColors.success : AppColors.critical)),
                duration: const Duration(seconds: 4),
              ));
              if (!result.success) {
                if (result.log == 'SSH_KEY_AUTH') {
                  _showManualInstall(s);
                } else if (result.log == 'SSH_KEY_BAD_PASSPHRASE') {
                  _forgetPassphrase(s.id); // cached phrase was wrong — ask again next time
                  _showInstallLog(s, 'Wrong key passphrase. Tap INSTALL AGENT to retry with the correct one, or use the manual install.');
                } else if (result.log == 'SSH_KEY_NEEDS_PASSPHRASE') {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(backgroundColor: AppColors.surface1, content: Text('Key needs a passphrase — enter it to retry one-click, or use manual install.', style: TextStyle(fontSize: 12, color: AppColors.warning)), duration: Duration(seconds: 4)));
                  _showManualInstall(s);
                } else {
                  _showInstallLog(s, result.log);
                }
              }
            }();
          }
          return AlertDialog(
            backgroundColor: AppColors.surface1,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: const BorderSide(color: AppColors.border)),
            title: Row(children: [const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.accentCyan)), const SizedBox(width: 10), Expanded(child: Text('Installing agent on ${s.host}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textPrimary)))]),
            content: SizedBox(width: 320, child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(status, style: const TextStyle(fontSize: 11, color: AppColors.textSecondary, fontFamily: AppFonts.mono), maxLines: 4, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 8),
              const LinearProgressIndicator(color: AppColors.accentCyan, backgroundColor: AppColors.surface2),
              const SizedBox(height: 8),
              const Text('Uploads /opt/mcp-agent/agent.py + systemd unit, opens TCP 9108.', style: TextStyle(fontSize: 10, color: AppColors.textDim)),
            ])),
          );
        }),
      );
    }
  }

  /// In-memory passphrase cache: prompt once per app run per server.
  final Map<String, String> _passCache = {};
  void _forgetPassphrase(String serverId) => _passCache.remove(serverId);

  Future<String?> _cachedPassphrase(ServerConnection s, {String actionLabel = 'INSTALL NOW'}) async {
    final hit = _passCache[s.id];
    if (hit != null && hit.isNotEmpty) return hit;
    final pass = await _askKeyPassphrase(s, actionLabel: actionLabel);
    if (pass != null && pass.isNotEmpty) _passCache[s.id] = pass;
    return pass;
  }

  Future<String?> _askKeyPassphrase(ServerConnection s, {String actionLabel = 'INSTALL NOW'}) async {
    final c = TextEditingController();
    final cred = s.credential.trim();
    final isPath = !cred.contains('PRIVATE KEY') && !cred.contains('OPENSSH');
    final desc = isPath
        ? 'Saved as file path (sandbox may block reads — prefer import)'
        : SshKeyLoader.describe(cred);
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface1,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: AppColors.accentCyan.withValues(alpha: 0.3))),
        title: Text('Key passphrase — ${s.host}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
        content: SizedBox(
          width: 320,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              decoration: BoxDecoration(color: AppColors.surface2, borderRadius: BorderRadius.circular(6), border: Border.all(color: AppColors.border)),
              child: Row(children: [
                const Icon(Icons.fingerprint, size: 13, color: AppColors.accentCyan),
                const SizedBox(width: 6),
                Expanded(child: Text(desc, style: const TextStyle(fontSize: 10, color: AppColors.textSecondary, fontFamily: AppFonts.mono))),
              ]),
            ),
            const SizedBox(height: 8),
            const Text('This exact key is encrypted. Enter ITS passphrase (not the server login password).', style: TextStyle(fontSize: 11, color: AppColors.textSecondary)),
            const SizedBox(height: 10),
            TextField(controller: c, obscureText: true, autofocus: true, style: const TextStyle(fontSize: 12, color: AppColors.textPrimary, fontFamily: AppFonts.mono), decoration: InputDecoration(hintText: 'Key passphrase', hintStyle: const TextStyle(fontSize: 11, color: AppColors.textMuted), filled: true, fillColor: AppColors.surface2, contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10), border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AppColors.border)), enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AppColors.border)), focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AppColors.accentCyan)))),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('CANCEL', style: TextStyle(color: AppColors.textSecondary))),
          FilledButton(onPressed: () => Navigator.pop(ctx, c.text), style: FilledButton.styleFrom(backgroundColor: AppColors.accentCyan, foregroundColor: Colors.black), child: Text(actionLabel, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800))),
        ],
      ),
    );
  }

  /// Guided manual install for SSH-key / non-password connections.
  /// Shows steps + copyable one-liner + Open Terminal + Verify buttons.
  void _showManualInstall(ServerConnection s) {
    final script = AgentService.manualInstallScript();
    final steps = AgentService.manualSteps(s);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface1,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: const BorderSide(color: AppColors.border)),
        title: Row(children: [
          Container(width: 30, height: 30, decoration: BoxDecoration(color: AppColors.warning.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(7)), child: const Icon(Icons.terminal, size: 15, color: AppColors.warning)),
          const SizedBox(width: 10),
          Expanded(child: Text('Manual install — ${s.host}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textPrimary))),
          IconButton(onPressed: () => Navigator.pop(ctx), icon: const Icon(Icons.close, size: 16, color: AppColors.textMuted)),
        ]),
        content: SizedBox(
          width: 460, height: 420,
          child: SingleChildScrollView(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: AppColors.warning.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(8), border: Border.all(color: AppColors.warning.withValues(alpha: 0.2))), child: const Text('One-click install needs password auth. Your connection uses SSH key — follow the guided steps below (60 seconds).', style: TextStyle(fontSize: 11, color: AppColors.textSecondary))),
            const SizedBox(height: 10),
            for (final st in steps)
              Padding(padding: const EdgeInsets.only(bottom: 6), child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Container(margin: const EdgeInsets.only(top: 2), width: 6, height: 6, decoration: const BoxDecoration(color: AppColors.accentCyan, shape: BoxShape.circle)),
                const SizedBox(width: 8),
                Expanded(child: SelectableText(st, style: const TextStyle(fontSize: 11, color: AppColors.textPrimary, fontFamily: AppFonts.mono))),
              ])),
            const SizedBox(height: 8),
            const Text('INSTALL COMMAND (tap to copy)', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 0.6, color: AppColors.textMuted)),
            const SizedBox(height: 4),
            InkWell(
              onTap: () {
                Clipboard.setData(ClipboardData(text: script));
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(backgroundColor: AppColors.surface1, content: Text('Install command copied — paste it into your SSH terminal', style: TextStyle(fontSize: 12, color: AppColors.accentCyan)), duration: Duration(seconds: 2)));
              },
              child: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: const Color(0xFF050505), borderRadius: BorderRadius.circular(8), border: Border.all(color: AppColors.border)),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Icon(Icons.copy, size: 13, color: AppColors.accentCyan),
                  const SizedBox(width: 8),
                  Expanded(child: Text(script, style: const TextStyle(fontSize: 9, color: Color(0xFFE4E4E7), fontFamily: AppFonts.mono), maxLines: 6, overflow: TextOverflow.ellipsis)),
                ]),
              ),
            ),
            const SizedBox(height: 6),
            const Text('Requires: python3 + systemd + sudo on the server. Opens TCP 9108 for /metrics.', style: TextStyle(fontSize: 10, color: AppColors.textDim)),
          ])),
        ),
        actions: [
          TextButton.icon(onPressed: () { Navigator.pop(ctx); _openInAppTerminal(s); }, icon: const Icon(Icons.terminal, size: 14), label: const Text('OPEN TERMINAL', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800)), style: TextButton.styleFrom(foregroundColor: AppColors.accentCyan)),
          TextButton.icon(onPressed: () { Clipboard.setData(ClipboardData(text: script)); ScaffoldMessenger.of(context).showSnackBar(const SnackBar(backgroundColor: AppColors.surface1, content: Text('Copied ✓', style: TextStyle(color: AppColors.accentCyan)))); }, icon: const Icon(Icons.copy, size: 14), label: const Text('COPY', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800)), style: TextButton.styleFrom(foregroundColor: AppColors.accentCyan)),
          FilledButton(onPressed: () async {
            Navigator.pop(ctx);
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(backgroundColor: AppColors.surface1, content: Text('Verifying agent...', style: TextStyle(fontSize: 12, color: AppColors.textSecondary))));
            final m = await _agent.fetch(s.host);
            if (!mounted) return;
            if (m != null) {
              setState(() => _metrics[s.id] = m);
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(backgroundColor: AppColors.success.withValues(alpha: 0.14), content: Text('Agent live on ${s.host} ✓ cpu=${m['cpu']} ram=${m['ram']}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.success))));
            } else {
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(backgroundColor: AppColors.critical.withValues(alpha: 0.14), content: Text('Cannot reach http://${s.host}:9108/metrics — check the install ran + firewall open.', style: const TextStyle(fontSize: 12, color: AppColors.critical)), duration: const Duration(seconds: 5)));
              _showManualInstall(s);
            }
          }, style: FilledButton.styleFrom(backgroundColor: AppColors.accentCyan, foregroundColor: Colors.black), child: const Text('VERIFY', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800))),
        ],
      ),
    );
  }

  // OPEN TERMINAL now opens the BUILT-IN terminal (not the OS one),
  // preselected to this server with the install command ready to run.
  void _openInAppTerminal(ServerConnection s) {
    setState(() {
      _navIndex = 12;
      _terminalServerId = s.id;
      _terminalPrefill = AgentService.manualInstallScript();
      _terminalKey++; // force rebuild with new prefill
    });
    _loadSavedServers();
  }

  void _showInstallLog(ServerConnection s, String log) {
    showDialog(context: context, builder: (ctx) => AlertDialog(
      backgroundColor: AppColors.surface1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: const BorderSide(color: AppColors.border)),
      title: Text('Install log — ${s.host}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
      content: SizedBox(width: 380, height: 300, child: SingleChildScrollView(child: SelectableText(log, style: const TextStyle(fontSize: 10, color: AppColors.textSecondary, fontFamily: AppFonts.mono)))),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('CLOSE', style: TextStyle(color: AppColors.textSecondary))),
        FilledButton(onPressed: () { Navigator.pop(ctx); _installAgent(s); }, style: FilledButton.styleFrom(backgroundColor: AppColors.accentCyan, foregroundColor: Colors.black), child: const Text('RETRY')),
      ],
    ));
  }

  Widget _realServerBody(ServerConnection c, ServerInfo s, bool compact) {
    final m = _metrics[c.id];
    if (m != null) {
      final cpu = (m['cpu'] as num).toDouble(), ram = (m['ram'] as num).toDouble(), disk = (m['disk'] as num).toDouble();
      return Column(children: [
        Row(children: [
          // Spec 02 §2.3: shared AppThresholds at every call site; hue means
          // state, not metric — sub-threshold bars share one neutral color.
          Expanded(child: MetricBar(label: 'CPU', value: cpu, color: cpu > AppThresholds.cpuCritical ? AppColors.critical : AppColors.textSecondary)),
          const SizedBox(width: 8),
          Expanded(child: MetricBar(label: 'RAM', value: ram, color: ram > AppThresholds.ramCritical ? AppColors.critical : AppColors.textSecondary)),
          const SizedBox(width: 8),
          Expanded(child: MetricBar(label: 'DISK', value: disk, color: disk > AppThresholds.diskCritical ? AppColors.critical : disk > AppThresholds.diskWarn ? AppColors.warning : AppColors.textSecondary)),
        ]),
        const SizedBox(height: 6),
        // Spec 02 parity rule: the live card renders the same five bands in
        // the same order as demo — this is band 4 (trend), fed by the
        // in-memory poll history. Omitted until 2+ polls; never faked.
        // Bands 1-2 (header + reachability) render above via the caller, so
        // the no-agent box below likewise never replaces them.
        Builder(builder: (_) {
          final pts = trendPoints(_cpuHistory[c.host] ?? []);
          if (pts.isEmpty) return const SizedBox.shrink();
          final peak = sparklineP95(pts);
          return Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: SizedBox(height: compact ? 18 : 24, child: Row(children: [
              Expanded(child: _miniSparkline(pts, s.status == Status.degraded ? AppColors.warning : AppColors.success)),
              const SizedBox(width: 8),
              Semantics(
                label: 'CPU trend, peak $peak percent over recent polls',
                child: Text('cpu p95 $peak%', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: AppColors.textSecondary)),
              ),
            ])),
          );
        }),
        Row(children: [
          Container(width: 6, height: 6, decoration: const BoxDecoration(color: AppColors.success, shape: BoxShape.circle)),
          const SizedBox(width: 6),
          // Spec 02 §2.5: footer grows to 11px; uptime is its own segment.
          Text('LIVE • agent :9108', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.success, letterSpacing: 0.4)),
          const SizedBox(width: 8),
          Text('UPTIME ${m['uptime_days']}d', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: AppColors.textPrimary, letterSpacing: 0.4)),
          const Spacer(),
          InkWell(onTap: () => _pollAgents(), child: const Row(children: [Icon(Icons.refresh, size: 11, color: AppColors.textMuted), SizedBox(width: 3), Text('REFRESH', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w800, color: AppColors.textMuted))])),
        ]),
      ]);
    }
    final busy = _installing.contains(c.id);
    final checking = _checking.contains(c.id);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: BoxDecoration(color: AppColors.surface2, borderRadius: BorderRadius.circular(6), border: Border.all(color: AppColors.border)),
      child: Column(children: [
        Row(children: [
          const Icon(Icons.sensors_off_outlined, size: 14, color: AppColors.warning),
          const SizedBox(width: 8),
          const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('No metrics agent', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
            Text('Install ran but app cannot see :9108? Tap CHECK.', style: TextStyle(fontSize: 9, color: AppColors.textMuted)),
          ])),
        ]),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(
            child: FilledButton.icon(
              onPressed: busy ? null : () => _installAgent(c),
              icon: busy ? const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black)) : const Icon(Icons.download, size: 12),
              label: Text(busy ? 'INSTALLING' : 'INSTALL AGENT', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w800)),
              style: FilledButton.styleFrom(backgroundColor: AppColors.accentCyan, foregroundColor: Colors.black, padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(7))),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: OutlinedButton.icon(
              onPressed: (busy || checking) ? null : () => _checkAgent(c),
              icon: checking ? const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.accentCyan)) : const Icon(Icons.radar, size: 12),
              label: Text(checking ? 'CHECKING' : 'CHECK :9108', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w800)),
              style: OutlinedButton.styleFrom(foregroundColor: AppColors.accentCyan, side: const BorderSide(color: AppColors.accentCyan), padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(7))),
            ),
          ),
        ]),
      ]),
    );
  }

  /// Diagnose why :9108 isn't visible: agent down vs firewall vs wrong host.
  Future<void> _checkAgent(ServerConnection c) async {
    setState(() => _checking.add(c.id));
    String verdict;
    final m = await _agent.fetch(c.host);
    if (m != null) {
      if (mounted) setState(() { _metrics[c.id] = m; _checking.remove(c.id); });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(backgroundColor: AppColors.success.withValues(alpha: 0.14), content: Text('Agent live on ${c.host} ✓ cpu=${m['cpu']} ram=${m['ram']} disk=${m['disk']}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.success))));
      return;
    }
    // fetch failed — is TCP even open?
    try {
      final sock = await Socket.connect(c.host, AgentService.agentPort, timeout: const Duration(seconds: 5));
      sock.destroy();
      verdict = 'TCP ${AgentService.agentPort} OPEN but /metrics bad — agent crashed? On server: sudo systemctl status mcp-agent --no-pager && sudo journalctl -u mcp-agent -n 30 --no-pager';
    } on SocketException catch (e) {
      final msg = e.osError?.message ?? e.message;
      if (msg.contains('refused')) {
        verdict = 'Connection REFUSED on ${c.host}:${AgentService.agentPort} — agent not running. On server run: sudo systemctl status mcp-agent --no-pager (start with: sudo systemctl restart mcp-agent). Did the install finish with AGENT_OK?';
      } else if (msg.contains('imeout')) {
        verdict = 'TIMEOUT reaching ${c.host}:${AgentService.agentPort} — firewall/security group blocking, or wrong host IP. Open TCP ${AgentService.agentPort} (AWS: security group inbound; ufw: sudo ufw allow ${AgentService.agentPort}/tcp).';
      } else {
        verdict = 'Network error ($msg). Check the host/IP and that this machine can route to it.';
      }
    } catch (e) {
      verdict = 'Check failed: $e';
    }
    if (mounted) setState(() => _checking.remove(c.id));
    if (!mounted) return;
    showDialog(context: context, builder: (ctx) => AlertDialog(
      backgroundColor: AppColors.surface1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: const BorderSide(color: AppColors.border)),
      title: Row(children: [Container(width: 30, height: 30, decoration: BoxDecoration(color: AppColors.warning.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(7)), child: const Icon(Icons.radar, size: 15, color: AppColors.warning)), const SizedBox(width: 10), Expanded(child: Text('Agent check — ${c.host}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textPrimary)))]),
      content: SizedBox(width: 380, child: SelectableText(verdict, style: const TextStyle(fontSize: 11, height: 1.4, color: AppColors.textSecondary, fontFamily: AppFonts.mono))),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('CLOSE', style: TextStyle(color: AppColors.textSecondary))),
        TextButton.icon(onPressed: () { Navigator.pop(ctx); _openInAppTerminal(c); }, icon: const Icon(Icons.terminal, size: 14), label: const Text('OPEN TERMINAL', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800)), style: TextButton.styleFrom(foregroundColor: AppColors.accentCyan)),
      ],
    ));
  }

  void _goTo(int i) {
    setState(() => _navIndex = i);
    _loadSavedServers();
    if (i == 0) _maybeAutoCheckUpdates();
  }

  /// Auto-check once per startup when enabled (desktop only).
  Future<void> _maybeAutoCheckUpdates() async {
    if (_updateAutoChecked) return;
    _updateAutoChecked = true;
    if (!(Platform.isMacOS || Platform.isWindows || Platform.isLinux)) return;
    SharedPreferences? prefs;
    try {
      prefs = await SharedPreferences.getInstance();
    } catch (_) {
      return;
    }
    if (!(prefs.getBool('auto_update_check') ?? true)) return;
    await checkForUpdates(manual: false);
  }

  /// Check GitHub Releases for a newer version. Sets [_updateRel] when an
  /// update is pending (and not skipped). Safe to call repeatedly.
  Future<void> checkForUpdates({bool manual = false}) async {
    if (_updateChecking) return;
    if (!Platform.isMacOS && !Platform.isWindows && !Platform.isLinux) return;
    setState(() => _updateChecking = true);
    try {
      final svc = UpdateService();
      final rel = await svc.fetchLatest();
      final cur = await svc.currentVersion();
      final prefs = await SharedPreferences.getInstance();
      final skipped = prefs.getString('skipped_update_tag') ?? '';
      if (!mounted) return;
      setState(() {
        _updateChecking = false;
        if (rel.tag.isNotEmpty &&
            UpdateService.compareVersions(cur, rel.version) < 0 &&
            rel.tag != skipped &&
            UpdateService.pickAsset(rel) != null) {
          _updateRel = rel;
        } else {
          if (manual) _updateRel = null;
        }
      });
      if (manual && mounted) {
        final r = _updateRel;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          backgroundColor: AppColors.surface1,
          content: Text(
              r == null ? 'Up to date (v$cur) ✓' : 'v${r.version} available — tap UPDATE below',
              style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
        ));
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _updateChecking = false);
      if (manual) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          backgroundColor: AppColors.surface1,
          content: Text('Update check failed: ${e.toString().split('\n').first}',
              style: const TextStyle(fontSize: 12, color: AppColors.critical)),
        ));
      }
    }
  }

  Future<void> _skipUpdateVersion() async {
    final tag = _updateRel?.tag;
    if (tag == null) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('skipped_update_tag', tag);
    if (!mounted) return;
    setState(() => _updateRel = null);
  }

  /// Overview update banner (only when a pending update exists).
  Widget _updateBanner() {
    final rel = _updateRel;
    if (rel == null) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.accentCyan.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.accentCyan.withValues(alpha: 0.25)),
      ),
      child: Row(children: [
        Container(
            width: 32, height: 32,
            decoration: BoxDecoration(color: AppColors.accentCyan.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(8)),
            child: _updateChecking
                ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.accentCyan))
                : const Icon(Icons.system_update, size: 16, color: AppColors.accentCyan)),
        const SizedBox(width: 10),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Update available: v${rel.version}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
          Text(
              (rel.name.isNotEmpty ? '${rel.name} • ' : '') + 'Tap UPDATE to review, download and install',
              style: const TextStyle(fontSize: 10, color: AppColors.textMuted),
              maxLines: 1,
              overflow: TextOverflow.ellipsis),
        ])),
        const SizedBox(width: 8),
        TextButton(onPressed: _skipUpdateVersion, child: const Text('SKIP', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: AppColors.textMuted))),
        FilledButton(
          onPressed: () => _showUpdateDialog(rel),
          style: FilledButton.styleFrom(backgroundColor: AppColors.accentCyan, foregroundColor: Colors.black, padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10)),
          child: const Text('UPDATE', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800)),
        ),
      ]),
    );
  }

  /// Review notes → download (progress) → verify → platform install.
  void _showUpdateDialog(ReleaseInfo rel) {
    final asset = UpdateService.pickAsset(rel);
    double progress = -1;
    String status = asset == null
        ? 'No ${Platform.isMacOS ? 'macOS' : Platform.isWindows ? 'Windows' : 'Linux'} build attached to this release.'
        : 'Ready to download ${(asset.size / 1048576).toStringAsFixed(1)} MB (${asset.name}).';
    bool busy = false;
    bool downloaded = false;
    bool verified = false;
    File? file;
    Directory? outDir;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setD) {
        Future<void> doDownload() async {
          if (asset == null || busy) return;
          setD(() { busy = true; status = 'Downloading…'; });
          try {
            final tmp = await getTemporaryDirectory();
            final dir = Directory('${tmp.path}/mcp-update-${rel.tag}');
            if (await dir.exists()) await dir.delete(recursive: true);
            await dir.create(recursive: true);
            file = await UpdateService().downloadAsset(asset, dir, (p) => setD(() => progress = p));
            setD(() => status = 'Download complete — verifying checksum…');
            final ok = await UpdateService().verifyChecksum(rel, file!);
            if (ok == false) throw Exception('Checksum MISMATCH — file may be corrupt. Aborting.');
            outDir = Directory('${dir.path}/extracted');
            await outDir!.create();
            setD(() => status = 'Extracting…');
            await UpdateService().extractArchive(file!, outDir!);
            setD(() {
              downloaded = true;
              verified = true;
              busy = false;
              status = ok == null
                  ? 'Extracted ✓ (no checksum file published — proceeding unverified).'
                  : 'Extracted ✓ checksum verified.';
            });
          } catch (e) {
            setD(() {
              busy = false;
              status = 'Failed: ${e.toString().replaceFirst('Exception: ', '').split('\n').first}';
            });
          }
        }

        Future<void> doInstall() async {
          if (!downloaded || outDir == null) return;
          if (Platform.isMacOS) {
            Navigator.pop(ctx);
            final msg = await UpdateInstaller.apply(outDir!);
            if (!mounted) return;
            showDialog(
              context: context,
              builder: (_) => AlertDialog(
                backgroundColor: AppColors.surface1,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: const BorderSide(color: AppColors.border)),
                title: const Text('Finish the update', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
                content: SizedBox(width: 360, child: SelectableText(msg, style: const TextStyle(fontSize: 11, height: 1.4, color: AppColors.textSecondary))),
                actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('GOT IT', style: TextStyle(color: AppColors.accentCyan, fontWeight: FontWeight.w800)))],
              ),
            );
            return;
          }
          // Windows / Linux: swap + relaunch (app exits here).
          setD(() {
            busy = true;
            status = 'Installing — the app will restart…';
          });
          await UpdateInstaller.apply(outDir!);
        }

        return AlertDialog(
          backgroundColor: AppColors.surface1,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: const BorderSide(color: AppColors.border)),
          title: Row(children: [
            Container(width: 30, height: 30, decoration: BoxDecoration(color: AppColors.accentCyan.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(7)), child: const Icon(Icons.system_update, size: 15, color: AppColors.accentCyan)),
            const SizedBox(width: 10),
            Expanded(child: Text('Update to v${rel.version}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: AppColors.textPrimary))),
            IconButton(onPressed: busy ? null : () => Navigator.pop(ctx), icon: const Icon(Icons.close, size: 16, color: AppColors.textMuted)),
          ]),
          content: SizedBox(
            width: 440,
            height: 420,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('WHAT\u2019S NEW', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 0.6, color: AppColors.textMuted)),
              const SizedBox(height: 4),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(color: const Color(0xFF050505), borderRadius: BorderRadius.circular(8), border: Border.all(color: AppColors.border)),
                  child: SingleChildScrollView(
                    child: rel.notes.isEmpty
                        ? const Text('No release notes.', style: TextStyle(fontSize: 11, color: AppColors.textMuted))
                        : MarkdownBody(data: rel.notes, selectable: true, shrinkWrap: true, styleSheet: _chatMarkdownStyle()),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              if (busy || progress >= 0) ...[
                Row(children: [
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: progress < 0 ? null : progress.clamp(0.0, 1.0),
                        minHeight: 5,
                        backgroundColor: AppColors.surface2,
                        valueColor: const AlwaysStoppedAnimation(AppColors.accentCyan),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(progress < 0 ? '…' : '${(progress * 100).toInt()}%', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: AppColors.accentCyan, fontFamily: AppFonts.mono)),
                ]),
                const SizedBox(height: 6),
              ],
              Row(children: [
                Icon(verified ? Icons.check_circle : Icons.info_outline, size: 13, color: verified ? AppColors.success : AppColors.textMuted),
                const SizedBox(width: 6),
                Expanded(child: Text(status, style: const TextStyle(fontSize: 11, color: AppColors.textSecondary))),
              ]),
            ]),
          ),
          actions: [
            TextButton(onPressed: busy ? null : () => Navigator.pop(ctx), child: const Text('LATER', style: TextStyle(color: AppColors.textSecondary, fontWeight: FontWeight.w700))),
            if (!downloaded)
              FilledButton(
                onPressed: (busy || asset == null) ? null : doDownload,
                style: FilledButton.styleFrom(backgroundColor: AppColors.accentCyan, foregroundColor: Colors.black),
                child: Text(progress >= 0 ? 'DOWNLOADING…' : 'DOWNLOAD', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800)),
              )
            else
              FilledButton(
                onPressed: busy ? null : doInstall,
                style: FilledButton.styleFrom(backgroundColor: AppColors.accentCyan, foregroundColor: Colors.black),
                child: Text(Platform.isMacOS ? 'REVEAL IN FINDER' : 'INSTALL & RESTART', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800)),
              ),
          ],
        );
      }),
    );
  }

  /// Open Server Details (pushed over the shell — works from Overview + Servers).
  void _openServerDetails(String serverId) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ServerDetailsScreen(
          serverId: serverId,
          onOpenTerminal: () {
            Navigator.pop(context); // back to shell first
            setState(() {
              _navIndex = 12;
              _terminalServerId = serverId;
              _terminalPrefill = null;
              _terminalKey++;
            });
          },
        ),
      ),
    ).then((_) => _loadSavedServers()); // refresh lists on return
  }

  @override
  void initState() {
    super.initState();
    _loadSavedServers().then((_) => _maybeAutoCheckUpdates());
    _startAutoRefresh();
    _logTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      if (!mounted) return;
      if (_useRealServers) return; // real mode: logs come from _pollRealLogs
      setState(() {
        _liveLogs.insert(0, LogLine(time: DateTime.now(), level: ['INFO','INFO','WARN','DEBUG'][DateTime.now().second % 4], source: ['api-gateway','worker-queue','auth-service'][DateTime.now().second % 3], message: 'heartbeat ok ${DateTime.now().second}'));
        if (_liveLogs.length > 40) _liveLogs = _liveLogs.sublist(0, 40);
      });
    });
  }

  @override
  void dispose() {
    _logTimer?.cancel();
    _autoTimer?.cancel();
    _chatController.dispose();
    _chatScroll.dispose();
    _logScroll.dispose();
    super.dispose();
  }

  /// Real auto-refresh: honors Settings → auto_refresh + refresh_interval.
  /// Ticks every 5s, re-polls only when the interval has elapsed.
  void _startAutoRefresh() {
    _autoTimer?.cancel();
    _autoTimer = Timer.periodic(const Duration(seconds: 5), (_) async {
      if (!mounted) return;
      SharedPreferences? prefs;
      try {
        prefs = await SharedPreferences.getInstance();
      } catch (_) {
        return;
      }
      if (!(prefs.getBool('auto_refresh') ?? true)) return;
      final interval = (prefs.getDouble('refresh_interval') ?? 15).toInt();
      final now = DateTime.now();
      if (_lastAutoPoll != null && now.difference(_lastAutoPoll!).inSeconds < interval) return;
      _lastAutoPoll = now;
      if (!mounted) return;
      _pollAgents(); // metrics + crons + apps + alerts (each guarded internally)
      _pollGithub();
      _pollGitlab();
    });
  }

  void _sendChat() async {
    final t = _chatController.text.trim();
    if (t.isEmpty || _aiTyping) return;
    setState(() {
      _chatMessages.add({'role': 'user', 'text': t});
      _chatController.clear();
      _aiTyping = true;
    });
    _scrollChatToEnd();
    if (!_aiConfigured) {
      setState(() {
        _chatMessages.add({'role': 'assistant', 'text': 'No AI provider configured — tap CONFIGURE AI PROVIDER above.'});
        _aiTyping = false;
      });
      return;
    }
    try {
      final hist = _chatMessages.where((m) => m['text'] != null && m['text']!.isNotEmpty).toList();
      final tail = hist.length > 12 ? hist.sublist(hist.length - 12) : hist;
      final convo = tail.map((m) => {'role': m['role']!, 'content': m['text']!}).toList();
      final route = AiService.toolRoute(_aiProvider, _aiModelName);
      if (route == ToolRoute.chat) {
        await _runToolLoop(convo);
      } else if (route == ToolRoute.responses) {
        await _runResponsesLoop(convo);
      } else if (route == ToolRoute.anthropic) {
        await _runAnthropicToolLoop(convo);
      } else if (route == ToolRoute.gemini) {
        await _runGeminiToolLoop(convo);
      } else {
        // Plain route: streamed reply straight into the bubble.
        setState(() => _chatMessages.add({'role': 'assistant', 'text': ''}));
        final idx = _chatMessages.length - 1;
        final buf = StringBuffer();
        try {
          await AiService().streamChat(
            provider: _aiProvider,
            baseUrl: _aiBaseUrl,
            apiKey: _aiKey,
            model: _aiModelName,
            system: _aiSystemPrompt(),
            sessionId: _aiSessionId,
            messages: convo,
            onToken: (t) {
              if (!mounted) return;
              buf.write(t);
              setState(() => _chatMessages[idx]['text'] = buf.toString());
              if (_chatScroll.hasClients) {
                _chatScroll.jumpTo(_chatScroll.position.maxScrollExtent);
              }
            },
          );
        } catch (e) {
          if (!mounted) return;
          final msg = 'AI error: ${e.toString().replaceFirst('Exception: ', '').split('\n').first}\n(Provider: ${_aiProvider.label} • model: $_aiModelName — check Settings → AI Provider.)';
          setState(() => _chatMessages[idx]['text'] = buf.isEmpty ? msg : '${buf}\n\n$msg');
        }
        if (!mounted) return;
        setState(() => _aiTyping = false);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _chatMessages.add({'role': 'assistant', 'text': 'AI error: ${e.toString().replaceFirst('Exception: ', '').split('\n').first}\n(Provider: ${_aiProvider.label} • model: $_aiModelName — check Settings → AI Provider.)'});
        _aiTyping = false;
      });
    }
    _scrollChatToEnd();
  }

  /// Tool-calling loop (Stage 2): read tools run freely; gated write tools
  /// pause for an Approve/Deny dialog first. Ollama rides the same loop via
  /// its OpenAI-compatible /api/chat endpoint.
  Future<void> _runToolLoop(List<Map<String, String>> convo) async {
    final svc = AiService();
    final headers = AiService().openAiHeaders(_aiProvider, _aiKey, _aiSessionId);
    final isOllama = _aiProvider == AiProvider.ollama;
    final base = isOllama
        ? _aiBaseUrl.trim().replaceAll(RegExp(r'/+$'), '')
        : AiService.chatBase(_aiProvider, _aiBaseUrl);
    final path = isOllama ? '/api/chat' : '/chat/completions';
    final turns = <Map<String, dynamic>>[
      for (final m in convo) {'role': m['role']!, 'content': m['content']!},
    ];
    for (var i = 0; i < AiTools.maxIterations; i++) {
      final tools = _aiWriteEnabled
          ? AiTools.schemas()
          : AiTools.schemas().where((t) => !AiTools.gated.contains((((t['function'] as Map?)) ?? const {})['name'])).toList();
      final turn = await svc.chatTurn(
        baseUrl: base,
        headers: headers,
        model: _aiModelName,
        system: '${_aiSystemPrompt()}\n\nYou have tools for live data${_aiWriteEnabled ? ' and actions' : ''}. Prefer calling a read tool over guessing.${_aiWriteEnabled ? ' For restart_service, run_ssh_command, rerun_workflow, retry_gitlab_pipeline, create_github_issue: the app asks the user to approve first — briefly say what you are about to do, then call the tool.' : ' Write actions are DISABLED by the user — you are read-only. If asked to change anything, explain the manual steps instead of calling a tool.'}',
        messages: turns.map((m) => {'role': m['role'].toString(), 'content': (m['content'] ?? '').toString()}).toList(),
        tools: tools,
        path: path,
      );
      if (turn.text != null && turn.text!.isNotEmpty) {
        if (!mounted) return;
        setState(() => _chatMessages.add({'role': 'assistant', 'text': turn.text!}));
        _scrollChatToEnd();
      }
      if (turn.calls.isEmpty) {
        if (!mounted) return;
        setState(() => _aiTyping = false);
        return;
      }
      // Normalize ids first (some providers omit them) so the assistant
      // message and the follow-up tool results reference the same ids.
      var callSeq = 0;
      final calls = [
        for (final c in turn.calls)
          c.id.isNotEmpty ? c : ToolCall(id: 'call_${DateTime.now().millisecondsSinceEpoch}_${callSeq++}', name: c.name, arguments: c.arguments),
      ];
      turns.add({
        'role': 'assistant',
        'content': turn.text ?? '',
        'tool_calls': [
          for (final c in calls)
            {'id': c.id, 'type': 'function', 'function': {'name': c.name, 'arguments': _argsJson(c.arguments)}},
        ],
      });
      for (final call in calls) {
        var toolDecision = 'auto';
        if (AiTools.gated.contains(call.name)) {
          // Kill-switch: model should not have these schemas when disabled,
          // but refuse anyway if one arrives.
          if (!_aiWriteEnabled) {
            if (!mounted) return;
            setState(() => _chatMessages.add({'role': 'assistant', 'text': '_Write tools are disabled — enable them above to allow ${call.name}._'}));
            turns.add({'role': 'tool', 'tool_call_id': call.id, 'content': 'Write tools are disabled by the user. Explain manual steps instead.'});
            _auditDecision(call, 'blocked', 'Blocked: write tools disabled.');
            continue;
          }
          final approved = await _askToolApproval(call);
          if (!mounted) return;
          if (!approved) {
            setState(() => _chatMessages.add({'role': 'assistant', 'text': '_${call.name} denied by user — I won\'t run it._'}));
            turns.add({'role': 'tool', 'tool_call_id': call.id, 'content': 'Denied by user. Do not retry this call. Explain the manual alternative instead.'});
            _auditDecision(call, 'denied', 'Denied by user at approval gate.');
            continue;
          }
          setState(() => _chatMessages.add({'role': 'assistant', 'text': '_Running ${call.name}…_'}));
          toolDecision = 'approved';
        }
        final result = await _auditedExecute(call, toolDecision);
        if (!mounted) return;
        turns.add({'role': 'tool', 'tool_call_id': call.id, 'content': result.output});
      }
    }
    if (!mounted) return;
    setState(() {
      _chatMessages.add({'role': 'assistant', 'text': '_Stopped after ${AiTools.maxIterations} tool rounds — ask me to continue if needed._'});
      _aiTyping = false;
    });
  }

  /// Executor guard: no tool exception may escape into the chat loop.
  Future<ToolResult> _safeExecute(String name, Map<String, dynamic> args) async {
    try {
      return await executeTool(name, args, _toolDeps());
    } catch (e) {
      return ToolResult('Tool $name crashed: ${e.toString().split('\n').first}');
    }
  }

  /// Execute + audit. Decision: auto (read tools), approved, denied, blocked.
  Future<ToolResult> _auditedExecute(ToolCall call, String decision) async {
    final sw = Stopwatch()..start();
    final result = await _safeExecute(call.name, call.arguments);
    sw.stop();
    unawaited(AuditLog.record(
      tool: call.name,
      args: call.arguments,
      decision: decision,
      result: result.output,
      provider: _aiProvider.label,
      model: _aiModelName,
      durationMs: sw.elapsedMilliseconds,
    ));
    return result;
  }

  void _auditDecision(ToolCall call, String decision, String summary) {
    unawaited(AuditLog.record(
      tool: call.name,
      args: call.arguments,
      decision: decision,
      result: summary,
      provider: _aiProvider.label,
      model: _aiModelName,
      durationMs: 0,
    ));
  }

  /// Tool loop for Responses-API models (Go/Zen responses family):
  /// same tools + approval gate, Responses wire format.
  Future<void> _runResponsesLoop(List<Map<String, String>> convo) async {
    final svc = AiService();
    final base = _aiBaseUrl.trim().replaceAll(RegExp(r'/+$'), '');
    final url = _aiProvider == AiProvider.openCodeGo
        ? 'https://opencode.ai/inference/go/openai/v1/responses'
        : '$base/responses';
    final headers = AiService().openAiHeaders(_aiProvider, _aiKey, _aiSessionId);
    final tools = _aiWriteEnabled
        ? AiTools.schemas()
        : AiTools.schemas().where((t) => !AiTools.gated.contains((((t['function'] as Map?)) ?? const {})['name'])).toList();
    final instructions =
        '${_aiSystemPrompt()}\n\nYou have function tools for live data${_aiWriteEnabled ? ' and actions' : ''}. Prefer calling a read tool over guessing.${_aiWriteEnabled ? ' For writes, briefly say what you are about to do, then call the tool — the app asks the user to approve first.' : ' Write actions are DISABLED — you are read-only; explain manual steps instead.'}';
    var input = <Map<String, dynamic>>[
      for (final m in convo)
        {
          'role': m['role'] == 'assistant' ? 'assistant' : 'user',
          'content': m['content']!,
        },
    ];
    for (var i = 0; i < AiTools.maxIterations; i++) {
      final turn = await svc.responsesTurn(
        url: url,
        headers: headers,
        model: _aiModelName,
        instructions: instructions,
        input: input,
        tools: tools,
      );
      if (turn.text != null && turn.text!.isNotEmpty) {
        if (!mounted) return;
        setState(() => _chatMessages.add({'role': 'assistant', 'text': turn.text!}));
        _scrollChatToEnd();
      }
      if (turn.calls.isEmpty) {
        if (!mounted) return;
        setState(() => _aiTyping = false);
        return;
      }
      input = [...input, ...turn.outputItems];
      for (final call in turn.calls) {
        var toolDecision = 'auto';
        if (AiTools.gated.contains(call.name)) {
          if (!_aiWriteEnabled) {
            if (!mounted) return;
            setState(() => _chatMessages.add({'role': 'assistant', 'text': '_Write tools are disabled — enable them above to allow ${call.name}._'}));
            input.add({'type': 'function_call_output', 'call_id': call.id, 'output': 'Write tools are disabled by the user. Explain manual steps instead.'});
            _auditDecision(call, 'blocked', 'Blocked: write tools disabled.');
            continue;
          }
          final approved = await _askToolApproval(call);
          if (!mounted) return;
          if (!approved) {
            setState(() => _chatMessages.add({'role': 'assistant', 'text': '_${call.name} denied by user — I won\'t run it._'}));
            input.add({'type': 'function_call_output', 'call_id': call.id, 'output': 'Denied by user. Do not retry this call. Explain the manual alternative instead.'});
            _auditDecision(call, 'denied', 'Denied by user at approval gate.');
            continue;
          }
          setState(() => _chatMessages.add({'role': 'assistant', 'text': '_Running ${call.name}…_'}));
        toolDecision = 'approved';
        }
        final result = await _auditedExecute(call, toolDecision);
        if (!mounted) return;
        input.add({'type': 'function_call_output', 'call_id': call.id, 'output': result.output});
      }
    }
    if (!mounted) return;
    setState(() {
      _chatMessages.add({'role': 'assistant', 'text': '_Stopped after ${AiTools.maxIterations} tool rounds — ask me to continue if needed._'});
      _aiTyping = false;
    });
  }

  List<Map<String, dynamic>> _toolSchemas() => _aiWriteEnabled
      ? AiTools.schemas()
      : AiTools.schemas().where((t) => !AiTools.gated.contains((((t['function'] as Map?)) ?? const {})['name'])).toList();

  String _toolSystemSuffix() =>
      ' Prefer calling a read tool over guessing.${_aiWriteEnabled ? ' For restart_service, run_ssh_command, rerun_workflow, retry_gitlab_pipeline, create_github_issue: the app asks the user to approve first — briefly say what you are about to do, then call the tool.' : ' Write actions are DISABLED by the user — you are read-only. If asked to change anything, explain the manual steps instead of calling a tool.'}';

  /// Native Anthropic tool loop (Anthropic provider + Zen/Go anthropic models).
  Future<void> _runAnthropicToolLoop(List<Map<String, String>> convo) async {
    final svc = AiService();
    final trimmed = _aiBaseUrl.trim().replaceAll(RegExp(r'/+$'), '');
    late final String url;
    if (_aiProvider == AiProvider.anthropic) {
      url = '$trimmed/v1/messages';
    } else if (_aiProvider == AiProvider.openCodeGo) {
      url = 'https://opencode.ai/inference/go/anthropic/v1/messages';
    } else {
      url = '$trimmed/messages'; // Zen: {base}/messages
    }
    final messages = <Map<String, dynamic>>[
      for (final m in convo)
        if (m['role'] == 'user' || m['role'] == 'assistant') {'role': m['role']!, 'content': m['content']!},
    ];
    final tools = _toolSchemas();
    final system = '${_aiSystemPrompt()}\n\nYou have tools for live data${_aiWriteEnabled ? ' and actions' : ''}.${_toolSystemSuffix()}';
    for (var i = 0; i < AiTools.maxIterations; i++) {
      final turn = await svc.anthropicTurn(
        baseUrl: _aiBaseUrl,
        key: _aiKey,
        model: _aiModelName,
        system: system,
        messages: messages,
        tools: tools,
        endpoint: url,
        gateway: _aiProvider != AiProvider.anthropic,
      );
      if (turn.text != null && turn.text!.isNotEmpty) {
        if (!mounted) return;
        setState(() => _chatMessages.add({'role': 'assistant', 'text': turn.text!}));
        _scrollChatToEnd();
      }
      if (turn.calls.isEmpty) {
        if (!mounted) return;
        setState(() => _aiTyping = false);
        return;
      }
      messages.add({'role': 'assistant', 'content': turn.native});
      for (final call in turn.calls) {
        var toolDecision = 'auto';
        if (AiTools.gated.contains(call.name)) {
          if (!_aiWriteEnabled) {
            if (!mounted) return;
            setState(() => _chatMessages.add({'role': 'assistant', 'text': '_Write tools are disabled — enable them above to allow ${call.name}._'}));
            messages.add({'role': 'user', 'content': [{'type': 'tool_result', 'tool_use_id': call.id, 'content': 'Write tools are disabled by the user. Explain manual steps instead.'}]});
            _auditDecision(call, 'blocked', 'Blocked: write tools disabled.');
            continue;
          }
          final approved = await _askToolApproval(call);
          if (!mounted) return;
          if (!approved) {
            setState(() => _chatMessages.add({'role': 'assistant', 'text': '_${call.name} denied by user — I won\'t run it._'}));
            messages.add({'role': 'user', 'content': [{'type': 'tool_result', 'tool_use_id': call.id, 'content': 'Denied by user. Do not retry this call. Explain the manual alternative instead.'}]});
            _auditDecision(call, 'denied', 'Denied by user at approval gate.');
            continue;
          }
          setState(() => _chatMessages.add({'role': 'assistant', 'text': '_Running ${call.name}…_'}));
        toolDecision = 'approved';
        }
        final result = await _auditedExecute(call, toolDecision);
        if (!mounted) return;
        messages.add({'role': 'user', 'content': [{'type': 'tool_result', 'tool_use_id': call.id, 'content': result.output}]});
      }
    }
    if (!mounted) return;
    setState(() {
      _chatMessages.add({'role': 'assistant', 'text': '_Stopped after ${AiTools.maxIterations} tool rounds — ask me to continue if needed._'});
      _aiTyping = false;
    });
  }

  /// Native Gemini tool loop (direct + Go/Zen gateways).
  Future<void> _runGeminiToolLoop(List<Map<String, String>> convo) async {
    final svc = AiService();
    final contents = <Map<String, dynamic>>[
      for (final m in convo)
        {
          'role': m['role'] == 'assistant' ? 'model' : 'user',
          'parts': [
            {'text': m['content']!}
          ],
        },
    ];
    final tools = _toolSchemas();
    final system = '${_aiSystemPrompt()}\n\nYou have function tools for live data${_aiWriteEnabled ? ' and actions' : ''}.${_toolSystemSuffix()}';
    String? fullUrl;
    var gateway = false;
    if (_aiProvider == AiProvider.openCodeGo) {
      fullUrl = 'https://opencode.ai/inference/go/google/v1beta/models/gemini-4-argon:generateContent?key=$_aiKey';
      gateway = true;
    } else if (_aiProvider == AiProvider.openCodeZen) {
      final m = _aiModelName.trim().toLowerCase();
      fullUrl = '${_aiBaseUrl.trim().replaceAll(RegExp(r'/+$'), '')}/models/$m:generateContent?key=$_aiKey';
      gateway = true;
    }
    for (var i = 0; i < AiTools.maxIterations; i++) {
      final turn = await svc.geminiTurn(
        baseUrl: _aiBaseUrl,
        key: _aiKey,
        model: _aiModelName,
        system: system,
        contents: contents,
        fullUrl: fullUrl,
        gateway: gateway,
        tools: tools,
      );
      if (turn.text != null && turn.text!.isNotEmpty) {
        if (!mounted) return;
        setState(() => _chatMessages.add({'role': 'assistant', 'text': turn.text!}));
        _scrollChatToEnd();
      }
      if (turn.calls.isEmpty) {
        if (!mounted) return;
        setState(() => _aiTyping = false);
        return;
      }
      contents.add({'role': 'model', 'parts': turn.native});
      for (final call in turn.calls) {
        var toolDecision = 'auto';
        if (AiTools.gated.contains(call.name)) {
          if (!_aiWriteEnabled) {
            if (!mounted) return;
            setState(() => _chatMessages.add({'role': 'assistant', 'text': '_Write tools are disabled — enable them above to allow ${call.name}._'}));
            contents.add({'role': 'function', 'parts': [{'functionResponse': {'name': call.name, 'response': {'result': 'Write tools are disabled by the user. Explain manual steps instead.'}}}]});
            _auditDecision(call, 'blocked', 'Blocked: write tools disabled.');
            continue;
          }
          final approved = await _askToolApproval(call);
          if (!mounted) return;
          if (!approved) {
            setState(() => _chatMessages.add({'role': 'assistant', 'text': '_${call.name} denied by user — I won\'t run it._'}));
            contents.add({'role': 'function', 'parts': [{'functionResponse': {'name': call.name, 'response': {'result': 'Denied by user. Do not retry this call. Explain the manual alternative instead.'}}}]});
            _auditDecision(call, 'denied', 'Denied by user at approval gate.');
            continue;
          }
          setState(() => _chatMessages.add({'role': 'assistant', 'text': '_Running ${call.name}…_'}));
        toolDecision = 'approved';
        }
        final result = await _auditedExecute(call, toolDecision);
        if (!mounted) return;
        contents.add({'role': 'function', 'parts': [{'functionResponse': {'name': call.name, 'response': {'result': result.output}}}]});
      }
    }
    if (!mounted) return;
    setState(() {
      _chatMessages.add({'role': 'assistant', 'text': '_Stopped after ${AiTools.maxIterations} tool rounds — ask me to continue if needed._'});
      _aiTyping = false;
    });
  }

  String _argsJson(Map<String, dynamic> args) {
    try {
      return const JsonEncoder.withIndent('  ').convert(args);
    } catch (_) {
      return args.toString();
    }
  }

  ToolDeps _toolDeps() => ToolDeps(
        servers: _savedServers,
        metrics: _metrics,
        crons: _serverCrons,
        apps: _serverApps,
        alerts: _serverAlerts,
        issues: _ghIssues,
        prs: _ghPRs,
        tasks: _ghTasks,
        runs: _ghRuns,
        githubToken: _ghToken,
        githubRepos: _ghRepos,
        gitlabToken: _glToken,
        gitlabBaseUrl: _glBase,
        gitlabProjects: _glProjects,
        agent: _agent,
      );

  /// Dark pitch-black Markdown theme for assistant replies.
  MarkdownStyleSheet _chatMarkdownStyle() {
    const body = TextStyle(fontSize: 12, height: 1.4, color: AppColors.textPrimary, fontFamily: AppFonts.mono);
    return MarkdownStyleSheet(
      p: body,
      pPadding: const EdgeInsets.only(bottom: 6),
      h1: body.copyWith(fontSize: 15, fontWeight: FontWeight.w800),
      h1Padding: const EdgeInsets.only(bottom: 6),
      h2: body.copyWith(fontSize: 13, fontWeight: FontWeight.w800),
      h2Padding: const EdgeInsets.only(bottom: 5),
      h3: body.copyWith(fontSize: 12, fontWeight: FontWeight.w800),
      h3Padding: const EdgeInsets.only(bottom: 4),
      em: body.copyWith(fontStyle: FontStyle.italic, color: AppColors.textSecondary),
      strong: body.copyWith(fontWeight: FontWeight.w800),
      del: body.copyWith(decoration: TextDecoration.lineThrough, color: AppColors.textMuted),
      a: body.copyWith(color: AppColors.accentCyan, decoration: TextDecoration.underline),
      code: const TextStyle(fontSize: 11, color: AppColors.accentCyan, fontFamily: AppFonts.mono, backgroundColor: Color(0xFF050505)),
      codeblockPadding: const EdgeInsets.all(8),
      codeblockDecoration: BoxDecoration(color: const Color(0xFF050505), borderRadius: BorderRadius.circular(8), border: Border.all(color: AppColors.border)),
      blockquote: body.copyWith(color: AppColors.textSecondary, fontStyle: FontStyle.italic),
      blockquoteDecoration: const BoxDecoration(border: Border(left: BorderSide(color: AppColors.accentCyan, width: 2))),
      blockquotePadding: const EdgeInsets.only(left: 8, top: 2, bottom: 2),
      listBullet: body.copyWith(color: AppColors.accentCyan),
      listIndent: 16,
      listBulletPadding: const EdgeInsets.only(right: 6),
      tableHead: body.copyWith(fontWeight: FontWeight.w800, fontSize: 11),
      tableBody: body.copyWith(fontSize: 11),
      tableHeadAlign: TextAlign.left,
      tableBorder: TableBorder.all(color: AppColors.border, width: 0.6),
      tableCellsPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      horizontalRuleDecoration: const BoxDecoration(border: Border(top: BorderSide(color: AppColors.border))),
      checkbox: body.copyWith(color: AppColors.accentCyan),
    );
  }

  /// Pop the top dialog and wait for the transition, so a follow-up
  /// showDialog doesn't trip Navigator._debugLocked ("is not true").
  Future<void> _dismissDialog() async {
    if (Navigator.canPop(context)) {
      Navigator.pop(context);
      await Future.delayed(const Duration(milliseconds: 350));
    }
  }

  /// Approve/Deny gate for write tools. True only on explicit Approve.
  Future<bool> _askToolApproval(ToolCall call) async {
    final pretty = _argsJson(call.arguments);
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface1,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: AppColors.warning.withValues(alpha: 0.4))),
        title: Row(children: [
          Container(width: 30, height: 30, decoration: BoxDecoration(color: AppColors.warning.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(7)), child: const Icon(Icons.verified_user_outlined, size: 15, color: AppColors.warning)),
          const SizedBox(width: 10),
          const Expanded(child: Text('Approve AI action?', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: AppColors.textPrimary))),
        ]),
        content: SizedBox(
          width: 340,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(color: AppColors.warning.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(6), border: Border.all(color: AppColors.warning.withValues(alpha: 0.25))),
              child: Text(call.name, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: AppColors.warning, fontFamily: AppFonts.mono)),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: const Color(0xFF050505), borderRadius: BorderRadius.circular(8), border: Border.all(color: AppColors.border)),
              child: SingleChildScrollView(child: SelectableText(pretty, style: const TextStyle(fontSize: 11, color: AppColors.textPrimary, fontFamily: AppFonts.mono))),
            ),
            const SizedBox(height: 8),
            const Text('Runs with your saved credentials. Deny if anything looks off.', style: TextStyle(fontSize: 10, color: AppColors.textMuted)),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('DENY', style: TextStyle(color: AppColors.textSecondary, fontWeight: FontWeight.w800))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), style: FilledButton.styleFrom(backgroundColor: AppColors.warning, foregroundColor: Colors.black), child: const Text('APPROVE & RUN', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800))),
        ],
      ),
    );
    return result == true;
  }

  void _scrollChatToEnd() {
    Future.delayed(const Duration(milliseconds: 100), () {
      if (_chatScroll.hasClients) {
        _chatScroll.animateTo(_chatScroll.position.maxScrollExtent + 200,
            duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
      }
    });
  }

  /// Live control-center snapshot injected as the system prompt.
  String _aiSystemPrompt() {
    final b = StringBuffer();
    b.writeln('You are the AI assistant inside MyControlPanel, an IT control center app.');
    b.writeln('Reply in GitHub-flavored Markdown (the client renders it): short headings, bullets, tables for comparisons, fenced code blocks for commands/output. Keep it tight.');
    b.writeln('Use ONLY the live state below for facts about infrastructure. Never invent servers, metrics, or deployments.');
    b.writeln();
    b.writeln('SERVERS (${_servers.length}${_useRealServers ? ', user-configured' : ', DEMO data'}):');
    for (final s in _servers) {
      final m = _metrics[s.id];
      final met = m == null
          ? 'no live metrics'
          : 'cpu=${((m['cpu'] as num).toDouble() * 100).toInt()}% ram=${((m['ram'] as num).toDouble() * 100).toInt()}% disk=${((m['disk'] as num).toDouble() * 100).toInt()}% up=${m['uptime_days']}d';
      b.writeln('- ${s.name} (${s.ip}, ${s.region}) status=${s.status.name} $met');
    }
    b.writeln();
    final alerts = _realAlerts.isEmpty && !_useRealServers ? mockAlerts.map((a) => '${a.title} [${a.severity}]').toList() : _realAlerts.map((a) => '${a.title} [${a.severity}] on ${a.serverName}').toList();
    b.writeln('ALERTS (${alerts.length} firing signals):');
    for (final a in alerts.take(10)) {
      b.writeln('- $a');
    }
    b.writeln();
    final crons = _realCrons.isEmpty && !_useRealServers
        ? mockCrons.map((c) => '${c.name} (${c.schedule}) status=${c.status.name} on ${c.server}').toList()
        : _realCrons.map((c) => '${c.command} (${c.schedule}) on ${c.serverName} [${c.source}]').toList();
    b.writeln('CRONJOBS (${crons.length}):');
    for (final c in crons.take(10)) {
      b.writeln('- $c');
    }
    b.writeln();
    final apps = _realApps.isEmpty && !_useRealServers
        ? mockApps.map((a) => '${a.name} ${a.version} [${a.env.name}]').toList()
        : _realApps.map((a) => '${a.name} (${a.detail}) on ${a.serverName} [${a.source}]').toList();
    b.writeln('APPS (${apps.length}):');
    for (final a in apps.take(10)) {
      b.writeln('- $a');
    }
    b.writeln();
    if (_ghConfigured) {
      b.writeln('GITHUB (@$_ghUser, repos: ${_ghRepos.join(', ')}): ${_ghIssues.length} open issues, ${_ghPRs.length} open PRs, ${_ghTasks.length} tasks${_ghTasksFromProjects ? ' (from Projects v2 boards)' : ''}.');
      if (_ghProjects.isNotEmpty) {
        b.writeln('PROJECTS V2: ${_ghProjects.map((p) => '${p['title']} (${p['items']} items)').join(', ')}');
      }
      for (final i in _ghIssues.take(5)) {
        b.writeln('- issue #${i.number}: ${i.title} (${i.repo})');
      }
      for (final p in _ghPRs.take(5)) {
        b.writeln('- PR #${p.number}: ${p.title} (${p.repo})');
      }
      if (_ghRuns.isNotEmpty) {
        b.writeln('RECENT GITHUB ACTIONS RUNS:');
        for (final r in _ghRuns.take(5)) {
          b.writeln('- ${r.app} #${r.version} ${r.status} on ${r.env} by ${r.actor}');
        }
      }
      if (_glPipes.isNotEmpty) {
        b.writeln('RECENT GITLAB PIPELINES:');
        for (final r in _glPipes.take(5)) {
          b.writeln('- ${r.app} #${r.version} ${r.status} on ${r.env} by ${r.actor}');
        }
      }
    } else {
      b.writeln('GITHUB: not connected (demo data in UI).');
    }
    b.writeln();
    if (_glConfigured) {
      b.writeln('GITLAB (@$_glUser on $_glBase, projects: ${_glProjects.join(', ')}): ${_glIssues.length} open issues, ${_glMrs.length} open MRs, ${_glTasks.length} tasks.');
      for (final i in _glIssues.take(5)) {
        b.writeln('- issue !${i.number}: ${i.title} (${i.repo})');
      }
      for (final m in _glMrs.take(5)) {
        b.writeln('- MR !${m.number}: ${m.title} (${m.repo})');
      }
    } else {
      b.writeln('GITLAB: not connected (demo data in UI).');
    }
    b.writeln();
    if (_aiWriteEnabled) {
      b.writeln('Write tools are ENABLED: you may restart services, run allowlisted diagnostic commands (incl. directory listings), re-run failed GitHub workflows, retry GitLab pipelines, and file GitHub issues via tools. The app asks the user to approve each write before it runs — say what you will do, then call the tool. Never claim inability to act: use the tools.');
    } else {
      b.writeln('Write tools are DISABLED: you are read-only. If asked to DO something, explain the manual steps and point to the relevant screen/terminal command.');
    }
    return b.toString();
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop = MediaQuery.of(context).size.width > 900;
    return Scaffold(
      backgroundColor: AppColors.pitchBlack,
      appBar: _buildAppBar(),
      drawer: isDesktop ? null : Drawer(backgroundColor: AppColors.pitchBlack, child: _buildSideRail()),
      endDrawer: _buildChatDrawer(),
      body: isDesktop ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [_buildSideRail(), const VerticalDivider(width: 1, color: AppColors.border), Expanded(child: _buildContent())]) : _buildContent(),
      bottomNavigationBar: isDesktop ? null : _buildBottomNav(),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    final op = _servers.where((s) => s.status == Status.operational).length;
    return AppBar(
      centerTitle: false,
      title: Row(children: [
        // Back to Overview on every non-Overview tab page.
        // (Placed in title, not AppBar.leading, so the mobile drawer hamburger is preserved.)
        if (_navIndex != 0)
          Padding(
            padding: const EdgeInsets.only(right: 6),
            child: InkWell(
              onTap: () => _goTo(0),
              borderRadius: BorderRadius.circular(8),
              child: Container(
                width: 32, height: 32,
                decoration: BoxDecoration(color: AppColors.surface1, borderRadius: BorderRadius.circular(8), border: Border.all(color: AppColors.border)),
                child: const Icon(Icons.arrow_back, size: 16, color: AppColors.textSecondary),
              ),
            ),
          ),
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(color: AppColors.surface1, borderRadius: BorderRadius.circular(8), border: Border.all(color: AppColors.border)),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.asset('assets/app_icon.png', width: 32, height: 32, fit: BoxFit.cover),
          ),
        ),
        const SizedBox(width: 10),
        const Flexible(child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          Text('MY CONTROL PANEL', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, letterSpacing: 1.0, color: AppColors.textPrimary)),
          Text('IT CONTROL CENTER', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 9, fontWeight: FontWeight.w600, letterSpacing: 0.6, color: AppColors.textMuted)),
        ])),
      ]),
      actions: [
        Container(
          margin: const EdgeInsets.only(right: 8),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(color: AppColors.surface0, borderRadius: BorderRadius.circular(20), border: Border.all(color: AppColors.border)),
          child: Row(children: [
            StatusDot(color: op == _servers.length && _servers.isNotEmpty ? AppColors.success : AppColors.warning, pulse: true),
            const SizedBox(width: 8),
            Text('$op/${_servers.length} OPERATIONAL${_useRealServers ? '' : ' • DEMO'}', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: AppColors.textSecondary, letterSpacing: 0.5)),
          ]),
        ),
        IconButton(onPressed: () => _goTo(11), icon: Container(padding: const EdgeInsets.all(6), decoration: BoxDecoration(color: _navIndex==11 ? AppColors.accentCyan.withValues(alpha:0.2) : AppColors.surface1, borderRadius: BorderRadius.circular(8), border: Border.all(color: _navIndex==11 ? AppColors.accentCyan : AppColors.border)), child: Icon(Icons.settings_outlined, size: 16, color: _navIndex==11 ? AppColors.accentCyan : AppColors.textSecondary))),
        Stack(children: [
          IconButton(onPressed: () => _goTo(6), icon: const Icon(Icons.notifications_none, size: 18, color: AppColors.textSecondary)),
          if (_alertBadge > 0)
            Positioned(
              right: 6, top: 6,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(color: AppColors.critical, borderRadius: BorderRadius.circular(8)),
                child: Text('$_alertBadge', style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w800, color: Colors.white)),
              ),
            ),
        ]),
        const SizedBox(width: 4),
        Builder(builder: (ctx) => IconButton(onPressed: ()=> Scaffold.of(ctx).openEndDrawer(), icon: Container(padding: const EdgeInsets.all(6), decoration: BoxDecoration(color: AppColors.accentCyan, borderRadius: BorderRadius.circular(8)), child: const Icon(Icons.smart_toy_outlined, size: 16, color: Colors.black)))),
        const SizedBox(width: 12),
      ],
    );
  }

  Widget _buildSideRail() {
    final items = [
      ('Overview', Icons.dashboard_outlined, AppColors.accentCyan),
      ('Servers', Icons.dns_outlined, AppColors.accentBlue),
      ('Cronjobs', Icons.schedule_outlined, AppColors.accentPurple),
      ('Apps', Icons.apps_outlined, AppColors.accentGreen),
      ('GitHub', Icons.code_outlined, AppColors.textPrimary),
      ('GitLab', Icons.layers_outlined, AppColors.accentPurple),
      ('Alerts', Icons.warning_amber_outlined, AppColors.warning),
      ('Deploys', Icons.rocket_launch_outlined, AppColors.accentCyan),
      ('Logs', Icons.article_outlined, AppColors.textSecondary),
      ('Metrics', Icons.show_chart_outlined, AppColors.success),
      ('Security', Icons.shield_outlined, AppColors.critical),
      ('Settings', Icons.settings_outlined, AppColors.textSecondary),
      ('Terminal', Icons.terminal_outlined, AppColors.accentCyan),
    ];
    return Container(
      width: 220, color: AppColors.pitchBlack,
      child: Column(children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
            children: [
              for (int i = 0; i < items.length; i++)
                Container(
                  margin: const EdgeInsets.only(bottom: 4),
                  decoration: BoxDecoration(color: _navIndex==i ? AppColors.surface1 : Colors.transparent, borderRadius: BorderRadius.circular(10), border: Border.all(color: _navIndex==i ? AppColors.borderLight : Colors.transparent)),
                  child: ListTile(
                    dense: true, onTap: () => _goTo(i),
                    leading: Container(width: 28, height: 28, decoration: BoxDecoration(color: _navIndex==i ? items[i].$3.withValues(alpha: 0.14) : AppColors.surface2, borderRadius: BorderRadius.circular(7), border: Border.all(color: _navIndex==i ? items[i].$3.withValues(alpha: 0.25) : AppColors.border)), child: Icon(items[i].$2, size: 14, color: _navIndex==i ? items[i].$3 : AppColors.textMuted)),
                    title: Text(items[i].$1, style: TextStyle(fontSize: 12, fontWeight: _navIndex==i ? FontWeight.w700 : FontWeight.w500, color: _navIndex==i ? AppColors.textPrimary : AppColors.textSecondary)),
                    trailing: _navIndex==i ? Container(width: 6, height: 6, decoration: BoxDecoration(color: items[i].$3, shape: BoxShape.circle)) : null,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0), minLeadingWidth: 28,
                  ),
                ),
              const SizedBox(height: 12),
              const Divider(), const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: AppColors.surface0, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.border)),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('QUICK STATS', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 0.7, color: AppColors.textMuted)),
                  const SizedBox(height: 10),
                  _miniStat('Servers', '${_servers.length}${_useRealServers ? ' real' : ' demo'}', AppColors.accentCyan),
                  _miniStat('Uptime', '99.92%', AppColors.success),
                  _miniStat('Incidents', '2 firing', AppColors.critical),
                  _miniStat('PRs open', '3', AppColors.textSecondary),
                ]),
              ),
            ],
          ),
        ),
        // Buy Me a Coffee — pinned bottom-left
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 4, 10, 10),
          child: InkWell(
            onTap: _openBuyMeACoffee,
            borderRadius: BorderRadius.circular(10),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
              decoration: BoxDecoration(color: const Color(0xFFFFDD00).withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10), border: Border.all(color: const Color(0xFFFFDD00).withValues(alpha: 0.35))),
              child: const Row(children: [
                Icon(Icons.coffee_outlined, size: 15, color: Color(0xFFFFDD00)),
                SizedBox(width: 8),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Buy Me a Coffee', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Color(0xFFFFDD00))),
                  Text('Support this project', style: TextStyle(fontSize: 9, color: AppColors.textMuted)),
                ])),
                Icon(Icons.open_in_new, size: 12, color: AppColors.textMuted),
              ]),
            ),
          ),
        ),
      ]),
    );
  }

  Future<void> _openBuyMeACoffee() async {
    final uri = Uri.parse('https://buymeacoffee.com/alfirus');
    try {
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!ok && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(backgroundColor: AppColors.surface1, content: Text('Could not open browser — visit buymeacoffee.com/alfirus', style: TextStyle(fontSize: 12, color: AppColors.textSecondary))));
      }
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(backgroundColor: AppColors.surface1, content: Text('Could not open browser — visit buymeacoffee.com/alfirus', style: TextStyle(fontSize: 12, color: AppColors.textSecondary))));
    }
  }

  Widget _miniStat(String k, String v, Color c) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
      Text(k, style: const TextStyle(fontSize: 11, color: AppColors.textMuted)),
      const SizedBox(width: 6),
      Flexible(child: Text(v, maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.end, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: c))),
    ]),
  );

  Widget _buildBottomNav() {
    return Container(
      decoration: const BoxDecoration(color: AppColors.surface0, border: Border(top: BorderSide(color: AppColors.border))),
      child: SafeArea(
        child: SizedBox(height: 64, child: Row(children: [
          _bottomItem(0, Icons.dashboard, 'Overview'),
          _bottomItem(1, Icons.dns, 'Servers'),
          _bottomItem(4, Icons.code, 'GitHub'),
          _bottomItem(6, Icons.rocket_launch, 'Deploys'),
          _bottomItem(11, Icons.settings, 'Settings'),
          _moreItem(),
          Builder(builder: (ctx) => GestureDetector(onTap: ()=> Scaffold.of(ctx).openEndDrawer(), child: Container(margin: const EdgeInsets.all(8), width: 44, height: 44, decoration: BoxDecoration(color: AppColors.accentCyan, borderRadius: BorderRadius.circular(12)), child: const Icon(Icons.smart_toy_outlined, size: 18, color: Colors.black)))),
        ])),
      ),
    );
  }

  /// MORE overflow (spec 03 F3): every destination missing from the bottom
  /// nav stays one tap away on phones via this sheet — same icons as the
  /// rail, selected row highlighted. Grouping IA still needs Lina (§3).
  Widget _moreItem() {
    final active = overflowNavIndices.contains(_navIndex);
    return Expanded(child: InkWell(onTap: _openMoreNav, child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      Icon(Icons.more_horiz, size: 18, color: active ? AppColors.accentCyan : AppColors.textMuted),
      const SizedBox(height: 3),
      Text('More', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w600, color: active ? AppColors.accentCyan : AppColors.textMuted)),
    ])));
  }

  void _openMoreNav() {
    const entries = [
      (2, 'Cronjobs', Icons.schedule_outlined),
      (3, 'Apps', Icons.apps_outlined),
      (5, 'GitLab', Icons.layers_outlined),
      (6, 'Alerts', Icons.warning_amber_outlined),
      (8, 'Logs', Icons.article_outlined),
      (9, 'Metrics', Icons.show_chart_outlined),
      (10, 'Security', Icons.shield_outlined),
      (12, 'Terminal', Icons.terminal_outlined),
    ];
    assert(entries.every((e) => overflowNavIndices.contains(e.$1)),
        'MORE sheet must list exactly the overflow destinations');
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface0,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16)), side: BorderSide(color: AppColors.border)),
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Padding(padding: EdgeInsets.fromLTRB(16, 14, 16, 6), child: Text('MORE DESTINATIONS', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 0.7, color: AppColors.textMuted))),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              children: [
                for (final e in entries)
                  ListTile(
                    dense: true,
                    leading: Container(width: 28, height: 28, decoration: BoxDecoration(color: _navIndex == e.$1 ? AppColors.accentCyan.withValues(alpha: 0.14) : AppColors.surface2, borderRadius: BorderRadius.circular(7), border: Border.all(color: _navIndex == e.$1 ? AppColors.accentCyan.withValues(alpha: 0.25) : AppColors.border)), child: Icon(e.$3, size: 14, color: _navIndex == e.$1 ? AppColors.accentCyan : AppColors.textSecondary)),
                    title: Text(e.$2, style: TextStyle(fontSize: 12, fontWeight: _navIndex == e.$1 ? FontWeight.w700 : FontWeight.w500, color: _navIndex == e.$1 ? AppColors.textPrimary : AppColors.textSecondary)),
                    trailing: _navIndex == e.$1 ? Container(width: 6, height: 6, decoration: const BoxDecoration(color: AppColors.accentCyan, shape: BoxShape.circle)) : null,
                    onTap: () {
                      Navigator.pop(ctx);
                      _goTo(e.$1);
                    },
                  ),
              ],
            ),
          ),
        ]),
      ),
    );
  }

  Widget _bottomItem(int idx, IconData icon, String label) => Expanded(child: InkWell(onTap: ()=> _goTo(idx), child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
    Icon(icon, size: 18, color: _navIndex == idx ? AppColors.accentCyan : AppColors.textMuted),
    const SizedBox(height: 3),
    Text(label, style: TextStyle(fontSize: 9, fontWeight: FontWeight.w600, color: _navIndex == idx ? AppColors.accentCyan : AppColors.textMuted)),
  ])));

  Widget _buildContent() {
    if (_navIndex == 0) return _overviewCompact();
    if (_navIndex == 1) return SingleChildScrollView(padding: const EdgeInsets.all(12), child: _serversSegment(fullWidth: true));
    if (_navIndex == 2) return SingleChildScrollView(padding: const EdgeInsets.all(12), child: _cronsSegment());
    if (_navIndex == 3) return SingleChildScrollView(padding: const EdgeInsets.all(12), child: _appsSegment());
    if (_navIndex == 4) return SingleChildScrollView(padding: const EdgeInsets.all(12), child: _githubSegment());
    if (_navIndex == 5) return SingleChildScrollView(padding: const EdgeInsets.all(12), child: _gitlabSegment());
    if (_navIndex == 6) return SingleChildScrollView(padding: const EdgeInsets.all(12), child: _alertsSegment());
    if (_navIndex == 7) return SingleChildScrollView(padding: const EdgeInsets.all(12), child: _deploysSegment());
    if (_navIndex == 8) return SingleChildScrollView(padding: const EdgeInsets.all(12), child: _logsSegment());
    if (_navIndex == 9) return SingleChildScrollView(padding: const EdgeInsets.all(12), child: _metricsSegment());
    if (_navIndex == 10) return SingleChildScrollView(padding: const EdgeInsets.all(12), child: _securitySegment());
    if (_navIndex == 11) return const SettingsScreen();
    return TerminalScreen(key: ValueKey(_terminalKey), initialServerId: _terminalServerId, prefillCommand: _terminalPrefill);
  }

  /// Status banner that reflects REAL agent state — not hardcoded copy.
  Widget _overviewBanner() {
    const gap = 12.0;
    final live = _metrics.length;
    final total = _servers.length;
    final bool allLive = total > 0 && live == total;
    final bool someLive = live > 0 && live < total;
    final color = allLive ? AppColors.success : someLive ? AppColors.warning : AppColors.accentCyan;
    final icon = allLive ? Icons.check_circle : someLive ? Icons.warning_amber : Icons.info_outline;
    final text = allLive
        ? 'All $total server${total == 1 ? '' : 's'} reporting live CPU/RAM/DISK via metrics agent ✓'
        : someLive
            ? '$live of $total servers live — ${total - live} still need the agent (tap INSTALL AGENT on their cards)'
            : 'Showing $total saved server${total == 1 ? '' : 's'} — no metrics yet. Tap INSTALL AGENT on a server card to wire live CPU/RAM/DISK.';
    return Container(
      margin: const EdgeInsets.only(bottom: gap),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(10), border: Border.all(color: color.withValues(alpha: 0.2))),
      child: Row(children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 8),
        Expanded(child: Text(text, style: const TextStyle(fontSize: 11, color: AppColors.textSecondary))),
        InkWell(onTap: () => _goTo(1), child: const Text('SERVERS →', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: AppColors.accentCyan))),
      ]),
    );
  }

  Widget _overviewCompact() {
    final isDesktop = MediaQuery.of(context).size.width > 900;
    const gap = 12.0;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(12),
      child: Column(children: [
        _updateBanner(),
        _kpiStrip(),
        const SizedBox(height: gap),
        if (_useRealServers) _overviewBanner(),
        if (isDesktop) ...[
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Expanded(child: _serversSegment(compact: true)), const SizedBox(width: gap), Expanded(child: _appsSegment(compact: true))]),
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Expanded(child: _cronsSegment(compact: true)), const SizedBox(width: gap), Expanded(child: _alertsSegment(compact: true))]),
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Expanded(child: _githubSegment(compact: true)), const SizedBox(width: gap), Expanded(child: _gitlabSegment(compact: true))]),
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Expanded(child: _deploysSegment(compact: true)), const SizedBox(width: gap), Expanded(child: _metricsSegment(compact: true))]),
          _securitySegment(compact: true),
          _logsSegment(compact: true),
        ] else ...[
          _serversSegment(compact: true), _appsSegment(compact: true), _cronsSegment(compact: true),
          _alertsSegment(compact: true), _githubSegment(compact: true), _gitlabSegment(compact: true),
          _deploysSegment(compact: true), _metricsSegment(compact: true), _securitySegment(compact: true),
          _logsSegment(compact: true),
        ],
        const SizedBox(height: 8),
        Text(_useRealServers ? 'MY CONTROL PANEL • ${_servers.length} REAL SERVERS • PITCH BLACK' : 'MY CONTROL PANEL • DEMO DATA • ADD SERVERS IN SETTINGS', style: const TextStyle(fontSize: 9, letterSpacing: 0.7, color: AppColors.textDim, fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
      ]),
    );
  }

  Widget _kpiStrip() {
    final op = _servers.where((s) => s.status == Status.operational).length;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(color: AppColors.surface0, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.border)),
      child: Row(children: [
        _kpiCell('SERVERS', '$op/${_servers.length}', _useRealServers ? AppColors.accentCyan : AppColors.success, Icons.dns),
        _kpiDivider(),
        _kpiCell('CRONS', '1 FAILED', AppColors.critical, Icons.schedule),
        _kpiDivider(),
        _kpiCell('APPS', '4/5 OK', AppColors.success, Icons.apps),
        _kpiDivider(),
        _kpiCell('ALERTS', '2 FIRING', AppColors.warning, Icons.warning_amber),
        _kpiDivider(),
        _kpiCell('DEPOYS', '4 /24H', AppColors.accentCyan, Icons.rocket_launch),
        _kpiDivider(),
        _kpiCell('SECURITY', '2 CRIT', AppColors.critical, Icons.shield),
      ]),
    );
  }
  Widget _kpiCell(String label, String val, Color c, IconData icon) => Expanded(child: Column(children: [Icon(icon, size: 12, color: c), const SizedBox(height: 3), Text(val, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: c)), Text(label, style: const TextStyle(fontSize: 8, fontWeight: FontWeight.w700, letterSpacing: 0.5, color: AppColors.textMuted))]));
  Widget _kpiDivider() => Container(width: 1, height: 28, color: AppColors.border, margin: const EdgeInsets.symmetric(horizontal: 4));

  Widget _serversSegment({bool fullWidth = false, bool compact = false}) {
    final filtered = _serverFilter == 'all' ? _servers : _servers.where((s) => s.status.name == _serverFilter).toList();
    final display = compact ? filtered.take(3).toList() : filtered;
    return PitchCard(
      title: _useRealServers ? 'SERVER STATUS • ${_servers.length} SAVED' : 'SERVER STATUS • DEMO',
      subtitle: compact ? '${filtered.length} nodes • ${display.length} shown' : '${filtered.length} nodes • ${_servers.where((s)=>s.status==Status.operational).length} healthy',
      trailing: compact
          ? InkWell(onTap: () => _goTo(1), child: const Text('VIEW ALL →', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: AppColors.accentCyan)))
          : (_useRealServers
              ? InkWell(onTap: () => _goTo(11), child: Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4), decoration: BoxDecoration(color: AppColors.accentCyan.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(6), border: Border.all(color: AppColors.accentCyan.withValues(alpha: 0.2))), child: const Text('+ MANAGE', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: AppColors.accentCyan))))
              : Wrap(spacing: 6, children: [_filterChip('all','All'),_filterChip('operational','OK'),_filterChip('degraded','Warn'),_filterChip('down','Down')])),
      child: Column(children: [
        if (filtered.isEmpty)
          Padding(padding: const EdgeInsets.all(16), child: Column(children: [const Icon(Icons.dns_outlined, size: 24, color: AppColors.textMuted), const SizedBox(height: 8), const Text('No servers yet', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.textPrimary)), const SizedBox(height: 8), FilledButton(onPressed: () => _goTo(11), style: FilledButton.styleFrom(backgroundColor: AppColors.accentCyan, foregroundColor: Colors.black), child: const Text('ADD SERVER IN SETTINGS', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800)))]))
        else ...[
          for (final s in display)
            Container(
              margin: EdgeInsets.only(bottom: compact ? 8 : 10),
              padding: EdgeInsets.all(compact ? 10 : 12),
              decoration: BoxDecoration(color: AppColors.surface1, borderRadius: BorderRadius.circular(10), border: Border.all(color: AppColors.borderLight)),
              child: InkWell(
                onTap: _useRealServers ? () => _openServerDetails(s.id) : null,
                child: Column(children: [
                  Row(children: [
                    StatusDot(color: statusColor(s.status)),
                    const SizedBox(width: 8),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [Flexible(child: Text(s.name, style: TextStyle(color: AppColors.textPrimary, fontSize: compact ? 12 : 13, fontWeight: FontWeight.w700), overflow: TextOverflow.ellipsis)), const SizedBox(width: 5), Container(padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1), decoration: BoxDecoration(color: AppColors.surface2, borderRadius: BorderRadius.circular(4)), child: Text(s.os.split(' ').first, style: const TextStyle(fontSize: 8, color: AppColors.textMuted)))]),
                      // Spec 02 §2.2: reachability line promoted to textSecondary;
                      // latency is the scanned value — textPrimary semibold.
                      Text.rich(TextSpan(
                        style: TextStyle(fontSize: compact ? 10 : 11, color: AppColors.textSecondary),
                        children: [
                          TextSpan(text: '${s.ip} • ${s.region} • '),
                          if (_useRealServers && s.latencyMs == 0)
                            const TextSpan(text: 'no metrics yet')
                          else
                            TextSpan(text: '${s.latencyMs.toInt()}ms', style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w600)),
                        ],
                      )),
                    ])),
                    Pill(text: s.status.name.toUpperCase(), color: statusColor(s.status)),
                  ]),
                  SizedBox(height: compact ? 6 : 10),
                  if (_useRealServers)
                    Builder(builder: (_) {
                      final conn = _savedServers.firstWhere((e) => e.id == s.id, orElse: () => _savedServers.first);
                      return _realServerBody(conn, s, compact);
                    })
                  else ...[
                    Row(children: [
                      Expanded(child: MetricBar(label: 'CPU', value: s.cpu, color: s.cpu > AppThresholds.cpuCritical ? AppColors.critical : AppColors.textSecondary)),
                      const SizedBox(width: 8),
                      Expanded(child: MetricBar(label: 'RAM', value: s.ram, color: s.ram > AppThresholds.ramCritical ? AppColors.critical : AppColors.textSecondary)),
                      const SizedBox(width: 8),
                      Expanded(child: MetricBar(label: 'DISK', value: s.disk, color: s.disk > AppThresholds.diskCritical ? AppColors.critical : s.disk > AppThresholds.diskWarn ? AppColors.warning : AppColors.textSecondary)),
                    ]),
                    const SizedBox(height: 6),
                    // Spec 02 §2.4: the trend exists as text too, wrapped in a
                    // Semantics label so screen readers get name + peak.
                    SizedBox(height: compact ? 18 : 24, child: Row(children: [
                      Expanded(child: _miniSparkline(s.sparkline, s.status==Status.degraded ? AppColors.warning : AppColors.success)),
                      const SizedBox(width: 8),
                      Semantics(
                        label: 'CPU trend, peak ${sparklineP95(s.sparkline)} percent over 5 minutes',
                        child: Text('cpu p95 ${sparklineP95(s.sparkline)}%', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: AppColors.textSecondary)),
                      ),
                    ])),
                  ],
                ]),
              ),
            ),
          if (compact && filtered.length > display.length)
            Container(margin: const EdgeInsets.only(top: 2), padding: const EdgeInsets.symmetric(vertical: 6), decoration: BoxDecoration(color: AppColors.surface1, borderRadius: BorderRadius.circular(8), border: Border.all(color: AppColors.borderLight)), child: Center(child: Text('+ ${filtered.length-display.length} more • tap VIEW ALL', style: const TextStyle(fontSize: 10, color: AppColors.textMuted, fontWeight: FontWeight.w600)))),
        ],
      ]),
      footer: compact ? null : Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text(_useRealServers ? 'Saved locally • Manage in Settings' : 'Demo data • Add servers in Settings', style: const TextStyle(fontSize: 11, color: AppColors.textMuted)),
        InkWell(onTap: () => _goTo(_useRealServers ? 10 : 1), child: Text(_useRealServers ? 'MANAGE →' : 'VIEW ALL →', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.accentCyan))),
      ]),
    );
  }

  Widget _filterChip(String val, String label) => ChoiceChip(
    label: Text(label, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: _serverFilter==val ? Colors.black : AppColors.textSecondary)),
    selected: _serverFilter==val, selectedColor: AppColors.accentCyan, backgroundColor: AppColors.surface2,
    side: BorderSide(color: _serverFilter==val ? AppColors.accentCyan : AppColors.border),
    onSelected: (v){ if (v) setState(()=> _serverFilter = val); }, materialTapTargetSize: MaterialTapTargetSize.shrinkWrap, visualDensity: VisualDensity.compact, padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
  );

  Widget _miniSparkline(List<double> vals, Color c) => LineChart(LineChartData(
    gridData: const FlGridData(show: false), titlesData: const FlTitlesData(show: false), borderData: FlBorderData(show: false),
    lineBarsData: [LineChartBarData(spots: [for (int i=0;i<vals.length;i++) FlSpot(i.toDouble(), vals[i])], isCurved: true, color: c, barWidth: 1.6, dotData: const FlDotData(show: false), belowBarData: BarAreaData(show: true, color: c.withValues(alpha: 0.08)))],
  ));

  /// Real discovered crons across all connected servers (empty until polled).
  List<CronEntry> get _realCrons => _serverCrons.values.expand((e) => e).toList();

  Widget _cronsSegment({bool compact = false}) {
    final hasReal = _realCrons.isNotEmpty;
    final loading = _cronLoading.isNotEmpty;
    if (_useRealServers && (hasReal || loading)) return _realCronsCard(compact: compact);
    // demo fallback (no servers, or poll found nothing yet and not loading)
    final display = compact ? mockCrons.take(3).toList() : mockCrons;
    return PitchCard(
      title: _useRealServers ? 'CRONJOBS • SCANNING…' : 'CRONJOBS • DEMO',
      subtitle: _useRealServers
          ? 'Discovering crontabs on ${_savedServers.length} server${_savedServers.length == 1 ? '' : 's'}…'
          : '${mockCrons.length} schedules',
      trailing: compact ? InkWell(onTap: () => _goTo(2), child: const Text('VIEW ALL →', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: AppColors.accentCyan))) : null,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          headingRowHeight: compact ? 28 : 36, dataRowMinHeight: compact ? 30 : 36, dataRowMaxHeight: compact ? 30 : 44,
          headingRowColor: WidgetStateProperty.all(AppColors.surface2), dataRowColor: WidgetStateProperty.all(Colors.transparent),
          headingTextStyle: TextStyle(fontSize: compact ? 9 : 10, fontWeight: FontWeight.w700, color: AppColors.textMuted),
          dataTextStyle: TextStyle(fontSize: compact ? 11 : 12, color: AppColors.textPrimary),
          columnSpacing: compact ? 14 : 20,
          columns: const [DataColumn(label: Text('JOB')), DataColumn(label: Text('SCHEDULE')), DataColumn(label: Text('LAST')), DataColumn(label: Text('DUR')), DataColumn(label: Text('STATUS')), DataColumn(label: Text('SERVER'))],
          rows: display.map((c) => DataRow(cells: [
            DataCell(Row(children: [Container(width: 5, height: 5, decoration: BoxDecoration(color: cronColor(c.status), shape: BoxShape.circle)), const SizedBox(width: 5), Text(c.name, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 11))])),
            DataCell(Text(c.schedule, style: const TextStyle(fontFamily: AppFonts.mono, fontSize: 10, color: AppColors.textSecondary))),
            DataCell(Text(timeAgo(c.lastRun), style: const TextStyle(fontSize: 10, color: AppColors.textSecondary))),
            DataCell(Text(c.duration, style: const TextStyle(fontSize: 10))),
            DataCell(Pill(text: c.status.name.toUpperCase(), color: cronColor(c.status))),
            DataCell(Text(c.server.split('-').last, style: const TextStyle(fontSize: 10, color: AppColors.textMuted))),
          ])).toList(),
        ),
      ),
    );
  }

  /// Cronjobs discovered live on the user's servers via SSH.
  Widget _realCronsCard({bool compact = false}) {
    final all = _realCrons;
    final display = compact ? all.take(4).toList() : all;
    final loading = _cronLoading.isNotEmpty;
    return PitchCard(
      title: 'CRONJOBS • ${_savedServers.length} SERVER${_savedServers.length == 1 ? '' : 'S'}',
      subtitle: '${all.length} jobs discovered${loading ? ' • scanning…' : ''}',
      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
        if (loading) const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.accentCyan)),
        if (loading) const SizedBox(width: 6),
        InkWell(
          onTap: () {
            setState(() { _serverCrons.clear(); _cronError = null; });
            _pollCrons();
          },
          child: const Row(children: [Icon(Icons.refresh, size: 11, color: AppColors.accentCyan), SizedBox(width: 3), Text('RESCAN', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: AppColors.accentCyan))]),
        ),
        if (compact) ...[const SizedBox(width: 10), InkWell(onTap: () => _goTo(2), child: const Text('VIEW ALL →', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: AppColors.accentCyan)))],
      ]),
      child: all.isEmpty
          ? Padding(
              padding: const EdgeInsets.all(14),
              child: Row(children: [
                const Icon(Icons.schedule_outlined, size: 16, color: AppColors.textMuted),
                const SizedBox(width: 8),
                Expanded(child: Text(_cronError ?? 'No crontab entries found on connected servers.', style: const TextStyle(fontSize: 11, color: AppColors.textMuted))),
              ]),
            )
          : Column(children: [
              for (final e in display)
                Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: () => _openCron(e),
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      margin: EdgeInsets.only(bottom: compact ? 6 : 8),
                      padding: EdgeInsets.all(compact ? 8 : 10),
                      decoration: BoxDecoration(color: AppColors.surface1, borderRadius: BorderRadius.circular(8), border: Border.all(color: AppColors.borderLight)),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Row(children: [
                          Container(width: 6, height: 6, decoration: const BoxDecoration(color: AppColors.success, shape: BoxShape.circle)),
                          const SizedBox(width: 6),
                          Expanded(child: Text(e.command, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.textPrimary, fontFamily: AppFonts.mono), maxLines: compact ? 1 : 2, overflow: TextOverflow.ellipsis)),
                          const SizedBox(width: 6),
                          const Icon(Icons.chevron_right, size: 14, color: AppColors.textDim),
                        ]),
                        const SizedBox(height: 4),
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(children: [
                            Text(e.schedule, style: const TextStyle(fontSize: 10, color: AppColors.accentCyan, fontFamily: AppFonts.mono)),
                            const SizedBox(width: 8),
                            Pill(text: e.serverName.toUpperCase(), color: AppColors.accentBlue),
                            const SizedBox(width: 6),
                            Text(e.source, style: const TextStyle(fontSize: 9, color: AppColors.textMuted, fontFamily: AppFonts.mono)),
                            const SizedBox(width: 6),
                            const Pill(text: 'SCHEDULED', color: AppColors.success),
                          ]),
                        ),
                      ]),
                    ),
                  ),
                ),
              if (compact && all.length > display.length)
                Center(child: Text('+ ${all.length - display.length} more • tap VIEW ALL', style: const TextStyle(fontSize: 10, color: AppColors.textMuted, fontWeight: FontWeight.w600))),
            ]),
      footer: compact
          ? null
          : (_cronError != null
              ? Row(children: [const Icon(Icons.info_outline, size: 12, color: AppColors.warning), const SizedBox(width: 6), Expanded(child: Text('Last scan: $_cronError', style: const TextStyle(fontSize: 10, color: AppColors.warning)))])
              : Row(children: [const Icon(Icons.check_circle, size: 12, color: AppColors.success), const SizedBox(width: 6), const Expanded(child: Text('Live from crontab • /etc/crontab • /etc/cron.d — rescans on tab switch', style: TextStyle(fontSize: 10, color: AppColors.textMuted)))])),
    );
  }

  Widget _appsSegment({bool compact = false}) {
    // Real discovered apps take over once any server reports them.
    if (_useRealServers && (_realApps.isNotEmpty || _appLoading.isNotEmpty)) return _realAppsCard(compact: compact);
    final display = compact ? mockApps.take(3).toList() : mockApps;
    return PitchCard(
      title: _useRealServers ? 'APPS • SCANNING…' : 'APPS • DEMO',
      subtitle: _useRealServers ? 'Discovering services on ${_savedServers.length} server${_savedServers.length == 1 ? '' : 's'}…' : (compact ? '3 of ${mockApps.length} shown' : '${mockApps.length} services'),
      trailing: compact ? InkWell(onTap: () => _goTo(3), child: const Text('VIEW ALL →', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: AppColors.accentCyan))) : null,
      child: Column(children: display.map((a) => Container(
        margin: EdgeInsets.only(bottom: compact ? 6 : 10), padding: EdgeInsets.all(compact ? 8 : 11),
        decoration: BoxDecoration(color: AppColors.surface1, borderRadius: BorderRadius.circular(10), border: Border.all(color: AppColors.borderLight)),
        child: Row(children: [
          Container(width: compact ? 28 : 36, height: compact ? 28 : 36, decoration: BoxDecoration(color: AppColors.surface2, borderRadius: BorderRadius.circular(7), border: Border.all(color: AppColors.border)), child: Icon(a.env==AppEnv.prod ? Icons.cloud_done : Icons.science_outlined, size: compact ? 12 : 16, color: a.env==AppEnv.prod ? AppColors.success : AppColors.warning)),
          const SizedBox(width: 8),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [Text(a.name, style: TextStyle(fontSize: compact ? 11 : 12, fontWeight: FontWeight.w700, color: AppColors.textPrimary)), const SizedBox(width: 5), Pill(text: a.env.name.toUpperCase(), color: a.env==AppEnv.prod ? AppColors.success : AppColors.warning)]),
            Text('${a.rps.toInt()} rps • ${a.errorRate}% err • ${a.containers}◻', style: TextStyle(fontSize: compact ? 10 : 11, color: AppColors.textMuted)),
          ])),
          StatusDot(color: statusColor(a.status), pulse: a.status!=Status.operational),
        ]),
      )).toList()),
    );
  }

  /// Apps discovered live on the user's servers (systemd + docker + ports).
  /// Extract port from a "listening :PORT" detail string.
  String _portOf(String detail) {
    final m = RegExp(r':(\d+)').firstMatch(detail);
    return m?.group(1) ?? '';
  }

  Widget _realAppsCard({bool compact = false}) {
    final all = _realApps;
    final display = compact ? all.take(4).toList() : all;
    final loading = _appLoading.isNotEmpty;
    IconData iconFor(AppEntry a) {
      switch (a.source) {
        case 'docker': return Icons.inventory_2_outlined;
        case 'port': return Icons.hub_outlined;
        default: return Icons.settings_applications_outlined;
      }
    }
    Color colorFor(AppEntry a) {
      switch (a.source) {
        case 'docker': return AppColors.accentBlue;
        case 'port': return AppColors.accentPurple;
        default: return AppColors.success;
      }
    }
    return PitchCard(
      title: 'APPS • ${_savedServers.length} SERVER${_savedServers.length == 1 ? '' : 'S'}',
      subtitle: '${all.length} services discovered${loading ? ' • scanning…' : ''}',
      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
        if (loading) const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.accentCyan)),
        if (loading) const SizedBox(width: 6),
        InkWell(
          onTap: () {
            setState(() { _serverApps.clear(); _appError = null; });
            _pollApps();
          },
          child: const Row(children: [Icon(Icons.refresh, size: 11, color: AppColors.accentCyan), SizedBox(width: 3), Text('RESCAN', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: AppColors.accentCyan))]),
        ),
        if (compact) ...[const SizedBox(width: 10), InkWell(onTap: () => _goTo(3), child: const Text('VIEW ALL →', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: AppColors.accentCyan)))],
      ]),
      child: all.isEmpty
          ? Padding(
              padding: const EdgeInsets.all(14),
              child: Row(children: [
                const Icon(Icons.apps_outlined, size: 16, color: AppColors.textMuted),
                const SizedBox(width: 8),
                Expanded(child: Text(_appError ?? 'No services found on connected servers.', style: const TextStyle(fontSize: 11, color: AppColors.textMuted))),
              ]),
            )
          : Column(children: [
              for (final a in display)
                Builder(builder: (_) {
                  final proc = _procStats[a.serverId]?.matchForApp(a.name);
                  final est = a.source == 'port'
                      ? _procStats[a.serverId]?.ports[_portOf(a.detail)]?.established
                      : null;
                  return Container(
                  margin: EdgeInsets.only(bottom: compact ? 6 : 8),
                  padding: EdgeInsets.all(compact ? 8 : 10),
                  decoration: BoxDecoration(color: AppColors.surface1, borderRadius: BorderRadius.circular(8), border: Border.all(color: AppColors.borderLight)),
                  child: Row(children: [
                    Container(width: compact ? 28 : 32, height: compact ? 28 : 32, decoration: BoxDecoration(color: colorFor(a).withValues(alpha: 0.12), borderRadius: BorderRadius.circular(7), border: Border.all(color: colorFor(a).withValues(alpha: 0.2))), child: Icon(iconFor(a), size: compact ? 12 : 14, color: colorFor(a))),
                    const SizedBox(width: 8),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        Flexible(child: Text(a.name, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.textPrimary), overflow: TextOverflow.ellipsis)),
                        const SizedBox(width: 5),
                        if (proc != null)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                            decoration: BoxDecoration(color: (proc.cpu > 0.75 ? AppColors.critical : AppColors.success).withValues(alpha: 0.12), borderRadius: BorderRadius.circular(4)),
                            child: Text('CPU ${(proc.cpu * 100).toInt()}% • ${proc.memMb}MB', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w800, color: proc.cpu > 0.75 ? AppColors.critical : AppColors.success, fontFamily: AppFonts.mono)),
                          )
                        else if (est != null && est > 0)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                            decoration: BoxDecoration(color: AppColors.accentPurple.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(4)),
                            child: Text('$est CONN', style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w800, color: AppColors.accentPurple, fontFamily: AppFonts.mono)),
                          ),
                        Pill(text: a.source.toUpperCase(), color: colorFor(a)),
                      ]),
                      const SizedBox(height: 4),
                      Row(children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                          decoration: BoxDecoration(color: AppColors.accentCyan.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(4), border: Border.all(color: AppColors.accentCyan.withValues(alpha: 0.25))),
                          child: Row(mainAxisSize: MainAxisSize.min, children: [
                            const Icon(Icons.dns, size: 9, color: AppColors.accentCyan),
                            const SizedBox(width: 3),
                            Text(a.serverName.toUpperCase(), style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w800, letterSpacing: 0.3, color: AppColors.accentCyan)),
                          ]),
                        ),
                        const SizedBox(width: 6),
                        Expanded(child: Text(a.detail, style: const TextStyle(fontSize: 10, color: AppColors.textMuted, fontFamily: AppFonts.mono), maxLines: 1, overflow: TextOverflow.ellipsis)),
                      ]),
                    ])),
                    StatusDot(color: AppColors.success, pulse: false),
                  ]),
                  );
                }),
              if (compact && all.length > display.length)
                Center(child: Text('+ ${all.length - display.length} more • tap VIEW ALL', style: const TextStyle(fontSize: 10, color: AppColors.textMuted, fontWeight: FontWeight.w600))),
            ]),
      footer: compact
          ? null
          : const Row(children: [Icon(Icons.check_circle, size: 12, color: AppColors.success), SizedBox(width: 6), Expanded(child: Text('Live from systemd • docker • listening ports — rescans on tab switch', style: TextStyle(fontSize: 10, color: AppColors.textMuted)))]),
    );
  }

  Widget _githubSegment({bool compact = false}) {
    // Live data once a PAT + repos are configured in Settings.
    if (_ghConfigured && (_ghIssues.isNotEmpty || _ghPRs.isNotEmpty || _ghTasks.isNotEmpty || _ghLoading || _ghError != null)) {
      return _realGithubCard(compact: compact);
    }
    final data = _githubTab==0 ? mockIssues : _githubTab==1 ? mockPRs : mockTasks;
    final display = compact ? data.take(2).toList() : data;
    return PitchCard(
      title: 'GITHUB • DEMO',
      subtitle: _ghToken.isNotEmpty ? 'Token saved — add repos in Settings to go live' : 'Add a token in Settings to go live',
      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
        FilledButton(
          onPressed: () => _goTo(11),
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.accentCyan,
            foregroundColor: Colors.black,
            minimumSize: const Size(48, 40),
            tapTargetSize: MaterialTapTargetSize.padded,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            textStyle: const TextStyle(fontSize: 10, fontWeight: FontWeight.w800),
          ),
          child: const Text('OPEN SETTINGS'),
        ),
        if (compact) ...[const SizedBox(width: 8), InkWell(onTap: () => _goTo(4), child: const Text('VIEW ALL →', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: AppColors.accentCyan)))],
      ]),
      child: Column(children: [
        ToggleButtons(
          isSelected: [_githubTab==0, _githubTab==1, _githubTab==2], onPressed: (i)=> setState(()=> _githubTab=i),
          borderRadius: BorderRadius.circular(7), selectedColor: Colors.black, fillColor: AppColors.accentCyan, color: AppColors.textSecondary, borderColor: AppColors.border, selectedBorderColor: AppColors.accentCyan,
          constraints: const BoxConstraints(minHeight: 24, minWidth: 44),
          children: const [Text('Issues', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700)), Text('PRs', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700)), Text('Tasks', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700))],
        ),
        const SizedBox(height: 8),
        for (final item in display)
          Container(
            margin: const EdgeInsets.only(bottom: 6), padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: AppColors.surface1, borderRadius: BorderRadius.circular(8), border: Border.all(color: AppColors.borderLight)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [Container(padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1), decoration: BoxDecoration(color: AppColors.surface2, borderRadius: BorderRadius.circular(4), border: Border.all(color: AppColors.border)), child: Text('#${item.number}', style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: AppColors.textSecondary, fontFamily: AppFonts.mono))), const SizedBox(width: 5), Expanded(child: Text(item.title, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.textPrimary), maxLines: 1, overflow: TextOverflow.ellipsis))]),
              const SizedBox(height: 4),
              Row(children: [Text(item.repo.split('/').last, style: const TextStyle(fontSize: 9, color: AppColors.textMuted)), const Spacer(), Pill(text: item.state.toUpperCase(), color: item.state=='open' ? AppColors.success : AppColors.textMuted)]),
            ]),
          ),
      ]),
    );
  }

  /// Retry helper shared by the SYNC button and the StateView RETRY action.
  void _retryGithub() {
    setState(() { _ghIssues = []; _ghPRs = []; _ghTasks = []; _ghProjects = []; _ghTasksSource = ''; _ghError = null; });
    _pollGithub();
  }

  /// GitHub rendered from the user's live API data.
  Widget _realGithubCard({bool compact = false}) {
    final data = _githubTab == 0 ? _ghIssues : _githubTab == 1 ? _ghPRs : _ghTasks;
    final display = compact ? data.take(3).toList() : data;
    final tabName = _githubTab == 0 ? 'issues' : _githubTab == 1 ? 'PRs' : 'tasks';
    return PitchCard(
      title: 'GITHUB • @$_ghUser',
      subtitle: _ghLoading
          ? 'syncing…'
          : _ghError != null
              ? _ghError!
              : '${_ghRepos.length} repo${_ghRepos.length == 1 ? '' : 's'} • ${_ghIssues.length} issues • ${_ghPRs.length} PRs • ${_ghTasks.length} tasks${_ghTasksFromProjects ? ' (Projects v2)' : ''}${_ghProjects.isNotEmpty ? ' • ${_ghProjects.length} boards' : ''}',
      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
        if (_ghLoading) const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.accentCyan)),
        if (_ghLoading) const SizedBox(width: 6),
        TextButton.icon(
          onPressed: _retryGithub,
          icon: const Icon(Icons.refresh, size: 11, color: AppColors.accentCyan),
          label: const Text('SYNC', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: AppColors.accentCyan)),
          style: TextButton.styleFrom(
            minimumSize: const Size(48, 32),
            tapTargetSize: MaterialTapTargetSize.padded,
            padding: const EdgeInsets.symmetric(horizontal: 6),
          ),
        ),
        if (compact) ...[const SizedBox(width: 10), InkWell(onTap: () => _goTo(4), child: const Text('VIEW ALL →', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: AppColors.accentCyan)))],
      ]),
      child: Column(children: [
        ToggleButtons(
          isSelected: [_githubTab==0, _githubTab==1, _githubTab==2], onPressed: (i)=> setState(()=> _githubTab=i),
          borderRadius: BorderRadius.circular(7), selectedColor: Colors.black, fillColor: AppColors.accentCyan, color: AppColors.textSecondary, borderColor: AppColors.border, selectedBorderColor: AppColors.accentCyan,
          constraints: const BoxConstraints(minHeight: 24, minWidth: 44),
          children: [Text('Issues (${_ghIssues.length})', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700)), Text('PRs (${_ghPRs.length})', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700)), Text('Tasks (${_ghTasks.length})${_ghTasksFromProjects ? ' ▣' : ''}', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700))],
        ),
        const SizedBox(height: 8),
        if (_ghLoading && data.isEmpty)
          StateView(
            state: PanelState.loading,
            loadingLabel: 'Syncing GitHub…',
            compact: compact,
          )
        else if (data.isEmpty)
          StateView(
            state: _ghError != null ? PanelState.error : PanelState.empty,
            icon: _ghError != null ? Icons.error_outline : Icons.check_circle,
            headline: _ghError != null ? 'GITHUB SYNC FAILED' : 'QUEUE IS CLEAR',
            body: _ghError ?? 'No open $tabName across ${_ghRepos.length} repo${_ghRepos.length == 1 ? '' : 's'} ✓',
            actionLabel: _ghError != null ? 'RETRY' : null,
            onAction: _ghError != null ? _retryGithub : null,
            semanticLabel: _ghError != null ? 'GitHub sync failed' : 'GitHub queue is clear',
            compact: compact,
          )
        else
          for (final item in display)
            Container(
              margin: const EdgeInsets.only(bottom: 6), padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: AppColors.surface1, borderRadius: BorderRadius.circular(8), border: Border.all(color: AppColors.borderLight)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Container(padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1), decoration: BoxDecoration(color: AppColors.surface2, borderRadius: BorderRadius.circular(4), border: Border.all(color: AppColors.border)), child: Text('#${item.number}', style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: AppColors.textSecondary, fontFamily: AppFonts.mono))),
                  const SizedBox(width: 5),
                  Expanded(child: Text(item.title, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.textPrimary), maxLines: compact ? 1 : 2, overflow: TextOverflow.ellipsis)),
                ]),
                const SizedBox(height: 5),
                Row(children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                    decoration: BoxDecoration(color: AppColors.accentCyan.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(4), border: Border.all(color: AppColors.accentCyan.withValues(alpha: 0.25))),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      const Icon(Icons.book_outlined, size: 8, color: AppColors.accentCyan),
                      const SizedBox(width: 3),
                      Text(item.repo.toUpperCase(), style: const TextStyle(fontSize: 8, fontWeight: FontWeight.w800, letterSpacing: 0.3, color: AppColors.accentCyan)),
                    ]),
                  ),
                  const SizedBox(width: 6),
                  const Icon(Icons.person_outline, size: 10, color: AppColors.textMuted),
                  const SizedBox(width: 2),
                  Flexible(child: Text(item.author, style: const TextStyle(fontSize: 10, color: AppColors.textMuted), maxLines: 1, overflow: TextOverflow.ellipsis)),
                  if (item.labels.isNotEmpty) ...[
                    const SizedBox(width: 6),
                    Flexible(child: Text(item.labels.take(2).join(' • '), style: const TextStyle(fontSize: 9, color: AppColors.accentPurple), maxLines: 1, overflow: TextOverflow.ellipsis)),
                  ],
                ]),
                const SizedBox(height: 4),
                Row(children: [
                  Text(timeAgo(item.updatedAt), style: const TextStyle(fontSize: 10, color: AppColors.textDim)),
                  const SizedBox(width: 8),
                  const Icon(Icons.chat_bubble_outline, size: 10, color: AppColors.textDim),
                  Text(' ${item.comments}', style: const TextStyle(fontSize: 10, color: AppColors.textDim)),
                  const Spacer(),
                  Pill(text: item.state.toUpperCase(), color: item.state == 'open' ? AppColors.success : AppColors.textMuted),
                ]),
              ]),
            ),
        if (compact && data.length > display.length)
          Center(child: Text('+ ${data.length - display.length} more • tap VIEW ALL', style: const TextStyle(fontSize: 10, color: AppColors.textMuted, fontWeight: FontWeight.w600))),
      ]),
    );
  }

  /// Shared issue/MR row builder (GitLab uses the same shape as GitHub items).
  Widget _vcsRow(GithubItem item, {bool compact = false, Color accent = AppColors.accentCyan}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6), padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(color: AppColors.surface1, borderRadius: BorderRadius.circular(8), border: Border.all(color: AppColors.borderLight)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1), decoration: BoxDecoration(color: AppColors.surface2, borderRadius: BorderRadius.circular(4), border: Border.all(color: AppColors.border)), child: Text(item.number > 0 ? '!${item.number}' : '#${item.number}', style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: AppColors.textSecondary, fontFamily: AppFonts.mono))),
          const SizedBox(width: 5),
          Expanded(child: Text(item.title, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.textPrimary), maxLines: compact ? 1 : 2, overflow: TextOverflow.ellipsis)),
        ]),
        const SizedBox(height: 5),
        Row(children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
            decoration: BoxDecoration(color: accent.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(4), border: Border.all(color: accent.withValues(alpha: 0.25))),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.book_outlined, size: 8, color: accent),
              const SizedBox(width: 3),
              Text(item.repo.toUpperCase(), style: TextStyle(fontSize: 8, fontWeight: FontWeight.w800, letterSpacing: 0.3, color: accent)),
            ]),
          ),
          const SizedBox(width: 6),
          const Icon(Icons.person_outline, size: 10, color: AppColors.textMuted),
          const SizedBox(width: 2),
          Flexible(child: Text(item.author, style: const TextStyle(fontSize: 10, color: AppColors.textMuted), maxLines: 1, overflow: TextOverflow.ellipsis)),
          if (item.labels.isNotEmpty) ...[
            const SizedBox(width: 6),
            Flexible(child: Text(item.labels.take(2).join(' • '), style: const TextStyle(fontSize: 9, color: AppColors.accentPurple), maxLines: 1, overflow: TextOverflow.ellipsis)),
          ],
        ]),
        const SizedBox(height: 4),
        Row(children: [
          Text(timeAgo(item.updatedAt), style: const TextStyle(fontSize: 10, color: AppColors.textDim)),
          const SizedBox(width: 8),
          const Icon(Icons.chat_bubble_outline, size: 10, color: AppColors.textDim),
          Text(' ${item.comments}', style: const TextStyle(fontSize: 10, color: AppColors.textDim)),
          const Spacer(),
          Pill(text: item.state.toUpperCase(), color: item.state == 'open' ? AppColors.success : AppColors.textMuted),
        ]),
      ]),
    );
  }

  Widget _gitlabSegment({bool compact = false}) {
    if (_glConfigured && (_glIssues.isNotEmpty || _glMrs.isNotEmpty || _glTasks.isNotEmpty || _glLoading || _glError != null)) {
      return _realGitlabCard(compact: compact);
    }
    final data = _gitlabTab == 0 ? mockIssues : _gitlabTab == 1 ? mockPRs : mockTasks;
    final display = compact ? data.take(2).toList() : data;
    return PitchCard(
      title: 'GITLAB • DEMO',
      subtitle: _glToken.isNotEmpty ? 'Token saved — add projects in Settings to go live' : 'Add a token in Settings to go live',
      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
        InkWell(onTap: () => _goTo(11), child: Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4), decoration: BoxDecoration(color: AppColors.accentPurple.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(6), border: Border.all(color: AppColors.accentPurple.withValues(alpha: 0.2))), child: const Text('+ CONNECT', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: AppColors.accentPurple)))),
        if (compact) ...[const SizedBox(width: 8), InkWell(onTap: () => _goTo(5), child: const Text('VIEW ALL →', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: AppColors.accentCyan)))],
      ]),
      child: Column(children: [
        ToggleButtons(
          isSelected: [_gitlabTab == 0, _gitlabTab == 1, _gitlabTab == 2], onPressed: (i) => setState(() => _gitlabTab = i),
          borderRadius: BorderRadius.circular(7), selectedColor: Colors.black, fillColor: AppColors.accentPurple, color: AppColors.textSecondary, borderColor: AppColors.border, selectedBorderColor: AppColors.accentPurple,
          constraints: const BoxConstraints(minHeight: 24, minWidth: 44),
          children: const [Text('Issues', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700)), Text('MRs', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700)), Text('Tasks', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700))],
        ),
        const SizedBox(height: 8),
        for (final item in display) _vcsRow(item, compact: compact, accent: AppColors.accentPurple),
      ]),
    );
  }

  /// GitLab rendered from the user's live instance data.
  Widget _realGitlabCard({bool compact = false}) {
    final data = _gitlabTab == 0 ? _glIssues : _gitlabTab == 1 ? _glMrs : _glTasks;
    final display = compact ? data.take(3).toList() : data;
    final tabName = _gitlabTab == 0 ? 'issues' : _gitlabTab == 1 ? 'MRs' : 'tasks';
    return PitchCard(
      title: 'GITLAB • @$_glUser',
      subtitle: _glLoading
          ? 'syncing…'
          : _glError != null
              ? _glError!
              : '${_glProjects.length} project${_glProjects.length == 1 ? '' : 's'} • ${_glIssues.length} issues • ${_glMrs.length} MRs • ${_glTasks.length} tasks',
      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
        if (_glLoading) const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.accentPurple)),
        if (_glLoading) const SizedBox(width: 6),
        InkWell(
          onTap: () {
            setState(() { _glIssues = []; _glMrs = []; _glTasks = []; _glError = null; });
            _pollGitlab();
          },
          child: const Row(children: [Icon(Icons.refresh, size: 11, color: AppColors.accentPurple), SizedBox(width: 3), Text('SYNC', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: AppColors.accentPurple))]),
        ),
        if (compact) ...[const SizedBox(width: 10), InkWell(onTap: () => _goTo(5), child: const Text('VIEW ALL →', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: AppColors.accentCyan)))],
      ]),
      child: Column(children: [
        ToggleButtons(
          isSelected: [_gitlabTab == 0, _gitlabTab == 1, _gitlabTab == 2], onPressed: (i) => setState(() => _gitlabTab = i),
          borderRadius: BorderRadius.circular(7), selectedColor: Colors.black, fillColor: AppColors.accentPurple, color: AppColors.textSecondary, borderColor: AppColors.border, selectedBorderColor: AppColors.accentPurple,
          constraints: const BoxConstraints(minHeight: 24, minWidth: 44),
          children: [Text('Issues (${_glIssues.length})', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700)), Text('MRs (${_glMrs.length})', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700)), Text('Tasks (${_glTasks.length})', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700))],
        ),
        const SizedBox(height: 8),
        if (data.isEmpty && !_glLoading)
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(children: [
              Icon(_glError != null ? Icons.error_outline : Icons.check_circle, size: 15, color: _glError != null ? AppColors.warning : AppColors.success),
              const SizedBox(width: 8),
              Expanded(child: Text(_glError ?? 'No open $tabName — queue is clear ✓', style: const TextStyle(fontSize: 11, color: AppColors.textMuted))),
            ]),
          )
        else
          for (final item in display) _vcsRow(item, compact: compact, accent: AppColors.accentPurple),
        if (compact && data.length > display.length)
          Center(child: Text('+ ${data.length - display.length} more • tap VIEW ALL', style: const TextStyle(fontSize: 10, color: AppColors.textMuted, fontWeight: FontWeight.w600))),
      ]),
    );
  }

  Widget _alertsSegment({bool compact = false}) {
    // Connected servers ALWAYS get the real card (with server badges) —
    // never demo alerts. Empty/error states explain themselves inside.
    if (_useRealServers) return _realAlertsCard(compact: compact);
    final display = compact ? mockAlerts.take(3).toList() : mockAlerts;
    return PitchCard(
      title: _useRealServers ? 'ALERTS • SCANNING…' : 'ALERTS • DEMO',
      subtitle: _useRealServers ? 'Harvesting signals from ${_savedServers.length} server${_savedServers.length == 1 ? '' : 's'}…' : '${mockAlerts.where((a)=>a.status=='firing').length} firing',
      trailing: compact ? InkWell(onTap: () => _goTo(6), child: const Text('VIEW ALL →', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: AppColors.accentCyan))) : null,
      child: Column(children: display.map((a) => Container(
        margin: EdgeInsets.only(bottom: compact ? 6 : 8), padding: EdgeInsets.all(compact ? 8 : 10),
        decoration: BoxDecoration(color: AppColors.surface1, borderRadius: BorderRadius.circular(8), border: Border.all(color: a.severity=='critical' ? AppColors.critical.withValues(alpha: 0.3) : AppColors.borderLight)),
        child: Row(children: [
          Container(width: compact ? 22 : 28, height: compact ? 22 : 28, decoration: BoxDecoration(color: severityColor(a.severity).withValues(alpha: 0.12), borderRadius: BorderRadius.circular(6)), child: Icon(a.severity=='critical' ? Icons.error_outline : a.severity=='warning' ? Icons.warning_amber : Icons.info_outline, size: compact ? 11 : 14, color: severityColor(a.severity))),
          const SizedBox(width: 8),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(a.title, style: TextStyle(fontSize: compact ? 11 : 12, fontWeight: FontWeight.w600, color: AppColors.textPrimary), maxLines: 1, overflow: TextOverflow.ellipsis),
            Text('${a.source.split('•').first.trim()} • ${timeAgo(a.time)}', style: const TextStyle(fontSize: 9, color: AppColors.textMuted)),
          ])),
          Pill(text: a.status.toUpperCase(), color: a.status=='firing' ? AppColors.critical : AppColors.success),
        ]),
      )).toList()),
    );
  }

  /// Alerts harvested live from the user's servers.
  Widget _realAlertsCard({bool compact = false}) {
    final all = _realAlerts;
    final display = compact ? all.take(3).toList() : all;
    final loading = _alertLoading.isNotEmpty;
    final firing = all.where((a) => a.status == 'firing').length;
    return PitchCard(
      title: 'ALERTS • ${_savedServers.length} SERVER${_savedServers.length == 1 ? '' : 'S'}',
      subtitle: all.isEmpty ? (loading ? 'scanning…' : 'no firing signals ✓') : '$firing firing • ${all.length} total',
      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
        if (loading) const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.accentCyan)),
        if (loading) const SizedBox(width: 6),
        InkWell(
          onTap: () {
            setState(() { _serverAlerts.clear(); _alertError = null; });
            _pollAlerts();
          },
          child: const Row(children: [Icon(Icons.refresh, size: 11, color: AppColors.accentCyan), SizedBox(width: 3), Text('RESCAN', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: AppColors.accentCyan))]),
        ),
        if (compact) ...[const SizedBox(width: 10), InkWell(onTap: () => _goTo(6), child: const Text('VIEW ALL →', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: AppColors.accentCyan)))],
      ]),
      child: all.isEmpty
          ? Padding(
              padding: const EdgeInsets.all(14),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Icon(loading ? Icons.radar : (_alertError != null ? Icons.error_outline : Icons.check_circle), size: 16, color: loading ? AppColors.accentCyan : (_alertError != null ? AppColors.warning : AppColors.success)),
                const SizedBox(width: 8),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(
                    loading
                        ? 'Harvesting signals via SSH…'
                        : (_alertError ?? 'Healthy — no failed units, disk OK, no brute force, load normal.'),
                    style: const TextStyle(fontSize: 11, color: AppColors.textMuted),
                  ),
                  if (!loading && _alertError != null) ...[
                    const SizedBox(height: 6),
                    ..._savedServers.map((s) => Padding(
                          padding: const EdgeInsets.only(bottom: 3),
                          child: Row(children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                              decoration: BoxDecoration(color: AppColors.surface2, borderRadius: BorderRadius.circular(4), border: Border.all(color: AppColors.border)),
                              child: Row(mainAxisSize: MainAxisSize.min, children: [
                                const Icon(Icons.dns, size: 8, color: AppColors.textMuted),
                                const SizedBox(width: 3),
                                Text(s.name.toUpperCase(), style: const TextStyle(fontSize: 8, fontWeight: FontWeight.w800, letterSpacing: 0.3, color: AppColors.textSecondary)),
                              ]),
                            ),
                            const SizedBox(width: 6),
                            const Expanded(child: Text('scan failed — tap RESCAN', style: TextStyle(fontSize: 10, color: AppColors.textMuted))),
                          ]),
                        )),
                  ],
                ])),
              ]),
            )
          : Column(children: [
              for (final a in display)
                Container(
                  margin: EdgeInsets.only(bottom: compact ? 6 : 8),
                  padding: EdgeInsets.all(compact ? 8 : 10),
                  decoration: BoxDecoration(color: AppColors.surface1, borderRadius: BorderRadius.circular(8), border: Border.all(color: a.severity == 'critical' ? AppColors.critical.withValues(alpha: 0.3) : AppColors.borderLight)),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Container(width: compact ? 22 : 28, height: compact ? 22 : 28, decoration: BoxDecoration(color: severityColor(a.severity).withValues(alpha: 0.12), borderRadius: BorderRadius.circular(6)), child: Icon(a.severity == 'critical' ? Icons.error_outline : a.severity == 'warning' ? Icons.warning_amber : Icons.info_outline, size: compact ? 11 : 14, color: severityColor(a.severity))),
                    const SizedBox(width: 8),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(a.title, style: TextStyle(fontSize: compact ? 11 : 12, fontWeight: FontWeight.w600, color: AppColors.textPrimary), maxLines: compact ? 1 : 2, overflow: TextOverflow.ellipsis),
                      const SizedBox(height: 3),
                      Row(children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                          decoration: BoxDecoration(color: AppColors.accentCyan.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(4), border: Border.all(color: AppColors.accentCyan.withValues(alpha: 0.25))),
                          child: Row(mainAxisSize: MainAxisSize.min, children: [
                            const Icon(Icons.dns, size: 8, color: AppColors.accentCyan),
                            const SizedBox(width: 3),
                            Text(a.serverName.toUpperCase(), style: const TextStyle(fontSize: 8, fontWeight: FontWeight.w800, letterSpacing: 0.3, color: AppColors.accentCyan)),
                          ]),
                        ),
                        const SizedBox(width: 6),
                        Expanded(child: Text(a.source, style: const TextStyle(fontSize: 9, color: AppColors.textMuted), maxLines: 1, overflow: TextOverflow.ellipsis)),
                      ]),
                    ])),
                    const SizedBox(width: 6),
                    Pill(text: a.status.toUpperCase(), color: a.status == 'firing' ? AppColors.critical : AppColors.success),
                  ]),
                ),
              if (compact && all.length > display.length)
                Center(child: Text('+ ${all.length - display.length} more • tap VIEW ALL', style: const TextStyle(fontSize: 10, color: AppColors.textMuted, fontWeight: FontWeight.w600))),
            ]),
      footer: compact
          ? null
          : const Row(children: [Icon(Icons.check_circle, size: 12, color: AppColors.success), SizedBox(width: 6), Expanded(child: Text('Live: failed units • disk • SSH brute force • load • kernel • uptime', style: TextStyle(fontSize: 10, color: AppColors.textMuted)))]),
    );
  }

  /// Merged CI/CD timeline via [DeploymentsService] (newest first).
  List<DeployItem> get _allRuns =>
      DeploymentsService.merge(_ghRuns, _glPipes);

  bool get _ciConfigured => _ghConfigured || _glConfigured;
  bool get _ciLoading => _ghLoading || _glLoading;
  String? get _ciError => _ghError ?? _glError;

  Widget _deploysSegment({bool compact = false}) {
    // Live runs once either VCS is configured.
    if (_ciConfigured && (_allRuns.isNotEmpty || _ciLoading || _ciError != null)) return _realDeploysCard(compact: compact);
    final display = compact ? mockDeploys.take(3).toList() : mockDeploys;
    return PitchCard(
      title: 'CI/CD • DEMO', subtitle: compact ? '3 of ${mockDeploys.length} shown' : 'Last 6 deployments',
      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
        InkWell(onTap: () => _goTo(11), child: Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4), decoration: BoxDecoration(color: AppColors.accentCyan.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(6), border: Border.all(color: AppColors.accentCyan.withValues(alpha: 0.2))), child: const Text('+ CONNECT', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: AppColors.accentCyan)))),
        if (compact) ...[const SizedBox(width: 8), InkWell(onTap: () => _goTo(7), child: const Text('VIEW ALL →', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: AppColors.accentCyan)))],
      ]),
      child: Column(children: display.map((d) => Container(
        margin: EdgeInsets.only(bottom: compact ? 6 : 8), padding: EdgeInsets.all(compact ? 8 : 10),
        decoration: BoxDecoration(color: AppColors.surface1, borderRadius: BorderRadius.circular(8), border: Border.all(color: AppColors.borderLight)),
        child: Row(children: [
          Container(width: compact ? 26 : 32, height: compact ? 26 : 32, decoration: BoxDecoration(color: d.status=='success' ? AppColors.success.withValues(alpha: 0.12) : AppColors.critical.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(7)), child: Icon(d.status=='success' ? Icons.check : Icons.close, size: compact ? 11 : 14, color: d.status=='success' ? AppColors.success : AppColors.critical)),
          const SizedBox(width: 8),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [Text(d.app, style: TextStyle(fontSize: compact ? 11 : 12, fontWeight: FontWeight.w700, color: AppColors.textPrimary)), const SizedBox(width: 5), Text(d.version, style: const TextStyle(fontSize: 10, color: AppColors.accentCyan, fontFamily: AppFonts.mono))]),
            Text('by ${d.actor} • ${timeAgo(d.time)}', style: const TextStyle(fontSize: 9, color: AppColors.textMuted)),
          ])),
        ]),
      )).toList()),
    );
  }

  /// Retry helper shared by the SYNC button and the StateView RETRY action.
  void _retryDeploys() {
    setState(() { _ghRuns = []; _ghError = null; _glPipes = []; _glError = null; });
    _pollGithub();
    _pollGitlab();
  }

  /// Open the run detail sheet (approve-first rerun/retry). No-op for
  /// demo rows: they carry no ids so the sheet shows detail only.
  void _openRun(DeployItem d) {
    if (!mounted) return;
    showRunDetailSheet(
      context: context,
      run: d,
      githubToken: _ghToken,
      githubRepos: _ghRepos,
      gitlabBaseUrl: _glBase,
      gitlabToken: _glToken,
      onChanged: () {
        setState(() { _ghRuns = []; _glPipes = []; _ghError = null; _glError = null; });
        _pollGithub();
        _pollGitlab();
      },
    );
  }

  /// CI/CD rendered from live runs: GitHub Actions + GitLab pipelines.
  Widget _realDeploysCard({bool compact = false}) {
    final all = _allRuns;
    final display = compact ? all.take(3).toList() : all;
    IconData statusIcon(String s) => s == 'success' ? Icons.check : s == 'failed' ? Icons.close : Icons.sync;
    Color statusColorFor(String s) => s == 'success' ? AppColors.success : s == 'failed' ? AppColors.critical : AppColors.warning;
    final sources = [
      if (_ghConfigured) 'GH:${_ghRuns.length}',
      if (_glConfigured) 'GL:${_glPipes.length}',
    ].join(' • ');
    return PitchCard(
      title: 'CI/CD • LIVE',
      subtitle: _ciLoading
          ? 'syncing…'
          : _ciError != null
              ? _ciError!
              : '${all.length} runs ($sources)',
      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
        if (_ciLoading) const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.accentCyan)),
        if (_ciLoading) const SizedBox(width: 6),
        TextButton.icon(
          onPressed: _retryDeploys,
          icon: const Icon(Icons.refresh, size: 11, color: AppColors.accentCyan),
          label: const Text('SYNC', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: AppColors.accentCyan)),
          style: TextButton.styleFrom(
            minimumSize: const Size(48, 32),
            tapTargetSize: MaterialTapTargetSize.padded,
            padding: const EdgeInsets.symmetric(horizontal: 6),
          ),
        ),
        if (compact) ...[const SizedBox(width: 10), InkWell(onTap: () => _goTo(7), child: const Text('VIEW ALL →', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: AppColors.accentCyan)))],
      ]),
      child: _ciLoading && all.isEmpty
          ? StateView(
              state: PanelState.loading,
              loadingLabel: 'Syncing pipelines…',
              compact: compact,
            )
          : all.isEmpty
              ? StateView(
                  state: _ciError != null ? PanelState.error : PanelState.empty,
                  icon: _ciError != null ? Icons.error_outline : Icons.rocket_launch_outlined,
                  headline: _ciError != null ? 'DEPLOY HISTORY UNAVAILABLE' : 'NO RUNS YET',
                  body: _ciError ?? 'Push to a tracked repo or check the Actions tab on GitHub.',
                  actionLabel: _ciError != null ? 'RETRY' : null,
                  onAction: _ciError != null ? _retryDeploys : null,
                  semanticLabel: _ciError != null ? 'Deploy history unavailable' : 'No deploy runs yet',
                  compact: compact,
                )
              : Column(children: display.map((d) {
              final isGl = d.vcs == 'gitlab';
              final vcsColor = isGl ? AppColors.accentPurple : AppColors.textPrimary;
              return InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: () => _openRun(d),
              child: Container(
              margin: EdgeInsets.only(bottom: compact ? 6 : 8), padding: EdgeInsets.all(compact ? 8 : 10),
              decoration: BoxDecoration(color: AppColors.surface1, borderRadius: BorderRadius.circular(8), border: Border.all(color: d.status == 'failed' ? AppColors.critical.withValues(alpha: 0.25) : AppColors.borderLight)),
              child: Row(children: [
                Container(width: compact ? 26 : 32, height: compact ? 26 : 32, decoration: BoxDecoration(color: statusColorFor(d.status).withValues(alpha: 0.12), borderRadius: BorderRadius.circular(7), border: Border.all(color: statusColorFor(d.status).withValues(alpha: 0.2))), child: Icon(statusIcon(d.status), size: compact ? 11 : 14, color: statusColorFor(d.status))),
                const SizedBox(width: 8),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                      decoration: BoxDecoration(color: vcsColor.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(3), border: Border.all(color: vcsColor.withValues(alpha: 0.25))),
                      child: Text(isGl ? 'GL' : 'GH', style: TextStyle(fontSize: 8, fontWeight: FontWeight.w800, letterSpacing: 0.3, color: vcsColor)),
                    ),
                    const SizedBox(width: 5),
                    Flexible(child: Text(d.app, style: TextStyle(fontSize: compact ? 11 : 12, fontWeight: FontWeight.w700, color: AppColors.textPrimary), overflow: TextOverflow.ellipsis)),
                    const SizedBox(width: 5),
                    Text(d.version, style: const TextStyle(fontSize: 10, color: AppColors.accentCyan, fontFamily: AppFonts.mono)),
                    const SizedBox(width: 5),
                    Pill(text: d.env.toUpperCase(), color: d.env == 'main' || d.env == 'master' ? AppColors.success : AppColors.warning),
                  ]),
                  const SizedBox(height: 2),
                  Text('by ${d.actor} • ${timeAgo(d.time)} • ${d.duration}', style: const TextStyle(fontSize: 9, color: AppColors.textMuted)),
                ])),
                const Icon(Icons.chevron_right, size: 14, color: AppColors.textDim),
              ]),
            ));
            }).toList()),
    );
  }

  /// Shared empty/error frame for the log tail (spec 04-state-patterns §2).
  /// Returns null when there are lines to show (caller renders the viewer).
  Widget? _logsState({required bool compact, required List<LogLine> display, required ServerConnection? logServer}) {
    if (display.isNotEmpty) return null;
    if (_useRealServers && _savedServers.isEmpty) {
      return StateView(
        state: PanelState.empty,
        icon: Icons.dns_outlined,
        headline: 'NO SERVERS',
        body: 'Add servers in Settings for real SSH logs.',
        actionLabel: 'OPEN SETTINGS',
        onAction: () => _goTo(11),
        semanticLabel: 'No servers configured',
        compact: compact,
      );
    }
    if (_logLoading) {
      return StateView(
        state: PanelState.loading,
        loadingLabel: 'Fetching $_logSource…',
        compact: compact,
      );
    }
    if (_logError != null) {
      return StateView(
        state: PanelState.error,
        icon: Icons.error_outline,
        headline: 'LOG TAIL FAILED',
        body: _logError!,
        actionLabel: 'RETRY',
        onAction: _pollRealLogs,
        semanticLabel: 'Log tail failed',
        compact: compact,
      );
    }
    if (_liveLogs.isNotEmpty) {
      // Lines exist but the level filter matched nothing.
      return StateView(
        state: PanelState.empty,
        icon: Icons.filter_list_off_outlined,
        headline: 'NO LINES MATCH',
        body: 'No $_logFilter lines in the last ${_liveLogs.length} fetched. Try ALL.',
        actionLabel: 'SHOW ALL',
        onAction: () => setState(() => _logFilter = 'ALL'),
        semanticLabel: 'No log lines match filter',
        compact: compact,
      );
    }
    return null; // demo mode with zero mock lines — keep today's (empty) viewer.
  }

  Widget _logsSegment({bool compact = false}) {
    final filtered = _logFilter=='ALL' ? _liveLogs : _liveLogs.where((l)=> l.level==_logFilter).toList();
    final display = compact ? filtered.take(6).toList() : filtered;
    ServerConnection? logServer;
    if (_savedServers.isNotEmpty) {
      logServer = _savedServers.first;
      for (final s in _savedServers) {
        if (s.id == _logServerId) { logServer = s; break; }
      }
    }
    return PitchCard(
      title: _useRealServers && logServer != null ? 'LIVE LOG TAIL • ${logServer.name}' : 'LIVE LOG TAIL',
      subtitle: _useRealServers
          ? (_logError ?? (_logLoading ? 'fetching ${_logSource}…' : '${_liveLogs.length} lines via SSH (${_logSource})'))
          : 'demo stream — add servers for real SSH logs',
      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
        if (_useRealServers && !compact) ...[
          DropdownButton<String>(
            value: _logSource,
            dropdownColor: AppColors.surface1,
            style: const TextStyle(fontSize: 10, color: AppColors.textSecondary),
            underline: const SizedBox(),
            items: const [
              DropdownMenuItem(value: 'journal', child: Text('journal')),
              DropdownMenuItem(value: 'syslog', child: Text('syslog')),
              DropdownMenuItem(value: 'docker', child: Text('docker')),
            ],
            onChanged: (v) {
              if (v == null) return;
              setState(() => _logSource = v);
              _pollRealLogs();
            },
          ),
          if (_savedServers.length > 1)
            DropdownButton<String?>(
              value: _logServerId,
              dropdownColor: AppColors.surface1,
              style: const TextStyle(fontSize: 10, color: AppColors.textSecondary),
              underline: const SizedBox(),
              hint: Text(logServer?.name ?? 'server', style: const TextStyle(fontSize: 10, color: AppColors.textSecondary)),
              items: [
                const DropdownMenuItem<String?>(value: null, child: Text('first server')),
                ..._savedServers.map((s) => DropdownMenuItem<String?>(value: s.id, child: Text(s.name))),
              ],
              onChanged: (v) {
                setState(() => _logServerId = v);
                _pollRealLogs();
              },
            ),
          TextButton.icon(
            onPressed: _logLoading ? null : _pollRealLogs,
            icon: _logLoading
                ? const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.accentCyan))
                : const Icon(Icons.refresh, size: 11, color: AppColors.accentCyan),
            label: const Text('REFRESH', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: AppColors.accentCyan)),
            style: TextButton.styleFrom(
              minimumSize: const Size(48, 32),
              tapTargetSize: MaterialTapTargetSize.padded,
              padding: const EdgeInsets.symmetric(horizontal: 6),
            ),
          ),
          const SizedBox(width: 8),
        ],
        if (compact) InkWell(onTap: () => _goTo(8), child: const Text('EXPAND →', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: AppColors.accentCyan))),
      ]),
      child: _logsState(compact: compact, display: display, logServer: logServer) ??
          Container(
            height: compact ? 160 : 280,
        decoration: BoxDecoration(color: const Color(0xFF050505), borderRadius: BorderRadius.circular(10), border: Border.all(color: AppColors.border)),
        child: Column(children: [
          Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5), decoration: const BoxDecoration(color: AppColors.surface1, borderRadius: BorderRadius.vertical(top: Radius.circular(10))), child: const Row(children: [Icon(Icons.circle, size: 7, color: AppColors.success), SizedBox(width: 6), Text('● LIVE', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w800, color: AppColors.success))])),
          Expanded(child: ListView.builder(padding: const EdgeInsets.all(7), itemCount: display.length, itemBuilder: (_, i) {
            final l = display[i];
            Color lvlColor = l.level=='ERROR' ? AppColors.critical : l.level=='WARN' ? AppColors.warning : AppColors.success;
            return Padding(padding: const EdgeInsets.only(bottom: 2), child: Row(children: [
              Container(padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1), decoration: BoxDecoration(color: lvlColor.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(3)), child: Text(l.level, style: TextStyle(fontSize: 8, fontWeight: FontWeight.w800, color: lvlColor))),
              const SizedBox(width: 5),
              Expanded(child: Text(l.message, style: const TextStyle(fontSize: 9, color: Color(0xFFE4E4E7), fontFamily: AppFonts.mono), maxLines: 1, overflow: TextOverflow.ellipsis)),
            ]));
          })),
        ]),
      ),
    );
  }

  Widget _metricsSegment({bool compact = false}) {
    // Real latency chart: merge per-host histories (agent poll round-trip ms).
    List<FlSpot> spots = const [FlSpot(0,35),FlSpot(1,42),FlSpot(2,38),FlSpot(3,55),FlSpot(4,48)];
    String p95label = '48ms';
    if (_useRealServers) {
      final allLat = _latHistory.values.expand((e) => e).toList();
      final p = MetricsHistory.p95(allLat);
      p95label = MetricsHistory.formatMs(p);
      final series = allLat.isEmpty ? <double>[] : allLat.take(40).toList();
      if (series.isNotEmpty) {
        final maxV = series.reduce((a, b) => a > b ? a : b);
        final scale = maxV <= 0 ? 1.0 : maxV;
        spots = [for (var i = 0; i < series.length; i++) FlSpot(i.toDouble(), (series[i] / scale * 90).clamp(2, 100))];
      } else {
        spots = const [FlSpot(0, 4), FlSpot(1, 4)];
      }
    }
    return PitchCard(
      title: _useRealServers ? 'METRICS • LIVE' : 'METRICS',
      subtitle: _useRealServers ? 'agent round-trip latency (SSH poll)' : null,
      trailing: compact ? InkWell(onTap: () => _goTo(9), child: const Text('VIEW ALL →', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: AppColors.accentCyan))) : null,
      child: Column(children: [
        SizedBox(
          height: compact ? 110 : 160,
          child: LineChart(LineChartData(
            gridData: FlGridData(show: true, drawVerticalLine: false, horizontalInterval: 20, getDrawingHorizontalLine: (v)=> FlLine(color: AppColors.border, strokeWidth: 0.6)),
            titlesData: const FlTitlesData(leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)), bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)), topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)), rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false))),
            borderData: FlBorderData(show: true, border: const Border(bottom: BorderSide(color: AppColors.border), left: BorderSide(color: AppColors.border))),
            lineBarsData: [
              LineChartBarData(spots: spots, isCurved: true, color: AppColors.accentCyan, barWidth: 1.8, dotData: const FlDotData(show: false), belowBarData: BarAreaData(show: true, color: AppColors.accentCyan.withValues(alpha: 0.08))),
            ],
          )),
        ),
        const SizedBox(height: 8),
        Row(children: [
          _metricKpi('Uptime', '99.92%', AppColors.success, compact: compact),
          const SizedBox(width: 6),
          _metricKpi('p95', p95label, AppColors.accentCyan, compact: compact),
          const SizedBox(width: 6),
          _metricKpi('Errors', '0.31%', AppColors.warning, compact: compact),
          const SizedBox(width: 6),
          _metricKpi('Req/min', '6.2k', AppColors.textPrimary, compact: compact),
        ]),
      ]),
    );
  }

  Widget _metricKpi(String label, String value, Color c, {bool compact=false}) => Expanded(child: Container(
    padding: EdgeInsets.all(compact ? 6 : 8),
    decoration: BoxDecoration(color: AppColors.surface1, borderRadius: BorderRadius.circular(8), border: Border.all(color: AppColors.borderLight)),
    child: Column(children: [Text(value, style: TextStyle(fontSize: compact ? 11 : 13, fontWeight: FontWeight.w800, color: c)), Text(label, style: TextStyle(fontSize: compact ? 8 : 9, color: AppColors.textMuted))]),
  ));

  Widget _securitySegment({bool compact = false}) {
    final display = compact ? mockSecurity.take(3).toList() : mockSecurity;
    return PitchCard(
      title: 'SECURITY',
      trailing: compact ? InkWell(onTap: () => _goTo(10), child: const Text('VIEW ALL →', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: AppColors.accentCyan))) : null,
      child: Column(children: display.map((s) => Container(
        margin: EdgeInsets.only(bottom: compact ? 6 : 8), padding: EdgeInsets.all(compact ? 8 : 10),
        decoration: BoxDecoration(color: AppColors.surface1, borderRadius: BorderRadius.circular(8), border: Border.all(color: s.severity=='critical' ? AppColors.critical.withValues(alpha: 0.25) : AppColors.borderLight)),
        child: Row(children: [
          Container(width: compact ? 22 : 28, height: compact ? 22 : 28, decoration: BoxDecoration(color: severityColor(s.severity).withValues(alpha: 0.12), borderRadius: BorderRadius.circular(6)), child: Icon(Icons.shield_outlined, size: compact ? 11 : 14, color: severityColor(s.severity))),
          const SizedBox(width: 8),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(s.title, style: TextStyle(fontSize: compact ? 10 : 11, fontWeight: FontWeight.w600, color: AppColors.textPrimary), maxLines: 1, overflow: TextOverflow.ellipsis),
            Row(children: [Pill(text: s.severity.toUpperCase(), color: severityColor(s.severity)), const SizedBox(width: 5), Text(s.category, style: const TextStyle(fontSize: 9, color: AppColors.textMuted))]),
          ])),
        ]),
      )).toList()),
    );
  }

  /// Re-send the most recent user message (chat error-bubble RETRY affordance).
  void _retryChat() {
    if (_aiTyping) return;
    for (var i = _chatMessages.length - 1; i >= 0; i--) {
      if (_chatMessages[i]['role'] == 'user') {
        _chatController.text = _chatMessages[i]['text'] ?? '';
        _sendChat();
        return;
      }
    }
  }

  Widget _buildChatDrawer() {
    return Drawer(
      backgroundColor: const Color(0xFF0A0A0A), width: 380,
      child: SafeArea(child: Column(children: [
        Container(padding: const EdgeInsets.all(14), decoration: const BoxDecoration(color: AppColors.surface1, border: Border(bottom: BorderSide(color: AppColors.border))), child: Row(children: [Container(width: 36, height: 36, decoration: BoxDecoration(color: AppColors.accentCyan, borderRadius: BorderRadius.circular(8)), child: const Icon(Icons.smart_toy, size: 18, color: Colors.black)), const SizedBox(width: 10), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [const Text('AI Assistant', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textPrimary)), Text(_aiConfigured ? '$_aiModelName • control center aware' : 'No provider configured', style: const TextStyle(fontSize: 10, color: AppColors.textMuted), maxLines: 1, overflow: TextOverflow.ellipsis)])), Builder(builder: (drawerCtx) => IconButton(tooltip: 'Audit trail', onPressed: () { Navigator.pop(drawerCtx); Navigator.push(context, MaterialPageRoute(builder: (_) => const AuditScreen())); }, icon: Container(padding: const EdgeInsets.all(6), decoration: BoxDecoration(color: AppColors.surface2, borderRadius: BorderRadius.circular(8), border: Border.all(color: AppColors.border)), child: const Icon(Icons.history, size: 15, color: AppColors.textSecondary))))])),
        if (!_aiConfigured)
          Expanded(
            child: Builder(
              builder: (drawerCtx) => Center(
                child: SingleChildScrollView(
                  child: StateView(
                    state: PanelState.empty,
                    icon: Icons.smart_toy_outlined,
                    headline: 'NO AI PROVIDER',
                    body: 'Configure a provider to make the assistant control-center aware.',
                    actionLabel: 'CONFIGURE',
                    onAction: () {
                      Navigator.pop(drawerCtx); // close drawer first
                      _goTo(11); // Settings tab (reloads AI config on return)
                    },
                    semanticLabel: 'No AI provider configured',
                  ),
                ),
              ),
            ),
          )
        else ...[
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: const BoxDecoration(color: AppColors.surface1, border: Border(bottom: BorderSide(color: AppColors.border))),
          child: Row(children: [
            Icon(_aiWriteEnabled ? Icons.edit_note : Icons.visibility_outlined, size: 13, color: _aiWriteEnabled ? AppColors.warning : AppColors.textMuted),
            const SizedBox(width: 7),
            const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Write permission', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
              Text('Allow restart, SSH commands, reruns, new issues (each asks first)', style: TextStyle(fontSize: 9, color: AppColors.textMuted)),
            ])),
            Switch(
              value: _aiWriteEnabled,
              onChanged: (v) async {
                final prefs = await SharedPreferences.getInstance();
                await prefs.setBool('ai_write_enabled', v);
                if (!mounted) return;
                setState(() => _aiWriteEnabled = v);
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  backgroundColor: AppColors.surface1,
                  content: Text(v ? 'Write tools ON — every write still asks for approval' : 'Write tools OFF — assistant is read-only',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: v ? AppColors.warning : AppColors.textSecondary)),
                  duration: const Duration(seconds: 2),
                ));
              },
              activeTrackColor: AppColors.warning,
              thumbColor: WidgetStateProperty.all(Colors.black),
            ),
          ]),
        ),
        Expanded(child: ListView.builder(controller: _chatScroll, padding: const EdgeInsets.all(12), itemCount: _chatMessages.length + (_aiTyping ? 1 : 0), itemBuilder: (_, i) {
          if (_aiTyping && i == _chatMessages.length) {
            return Align(alignment: Alignment.centerLeft, child: Container(margin: const EdgeInsets.only(bottom: 8), padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10), decoration: BoxDecoration(color: AppColors.surface1, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.border)), child: Row(mainAxisSize: MainAxisSize.min, children: [const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.accentCyan)), const SizedBox(width: 8), Text('$_aiModelName is thinking…', style: const TextStyle(fontSize: 11, color: AppColors.textMuted))])));
          }
          final m = _chatMessages[i]; final isUser = m['role']=='user';
          final isStatus = !isUser && m['text']!.startsWith('_') && m['text']!.endsWith('_');
          // Spec 04-state-patterns §2: request failures surface inline + RETRY chip.
          final isError = !isUser && !isStatus && (m['text'] ?? '').startsWith('AI error:');
          return Column(
            crossAxisAlignment: isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Align(
                alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
                child: Container(
                  margin: EdgeInsets.only(bottom: isError ? 2 : 8),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                  constraints: const BoxConstraints(maxWidth: 300),
                  decoration: BoxDecoration(
                    color: isUser ? AppColors.accentCyan : AppColors.surface1,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: isUser ? AppColors.accentCyan : AppColors.border),
                  ),
                  child: isUser || isStatus
                      ? SelectableText(m['text']!,
                          style: TextStyle(fontSize: 12, height: 1.35, fontStyle: isStatus ? FontStyle.italic : FontStyle.normal, color: isUser ? Colors.black : AppColors.textMuted))
                      : MarkdownBody(
                          data: m['text']!,
                          selectable: true,
                          shrinkWrap: true,
                          fitContent: false,
                          styleSheet: _chatMarkdownStyle(),
                          onTapLink: (text, href, title) {},
                        ),
                ),
              ),
              if (isError)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Semantics(
                    label: 'AI request failed, retry',
                    child: TextButton.icon(
                      onPressed: _retryChat,
                      icon: const Icon(Icons.refresh, size: 12, color: AppColors.accentCyan),
                      label: const Text('RETRY', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: AppColors.accentCyan)),
                      style: TextButton.styleFrom(
                        minimumSize: const Size(48, 32),
                        tapTargetSize: MaterialTapTargetSize.padded,
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                      ),
                    ),
                  ),
                ),
            ],
          );
        })),
        Container(padding: const EdgeInsets.all(10), decoration: const BoxDecoration(color: AppColors.surface1, border: Border(top: BorderSide(color: AppColors.border))), child: Row(children: [
          Expanded(child: TextField(controller: _chatController, onSubmitted: (_)=> _sendChat(), style: const TextStyle(fontSize: 13, color: AppColors.textPrimary), decoration: InputDecoration(hintText: 'Ask about servers, crons, deploys...', hintStyle: const TextStyle(fontSize: 12, color: AppColors.textMuted), filled: true, fillColor: AppColors.surface2, contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10), border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppColors.border)), enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppColors.border)), focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppColors.accentCyan))))),
          const SizedBox(width: 8),
          FilledButton(onPressed: _sendChat, style: FilledButton.styleFrom(backgroundColor: AppColors.accentCyan, foregroundColor: Colors.black, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)), padding: const EdgeInsets.all(12)), child: const Icon(Icons.send, size: 16)),
        ])),
        ], // end else (chat UI when provider configured)
      ])),
    );
  }
}
