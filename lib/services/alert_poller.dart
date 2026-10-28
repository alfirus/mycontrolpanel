/// Background alert polling job (no new plugins).
///
/// Owns the *schedule + transport + dedup* half of alert polling so the
/// control center (and a future workmanager background worker) share one
/// implementation:
///
/// 1. **Transport** — [pollHostAlerts] hits the cheap agent HTTP endpoints
///    first (`/health` liveness, then `/metrics` + `/sysstats` on :9108),
///    evaluates them with [AlertRules] (disk ≥80/90%, load vs nproc), and
///    unions the result with the full SSH sweep ([AgentService.fetchAlerts]
///    — failed units, brute force, kernel, reboots) that HTTP cannot see.
///    Either leg may fail independently; the union keeps whatever answered.
/// 2. **Schedule** — [AlertPollJob] wraps one host: each [tick] runs a
///    fetch, diffs firing alerts against the last-seen set ([AlertWatch]),
///    and backs off with [PollPolicy] on consecutive transport failures
///    (5m → 10m → … → 1h). [start]/[stop] drive it on a [Timer] while the
///    app is open (desktop + foreground mobile).
/// 3. **Notify** — fresh titles are fanned out through [NotificationHook]
///    payloads with a per-title resend cooldown so a flapping check does
///    not spam the OS notification rail ([AlertNotifications], Nadia's
///    hooks: `showFresh` accepts the same title list).
///
/// Upgrade path: a workmanager background task only needs to own one
/// [AlertPollJob] per host and call [tick] — policy, diff and cooldown
/// state already live here, not in the widget layer.

import 'dart:async';

import '../models/alert_entry.dart';
import '../models/mock_data.dart' show DeployItem;
import '../models/server_connection.dart';
import 'agent_service.dart';
import 'alert_pipeline.dart';
import 'alert_rules.dart';
import 'alert_watch.dart';
import 'polling_alerts.dart';

/// Which legs answered on one [pollHostAlerts] call.
enum AlertTransport {
  /// Agent HTTP answered; SSH sweep skipped or unavailable.
  agent,

  /// Agent HTTP failed; SSH sweep answered.
  ssh,

  /// Both legs answered (union).
  both,

  /// Nothing answered (caller decides: backoff + retry).
  none,
}

/// Outcome of one [AlertPollJob.tick].
class AlertPollTick {
  /// Fresh firing titles surfaced on this tick (after cooldown).
  final List<String> freshTitles;

  /// Notification payload for the hooks (`{title, body}`), or null when
  /// there is nothing new to announce.
  final Map<String, String>? notification;

  /// Consecutive transport failures *after* this tick (0 = success).
  final int consecutiveFailures;

  /// How long the job should wait before the next tick.
  final Duration nextDelay;

  /// Which transport legs answered.
  final AlertTransport transport;

  const AlertPollTick({
    required this.freshTitles,
    required this.consecutiveFailures,
    required this.nextDelay,
    required this.transport,
    this.notification,
  });
}

/// Maps decoded `:9108` payloads to [HostSignals] for [AlertRules].
///
/// Pure: `/metrics` carries the `/` disk ratio, `/sysstats` the load +
/// CPU count. Unknown/absent fields stay unknown (rules skip them) —
/// never assumed healthy. Uptime is deliberately *not* derived from
/// `/metrics.uptime_days` (day granularity would false-fire the reboot
/// tripwire); the SSH sweep owns reboot detection.
HostSignals buildAgentHostSignals({
  Map<String, dynamic>? metrics,
  Map<String, dynamic>? sysstats,
}) {
  var diskByMount = const <String, double>{};
  final disk = (metrics?['disk'] as num?)?.toDouble();
  if (disk != null && disk.isFinite) {
    diskByMount = {'/': disk.clamp(0.0, 1.0).toDouble()};
  }
  var load1 = 0.0;
  var nproc = 0;
  final rawLoad = (sysstats?['load1'] as num?)?.toDouble();
  if (rawLoad != null && rawLoad.isFinite && rawLoad >= 0) load1 = rawLoad;
  final rawNproc = (sysstats?['nproc'] as num?)?.toInt();
  if (rawNproc != null && rawNproc > 0) nproc = rawNproc;
  return HostSignals(diskByMount: diskByMount, load1: load1, nproc: nproc);
}

/// Union of two alert lists, deduped by title (first occurrence wins).
/// Never throws — hostile entries are skipped, not fatal.
List<AlertEntry> unionAlerts(List<AlertEntry> a, List<AlertEntry> b) {
  final seen = <String>{};
  final out = <AlertEntry>[];
  for (final list in [a, b]) {
    for (final e in list) {
      try {
        if (seen.add(e.title)) out.add(e);
      } catch (_) {
        // Skip entries that fail on field access.
      }
    }
  }
  return out;
}

/// Poll one host: agent HTTP first, SSH sweep for what HTTP cannot see.
///
/// - `/health` gates the agent path (cheap, no /proc scan). Unreachable =
///   agent leg skipped, not fatal.
/// - `/metrics` + `/sysstats` feed [AlertRules] (disk, load vs nproc).
/// - [AgentService.fetchAlerts] over SSH adds failed units, brute-force,
///   kernel and reboot signals. Disabled with [sshSweep]=false (e.g. the
///   key is unavailable) — the agent leg alone still reports disk/load.
/// - Throws only when *both* legs fail (or SSH is disabled and the agent
///   leg fails), so [AlertPollJob] can count one failure per tick.
Future<List<AlertEntry>> pollHostAlerts(
  AgentService agent,
  ServerConnection s, {
  String? agentToken,
  String? keyPassphrase,
  bool sshSweep = true,
  AlertRules rules = const AlertRules(),
}) async {
  final agentAlerts = <AlertEntry>[];
  var agentOk = false;
  try {
    final health = await agent.fetchHealth(s.host,
        agentToken: agentToken, serverId: s.id);
    if (health != null) {
      final metrics = await agent.fetch(s.host,
          agentToken: agentToken, serverId: s.id);
      final sys = await agent.fetchSysstats(s.host,
          agentToken: agentToken, serverId: s.id);
      agentAlerts.addAll(rules.evaluate(
        s.id,
        s.name,
        buildAgentHostSignals(metrics: metrics, sysstats: sys),
      ));
      agentOk = true;
    }
  } catch (_) {
    agentOk = false;
  }

  var sshAlerts = const <AlertEntry>[];
  var sshOk = false;
  if (sshSweep) {
    try {
      sshAlerts = await agent.fetchAlerts(s, keyPassphrase: keyPassphrase);
      sshOk = true;
    } catch (_) {
      sshOk = false;
    }
  }

  if (!agentOk && !sshOk) {
    throw Exception('alert poll failed (agent :9108 + SSH both down)');
  }
  return unionAlerts(agentAlerts, sshAlerts);
}

/// Per-host periodic alert poll with backoff, diffing and notify cooldown.
///
/// One job per host; [tick] runs a single poll, [start] loops it on a
/// [Timer] (foreground/desktop). State is in-memory — recreating the job
/// just re-warms the seen-set (same contract as [AlertPipeline]).
class AlertPollJob {
  final String serverId;
  final String serverName;
  final PollPolicy policy;

  /// Minimum gap before the same title re-notifies.
  final Duration notifyCooldown;

  /// Consecutive transport failures (drives [PollPolicy]).
  int consecutiveFailures = 0;

  /// Last tick outcome (null before the first tick).
  AlertPollTick? lastTick;

  Set<String> _seen = {};
  final Map<String, int> _lastSentMs = {};
  Timer? _timer;

  AlertPollJob({
    required this.serverId,
    required this.serverName,
    this.policy = const PollPolicy(),
    this.notifyCooldown = const Duration(hours: 6),
  });

  bool get running => _timer?.isActive ?? false;

  /// Run one poll. [fetch] is the transport (see [pollHostAlerts]);
  /// inject a fake in tests. [onNotify] receives the hook payload.
  /// Never throws — transport errors become backoff state.
  Future<AlertPollTick> tick(
    Future<List<AlertEntry>> Function() fetch, {
    PipelineNotify? onNotify,
    DateTime? now,
  }) async {
    final at = now ?? DateTime.now();
    final atMs = at.millisecondsSinceEpoch;
    List<AlertEntry> alerts;
    AlertTransport transport = AlertTransport.none;
    try {
      alerts = await fetch();
      consecutiveFailures = 0;
      transport = AlertTransport.both;
    } catch (_) {
      consecutiveFailures++;
      final delay = policy.nextDelay(consecutiveFailures);
      lastTick = AlertPollTick(
        freshTitles: const [],
        consecutiveFailures: consecutiveFailures,
        nextDelay: delay,
        transport: AlertTransport.none,
      );
      return lastTick!;
    }

    final keys = AlertWatch.currentKeys(alerts, const <DeployItem>[]);
    final fresh = AlertWatch.freshTitles(keys, _seen, alerts, const <DeployItem>[]);
    _seen = keys;

    // Per-title cooldown: a flapping check notifies at most once per window.
    final cooled = fresh.where((t) {
      final last = _lastSentMs[t];
      if (last != null && atMs - last < notifyCooldown.inMilliseconds) {
        return false;
      }
      _lastSentMs[t] = atMs;
      return true;
    }).toList();

    Map<String, String>? payload;
    if (cooled.isNotEmpty) {
      payload = NotificationHook.build('New alerts • $serverName', cooled);
      try {
        onNotify?.call(payload['title']!, payload['body']!);
      } catch (_) {
        // Notification hooks are best-effort; the tick still counts.
      }
    }

    final delay = policy.nextDelay(consecutiveFailures);
    lastTick = AlertPollTick(
      freshTitles: cooled,
      notification: payload,
      consecutiveFailures: consecutiveFailures,
      nextDelay: delay,
      transport: transport,
    );
    return lastTick!;
  }

  /// Loop [tick] on a [Timer] until [stop]. Re-entrancy guarded by the
  /// timer itself (a slow fetch delays, never overlaps, the next tick).
  void start(
    Future<List<AlertEntry>> Function() fetch, {
    PipelineNotify? onNotify,
  }) {
    stop();
    Future<void> loop() async {
      if (_timer == null) return;
      final t = await tick(fetch, onNotify: onNotify);
      _timer = Timer(t.nextDelay, loop);
    }

    _timer = Timer(policy.nextDelay(0), loop);
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }
}
