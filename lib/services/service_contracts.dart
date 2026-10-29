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
import '../models/mock_data.dart';
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

/// GitHub issues / PRs / Actions proxy behind the app's token.
///
/// Unmocks the CI + backlog screens: live data flows through
/// [GithubService], previews and widget tests through
/// [MockGithubRepository]. Method names mirror [GithubService] 1:1 so
/// the concrete class implements this contract with no adapter logic.
abstract class GithubRepo {
  /// Who owns the token (login). Throws on 4xx/5xx — never null.
  Future<String> validate();

  /// Open issues (PRs excluded) for `owner/repo`, newest first.
  /// [page]/[perPage] drive the screen's LOAD MORE affordance (GitHub
  /// caps pages at 100 items; the screen passes 30).
  Future<List<GithubItem>> repoIssues(String repo,
      {int page = 1, int perPage = 30});

  /// Open pull requests for `owner/repo`, newest first.
  /// [page]/[perPage] mirror [repoIssues] for the PR tab's LOAD MORE.
  Future<List<GithubItem>> repoPRs(String repo, {int page = 1, int perPage = 30});

  /// Projects v2 boards owned by the token viewer (id/title/open count).
  /// Empty when the token lacks Projects access — the screen falls back
  /// to assigned issues instead of failing.
  Future<List<Map<String, dynamic>>> projectsV2();

  /// Open items across the viewer's recent Projects v2 boards, skipping
  /// Done/Closed/Complete statuses. Throws when Projects is unreachable
  /// so the caller can use the assigned-issue fallback.
  Future<List<GithubItem>> projectTasks();

  /// "Tasks" = open issues assigned to the token owner across [repos].
  /// Falls back to recently updated issues when assignee data is empty.
  Future<List<GithubItem>> myTasks(List<String> repos);

  /// Recent Actions workflow runs for `owner/repo` as deploy items.
  Future<List<DeployItem>> repoRuns(String repo, {int limit = 8});

  /// Re-run a workflow run. True on accepted (201/204).
  Future<bool> rerunRun(String repo, int runId);

  /// Open an issue. Returns the new issue number.
  Future<int> createIssue(String repo, String title,
      {String body = '', List<String> labels = const []});
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
