import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/mock_data.dart';
import 'deployments_service.dart';
import 'polling_alerts.dart';
import 'service_contracts.dart';

/// CI/CD sync automation (no new plugins).
///
/// The Deployments timeline already renders live GitHub Actions runs +
/// GitLab pipelines ([DeploymentsService]); this service owns the *sync*
/// half for the GitHub leg: periodic per-repo polling with [PollPolicy]
/// backoff, a last-good SharedPreferences cache per repo (the timeline
/// keeps showing stale-but-real rows when the API is rate-limited or
/// offline), and failure surfacing for [AlertWatch].
///
/// Cadence contract: one [CiSyncService] per screen (it keeps the
/// per-repo failure streaks in memory); call [syncRepos] on every
/// control-center refresh. Repos inside their backoff window are skipped
/// (cache stands); everything else is fetched live and re-cached.
///
/// Upgrade path: GitLab gets the same treatment once its polling needs
/// backoff — the cache helpers here are VCS-agnostic by key.
class CiSyncResult {
  /// Merged newest-first runs, capped at the requested timeline limit.
  final List<DeployItem> runs;

  /// Failed runs, newest first — feed to the alert watcher.
  List<DeployItem> get failures => DeploymentsService.failures(runs);

  /// `owner/repo -> error` for repos that did not answer live this sync.
  final Map<String, String> errors;

  /// True when at least one repo served cache (backoff-skip or live error).
  final bool servedCache;

  /// Human note for the timeline subtitle (`''` when everything is live).
  /// e.g. `2 cached • retrying` or `offline cache`.
  final String cacheNote;

  final DateTime syncedAt;

  const CiSyncResult({
    required this.runs,
    required this.errors,
    required this.servedCache,
    required this.cacheNote,
    required this.syncedAt,
  });

  /// One-line subtitle for the Deployments timeline.
  String summary(List<DeployItem> gitlabPipes) =>
      DeploymentsService.summary(runs, gitlabPipes);
}

class CiSyncService {
  final PollPolicy policy;
  final int perRepoLimit;
  final int timelineLimit;

  final Map<String, int> _repoFailures = {};
  final Map<String, int> _lastAttemptMs = {};

  CiSyncService({
    this.policy = const PollPolicy(
      baseInterval: Duration(minutes: 5),
      maxInterval: Duration(hours: 1),
    ),
    this.perRepoLimit = 8,
    this.timelineLimit = 12,
  });

  /// Sync Actions runs for [repos]. Never throws — per-repo failures are
  /// collected in [CiSyncResult.errors] with the last-good cache standing
  /// in. Empty [repos] returns an empty result without touching prefs.
  /// Repos inside their backoff window are skipped (cache stands) unless
  /// [force] is true (manual SYNC / retry buttons bypass the cadence).
  Future<CiSyncResult> syncRepos(
    GithubRepo github,
    List<String> repos, {
    DateTime? now,
    bool force = false,
  }) async {
    final at = now ?? DateTime.now();
    final atMs = at.millisecondsSinceEpoch;
    final live = <DeployItem>[];
    final errors = <String, String>{};
    var servedCache = false;

    final seen = <String>{};
    for (final repo in repos) {
      final slug = repo.trim();
      if (slug.isEmpty || !seen.add(slug)) continue;
      final streak = _repoFailures[slug] ?? 0;
      final lastAttempt = _lastAttemptMs[slug];
      final wait = policy.nextDelay(streak);
      if (!force &&
          lastAttempt != null &&
          atMs - lastAttempt < wait.inMilliseconds) {
        // Inside the backoff window: cache stands, no network.
        final cached = await CiSyncCache.read(slug);
        live.addAll(cached);
        if (cached.isNotEmpty) servedCache = true;
        continue;
      }
      _lastAttemptMs[slug] = atMs;
      try {
        final runs =
            await github.repoRuns(slug, limit: perRepoLimit).timeout(
                  const Duration(seconds: 30),
                );
        final stamped = runs.map((d) => d.withRepo(slug)).toList();
        live.addAll(stamped);
        await CiSyncCache.save(slug, stamped);
        _repoFailures.remove(slug);
      } catch (e) {
        _repoFailures[slug] = streak + 1;
        errors[slug] =
            e.toString().replaceFirst('Exception: ', '').split('\n').first;
        final cached = await CiSyncCache.read(slug);
        live.addAll(cached);
        if (cached.isNotEmpty) servedCache = true;
      }
    }

    live.sort((a, b) => b.time.compareTo(a.time));
    final capped = live.take(timelineLimit).toList();
    final cachedCount = errors.length;
    final note = !servedCache
        ? ''
        : errors.isEmpty
            ? 'cache warming'
            : '$cachedCount cached • retrying';
    return CiSyncResult(
      runs: capped,
      errors: errors,
      servedCache: servedCache,
      cacheNote: note,
      syncedAt: at,
    );
  }
}

/// Last-good Actions runs per repo (SharedPreferences).
///
/// Same best-effort pattern as [MetricsHistory]: silent on failure, so a
/// cache fault can never break the Deployments timeline.
class CiSyncCache {
  static const _prefix = 'ci_runs_';
  static const _cap = 24;

  static String _key(String repo) =>
      '$_prefix${repo.replaceAll(RegExp(r'[^A-Za-z0-9_.\-]'), '_')}';

  static Map<String, dynamic> _toJson(DeployItem d) => {
        'app': d.app,
        'version': d.version,
        'env': d.env,
        'actor': d.actor,
        'timeMs': d.time.millisecondsSinceEpoch,
        'status': d.status,
        'duration': d.duration,
        'runId': d.runId,
        'ghRepo': d.ghRepo,
        'vcs': d.vcs,
      };

  static DeployItem? _fromJson(Map<String, dynamic> j) {
    try {
      final ms = (j['timeMs'] as num?)?.toInt();
      final status = (j['status'] ?? '').toString();
      if (ms == null || status.isEmpty) return null;
      return DeployItem(
        app: (j['app'] ?? '').toString(),
        version: (j['version'] ?? '').toString(),
        env: (j['env'] ?? '').toString(),
        actor: (j['actor'] ?? '').toString(),
        time: DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true).toLocal(),
        status: status,
        duration: (j['duration'] ?? '').toString(),
        runId: (j['runId'] as num?)?.toInt(),
        ghRepo: (j['ghRepo'] as String?),
        vcs: (j['vcs'] ?? 'github').toString(),
      );
    } catch (_) {
      return null;
    }
  }

  static Future<void> save(String repo, List<DeployItem> runs) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _key(repo),
        jsonEncode({
          'at': DateTime.now().millisecondsSinceEpoch,
          'runs': runs.take(_cap).map(_toJson).toList(),
        }),
      );
    } catch (_) {}
  }

  static Future<List<DeployItem>> read(String repo) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key(repo));
      if (raw == null) return [];
      final doc = jsonDecode(raw) as Map<String, dynamic>;
      final rows = (doc['runs'] as List?) ?? [];
      return rows
          .whereType<Map<String, dynamic>>()
          .map(_fromJson)
          .whereType<DeployItem>()
          .toList();
    } catch (_) {
      return [];
    }
  }
}
