/// Dependency injection for the service layer. Screens and pollers take
/// their dependencies from [Services.current], which resolves to
/// [MockServices] when `--dart-define=MCP_MOCKS=true` and to the live
/// adapters otherwise.
///
/// Wiring rule: a screen's `initState`/loader calls `Services.of(context?)`
/// — here simply [Services.current] — instead of constructing
/// `AgentService()` / `GithubService(token)` inline. Adapters wrap the
/// existing concrete services so current behavior is unchanged.
library service_locator;

import '../models/alert_entry.dart';
import '../models/app_entry.dart';
import '../models/app_proc.dart';
import '../models/cron_entry.dart';
import '../models/server_connection.dart';
import 'agent_protocol.dart';
import 'agent_service.dart';
import 'github_service.dart';
import 'mock_services.dart';
import 'secure_store.dart';
import 'service_contracts.dart';
import 'ssh_key_loader.dart';

/// The full dependency set any screen or background poller may need.
class Services {
  final MetricsPoller metrics;
  final ProcStatsPoller procStats;
  final CronRepository crons;
  final AppRepository apps;
  final AlertRepository alerts;
  final KeyLoader keys;
  final SecretStore secrets;
  final GithubRepo github;

  const Services({
    required this.metrics,
    required this.procStats,
    required this.crons,
    required this.apps,
    required this.alerts,
    required this.keys,
    required this.secrets,
    required this.github,
  });

  static Services? _current;

  /// The active container. First call builds live or mock services based
  /// on [kUseMocks]; tests may inject any [Services] via [overrideCurrent].
  static Services get current => _current ??= kUseMocks
      ? MockServices()
      : LiveServices();

  /// Test/preview injection. Call with `null` to reset to auto-resolve.
  static void overrideCurrent(Services? services) {
    _current = services;
  }

  static bool get isMock => current is MockServices;
}

/// Fake container: deterministic, offline, secret-free.
class MockServices extends Services {
  MockServices()
      : super(
          metrics: const MockMetricsPoller(),
          procStats: const MockProcStatsPoller(),
          crons: const MockCronRepository(),
          apps: const MockAppRepository(),
          alerts: const MockAlertRepository(),
          keys: const MockKeyLoader(),
          secrets: _ErrorSecretStore(),
          github: const MockGithubRepository(),
        );
}

/// Placeholder that loudly fails if a mock test touches secrets: even in
/// mock mode, secret reads/writes must go through an injected
/// [MockSecretStore], never a hidden default.
class _ErrorSecretStore extends MockSecretStore {
  @override
  Future<String?> readSecret(String key) =>
      throw StateError('MockSecrets: inject MockSecretStore explicitly');
}

/// Live container: thin adapters over the existing concrete services.
/// Behavior identical to today's direct calls.
class LiveServices extends Services {
  LiveServices()
      : super(
          metrics: _AgentMetricsAdapter(),
          procStats: _AgentProcStatsAdapter(),
          crons: _AgentCronAdapter(),
          apps: _AgentAppAdapter(),
          alerts: _AgentAlertAdapter(),
          keys: _SshKeyLoaderAdapter(),
          secrets: _SecureStoreAdapter(),
          github: LiveGithubRepo(
              () => SecureStore.readSecret('github_token')),
        );
}

class _AgentMetricsAdapter implements MetricsPoller {
  final AgentService _agent = AgentService();

  @override
  Future<AgentMetrics> pollMetrics(ServerConnection server) async {
    final raw = await _agent.fetch(server.host);
    if (raw == null) {
      throw const AgentProtocolException(
          AgentErrorCode.unreachable, '/metrics unreachable');
    }
    return parseAgentMetrics(raw);
  }
}

class _AgentProcStatsAdapter implements ProcStatsPoller {
  final AgentService _agent = AgentService();

  @override
  Future<AppStats> pollProcStats(ServerConnection server) async {
    final stats = await _agent.fetchAppStats(server.host);
    if (stats == null) {
      throw const AgentProtocolException(
          AgentErrorCode.unreachable, '/procstats unreachable');
    }
    return stats;
  }
}

class _AgentCronAdapter implements CronRepository {
  final AgentService _agent = AgentService();

  @override
  Future<List<CronEntry>> fetchCrons(ServerConnection s,
          {String? keyPassphrase}) =>
      _agent.fetchCrons(s, keyPassphrase: keyPassphrase);
}

class _AgentAppAdapter implements AppRepository {
  final AgentService _agent = AgentService();

  @override
  Future<List<AppEntry>> fetchApps(ServerConnection s,
          {String? keyPassphrase}) =>
      _agent.fetchApps(s, keyPassphrase: keyPassphrase);
}

class _AgentAlertAdapter implements AlertRepository {
  final AgentService _agent = AgentService();

  @override
  Future<List<AlertEntry>> fetchAlerts(ServerConnection s,
          {String? keyPassphrase}) =>
      _agent.fetchAlerts(s, keyPassphrase: keyPassphrase);
}

class _SshKeyLoaderAdapter implements KeyLoader {
  @override
  Future<KeyLoadOutcome> load(String credential,
      {String? passphrase}) async {
    final r =
        await SshKeyLoader.load(credential, passphrase: passphrase);
    return KeyLoadOutcome(
      ok: r.keys != null,
      needsPassphrase: r.needsPassphrase,
      error: r.error ?? '',
      detected: r.detected,
    );
  }
}

class _SecureStoreAdapter implements SecretStore {
  @override
  Future<void> deleteSecret(String key) => SecureStore.deleteSecret(key);

  @override
  Future<void> deleteServerCredential(String serverId) =>
      SecureStore.deleteServerCredential(serverId);

  @override
  Future<void> migrateIfNeeded() => SecureStore.migrateIfNeeded();

  @override
  Future<String?> readSecret(String key) => SecureStore.readSecret(key);

  @override
  Future<List<ServerConnection>> readServers() =>
      SecureStore.readServers();

  @override
  Future<void> writeSecret(String key, String value) =>
      SecureStore.writeSecret(key, value);

  @override
  Future<void> writeServers(List<ServerConnection> servers) =>
      SecureStore.writeServers(servers);
}
