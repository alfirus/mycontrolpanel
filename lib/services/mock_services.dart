/// Deterministic fakes behind the MCP_MOCKS flag. No network, no secrets,
/// no plugins — safe for widget tests, UI previews, and screenshots.
library mock_services;

import '../models/alert_entry.dart';
import '../models/app_entry.dart';
import '../models/app_proc.dart';
import '../models/cron_entry.dart';
import '../models/mock_data.dart';
import '../models/server_connection.dart';
import 'agent_protocol.dart';
import 'service_contracts.dart';

class MockMetricsPoller implements MetricsPoller {
  const MockMetricsPoller();

  @override
  Future<AgentMetrics> pollMetrics(ServerConnection server) async {
    await Future<void>.delayed(const Duration(milliseconds: 50));
    return const AgentMetrics(
        cpu: 0.23, ram: 0.41, disk: 0.62, uptimeDays: 17, agentVersion: 2);
  }
}

class MockProcStatsPoller implements ProcStatsPoller {
  const MockProcStatsPoller();

  @override
  Future<AppStats> pollProcStats(ServerConnection server) async {
    await Future<void>.delayed(const Duration(milliseconds: 50));
    return AppStats(
      top: const [
        AppProc(pid: 1, name: 'systemd', cpu: 0.002, memMb: 12),
        AppProc(pid: 4242, name: 'mcp-agent', cpu: 0.001, memMb: 9),
      ],
      ports: {
        '22': const AppPortStat(
            port: '22', listening: true, established: 1),
        '9108': const AppPortStat(
            port: '9108', listening: true, established: 0),
      },
    );
  }
}

class MockCronRepository implements CronRepository {
  const MockCronRepository();

  @override
  Future<List<CronEntry>> fetchCrons(ServerConnection s,
      {String? keyPassphrase}) async {
    return [
      CronEntry(
          schedule: '0 * * * *',
          command: '/opt/mcp-agent/hourly.sh',
          source: 'crontab',
          serverId: s.id,
          serverName: s.name,
          rawLine: '0 * * * * /opt/mcp-agent/hourly.sh'),
    ];
  }
}

class MockAppRepository implements AppRepository {
  const MockAppRepository();

  @override
  Future<List<AppEntry>> fetchApps(ServerConnection s,
      {String? keyPassphrase}) async {
    return [
      AppEntry(
          name: 'mcp-agent',
          detail: 'systemd active',
          source: 'systemd',
          serverId: s.id,
          serverName: s.name),
    ];
  }
}

class MockAlertRepository implements AlertRepository {
  const MockAlertRepository();

  @override
  Future<List<AlertEntry>> fetchAlerts(ServerConnection s,
      {String? keyPassphrase}) async {
    return [
      AlertEntry(
          title: 'Mock: disk 82% on /',
          source: 'mock',
          severity: 'warning',
          serverId: s.id,
          serverName: s.name),
    ];
  }
}

class MockKeyLoader implements KeyLoader {
  const MockKeyLoader();

  @override
  Future<KeyLoadOutcome> load(String credential,
      {String? passphrase}) async {
    return const KeyLoadOutcome(
        ok: true, detected: 'mock key (MCP_MOCKS)');
  }
}

/// Deterministic GitHub data behind the MCP_MOCKS flag: one open issue,
/// one open PR, and a 3-run Actions history (success/failed/running) that
/// exercises the CI badge + rerun paths in widget tests.
class MockGithubRepository implements GithubRepo {
  const MockGithubRepository();

  static final _at = DateTime.utc(2026, 10, 27, 12);

  @override
  Future<String> validate() async => 'mock-user';

  @override
  Future<List<GithubItem>> repoIssues(String repo) async => [
        GithubItem(
          title: 'Mock: agent reconnect loop on flaky wifi',
          repo: repo,
          author: 'mock-user',
          number: 101,
          state: 'open',
          labels: const ['bug'],
          updatedAt: _at,
          comments: 2,
        ),
      ];

  @override
  Future<List<GithubItem>> repoPRs(String repo) async => [
        GithubItem(
          title: 'Mock: harden agent token auth',
          repo: repo,
          author: 'mock-user',
          number: 102,
          state: 'open',
          labels: const ['backend'],
          updatedAt: _at,
          comments: 1,
        ),
      ];

  @override
  Future<List<DeployItem>> repoRuns(String repo, {int limit = 8}) async => [
        DeployItem(
            app: 'ci', version: 'main', env: repo, actor: 'mock-user',
            time: _at, status: 'success', duration: '3m'),
        DeployItem(
            app: 'ci', version: 'feat/x', env: repo, actor: 'mock-user',
            time: _at, status: 'failed', duration: '5m', runId: 9001),
        DeployItem(
            app: 'ci', version: 'feat/y', env: repo, actor: 'mock-user',
            time: _at, status: 'running', duration: '1m', runId: 9002),
      ].take(limit).toList();

  @override
  Future<bool> rerunRun(String repo, int runId) async => true;

  @override
  Future<int> createIssue(String repo, String title,
          {String body = '', List<String> labels = const []}) async =>
      103;
}

/// In-memory secret store for tests/previews. Never touches the OS
/// keychain; dropped when the process exits.
class MockSecretStore implements SecretStore {
  final Map<String, String> _secrets = {};
  List<ServerConnection> _servers = [];

  @override
  Future<void> deleteSecret(String key) async {
    _secrets.remove(key);
  }

  @override
  Future<void> deleteServerCredential(String serverId) async {
    _secrets.remove('srv_cred_$serverId');
  }

  @override
  Future<void> migrateIfNeeded() async {}

  @override
  Future<String?> readSecret(String key) async => _secrets[key];

  @override
  Future<List<ServerConnection>> readServers() async =>
      List.of(_servers);

  @override
  Future<void> writeSecret(String key, String value) async {
    _secrets[key] = value;
  }

  @override
  Future<void> writeServers(List<ServerConnection> servers) async {
    _servers = List.of(servers);
  }
}
