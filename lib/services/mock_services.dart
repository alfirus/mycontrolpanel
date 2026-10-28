/// Deterministic fakes behind the MCP_MOCKS flag. No network, no secrets,
/// no plugins — safe for widget tests, UI previews, and screenshots.
library mock_services;

import '../models/alert_entry.dart';
import '../models/app_entry.dart';
import '../models/app_proc.dart';
import '../models/cron_entry.dart';
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
