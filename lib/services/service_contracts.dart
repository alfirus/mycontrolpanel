/// Service contracts — interfaces + dependency injection for the
/// MyControlPanel service layer.
///
/// Goal: screens depend on these abstractions (via [Services]), never on
/// concrete `AgentService` / `GithubService` / SSH code directly. That split
/// lets QA and previews run the whole app against [MockServices] behind the
/// `MCP_MOCKS` feature flag, with zero network and zero secrets.
///
/// Migration is incremental: existing services stay untouched; new and
/// refactored call sites take their dependency from [Services.current].
/// See docs/specs/service-layer.md.
library service_contracts;

import '../models/alert_entry.dart';
import '../models/app_entry.dart';
import '../models/app_proc.dart';
import '../models/cron_entry.dart';
import '../models/server_connection.dart';
import 'agent_protocol.dart';

/// Compile-time feature flag. Run/preview with fakes:
///   flutter run --dart-define=MCP_MOCKS=true
const bool kUseMocks = bool.fromEnvironment('MCP_MOCKS', defaultValue: false);

/// Polls the metrics agent (/metrics) for one host.
abstract class MetricsPoller {
  Future<AgentMetrics> pollMetrics(ServerConnection server);
}

/// Polls the metrics agent (/procstats) for one host.
abstract class ProcStatsPoller {
  Future<AppStats> pollProcStats(ServerConnection server);
}

/// Cronjob discovery + edits over SSH.
abstract class CronRepository {
  Future<List<CronEntry>> fetchCrons(ServerConnection s,
      {String? keyPassphrase});
}

/// Running-apps discovery (systemd / Docker / listening ports).
abstract class AppRepository {
  Future<List<AppEntry>> fetchApps(ServerConnection s,
      {String? keyPassphrase});
}

/// Alert harvesting (failed units, disk, brute force, load, kernel, reboots).
abstract class AlertRepository {
  Future<List<AlertEntry>> fetchAlerts(ServerConnection s,
      {String? keyPassphrase});
}

/// Resolves a saved credential (file path or pasted PEM) into key pairs.
/// Error strings only — key material never leaves the implementation.
abstract class KeyLoader {
  Future<KeyLoadOutcome> load(String credential, {String? passphrase});
}

/// Non-secret outcome of a key load (mirrors SshKeyLoader.KeyLoadResult
/// without importing dartssh2, so mocks stay dependency-free).
class KeyLoadOutcome {
  final bool ok;
  final bool needsPassphrase;
  final String error;
  final String detected;
  const KeyLoadOutcome({
    required this.ok,
    this.needsPassphrase = false,
    this.error = '',
    this.detected = 'unknown format',
  });
}

/// Secret storage for credentials + tokens (OS keychain/keystore).
abstract class SecretStore {
  Future<String?> readSecret(String key);
  Future<void> writeSecret(String key, String value);
  Future<void> deleteSecret(String key);
  Future<List<ServerConnection>> readServers();
  Future<void> writeServers(List<ServerConnection> servers);
  Future<void> deleteServerCredential(String serverId);
  Future<void> migrateIfNeeded();
}
