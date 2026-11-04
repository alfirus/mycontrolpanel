// SPDX-License-Identifier: MIT
/// Background alerting policy + SLO helpers (pure Dart, no plugins).
///
/// Complements the foreground-only helpers that already exist:
/// - `AlertWatch` diffs firing alerts / failed CI runs while the app is open.
/// - `MetricsHistory` records per-poll points (capped at 120) and computes p95.
///
/// This file answers the *policy* questions a future background worker
/// (workmanager + flutter_local_notifications, still an open next step)
/// will need, kept here so the logic is unit-tested before any plugin lands:
/// how long to wait between polls, when a metric is warn vs critical,
/// what uptime % a success series means, and what payload the notification
/// hooks receive.
///
/// It also owns the shared concurrent fan-out ([pollHostsConcurrently])
/// so every poll rail (foreground ticker, background worker, headless
/// adapter, `mcpoll` CLI) polls hosts concurrently with the same per-host
/// timeout + per-host backoff semantics instead of each rail re-solving
/// the slow-host-stalls-everyone problem.

import 'dart:async';

/// Severity of one evaluated threshold.
enum AlertSeverity { ok, warning, critical }

/// Poll scheduling with exponential backoff on consecutive failures.
///
/// Success resets the streak to the base interval; each failure doubles
/// the wait (base * 2^failures) up to [maxInterval]. Pure function of the
/// failure count — the worker stores nothing but the streak.
class PollPolicy {
  final Duration baseInterval;
  final Duration maxInterval;

  const PollPolicy({
    this.baseInterval = const Duration(minutes: 5),
    this.maxInterval = const Duration(hours: 1),
  });

  /// Next wait given [consecutiveFailures] since the last success.
  Duration nextDelay(int consecutiveFailures) {
    if (consecutiveFailures <= 0) return baseInterval;
    var seconds = baseInterval.inSeconds;
    for (var i = 0; i < consecutiveFailures; i++) {
      seconds *= 2;
      if (seconds >= maxInterval.inSeconds) {
        return maxInterval;
      }
    }
    return Duration(seconds: seconds);
  }
}

/// Threshold evaluation for 0..1 resource readings (cpu/ram/disk).
class Thresholds {
  final double warnAt;
  final double critAt;

  const Thresholds({this.warnAt = 0.85, this.critAt = 0.95})
      : assert(warnAt < critAt, 'warnAt must be below critAt');

  AlertSeverity evaluate(double value) {
    if (value >= critAt) return AlertSeverity.critical;
    if (value >= warnAt) return AlertSeverity.warning;
    return AlertSeverity.ok;
  }
}

/// SLO math over a window of poll outcomes.
class Slo {
  /// Uptime fraction 0..1 from [successes] out of [total] polls.
  /// Returns null when there is nothing to measure.
  static double? uptimePct(int successes, int total) {
    if (total <= 0) return null;
    final s = successes.clamp(0, total);
    return s / total;
  }

  /// True when uptime over the window breaches [target] (e.g. 0.99).
  /// Null input (no data) never counts as a breach.
  static bool breaches(double? uptime, double target) {
    if (uptime == null) return false;
    return uptime < target;
  }
}

/// Payload builder for notification hooks (snack bar today, push later).
///
/// Takes plain strings so hooks stay decoupled from model classes:
/// pass alert titles in, get a capped `{title, body}` map out.
class NotificationHook {
  static const maxItems = 3;

  static Map<String, String> build(
    String title,
    List<String> freshTitles,
  ) {
    if (freshTitles.isEmpty) return {'title': title, 'body': ''};
    final shown = freshTitles.take(maxItems).join('\n');
    final extra = freshTitles.length - freshTitles.take(maxItems).length;
    final body = extra > 0 ? '$shown\n…and $extra more' : shown;
    return {'title': title, 'body': body};
  }
}

/// Outcome of one host inside [pollHostsConcurrently].
class HostPollOutcome<T> {
  const HostPollOutcome({
    required this.index,
    required this.hostId,
    required this.answered,
    required this.consecutiveFailures,
    required this.nextDelay,
    this.value,
  });

  /// Position of this host in the input list (outputs sort by this, so
  /// the UI merge always sees hosts in configuration order no matter
  /// who answered first).
  final int index;

  /// Host id as passed in (matches the input [hostIds] entry).
  final String hostId;

  /// True when the host answered within [pollHostsConcurrently]'s
  /// per-host timeout. False covers fetch errors AND timeouts — one
  /// sick host never sinks the run.
  final bool answered;

  /// Consecutive-failure streak *after* this tick (0 on success, so a
  /// healthy host resets exactly like [AlertPollJob.tick] does).
  final int consecutiveFailures;

  /// [PollPolicy.nextDelay] of [consecutiveFailures] — the same backoff
  /// curve the single-host job applies, tracked per host instead of
  /// globally.
  final Duration nextDelay;

  /// The fetched value on success, null on failure/timeout.
  final T? value;
}

/// Poll every host concurrently with a per-host timeout.
///
/// Replaces the old sequential `for (host) await fetch(host)` loops: each
/// host runs [fetch] in its own future guarded by [perHostTimeout], so one
/// slow/stalled host (e.g. a hung SSH handshake) times out alone and never
/// stalls the others.
///
/// - Failures are counted per host: [previousFailures] carries the
///   consecutive-failure streak per host id (absent = 0). Success resets
///   that host to 0; failure/timeout increments it; [HostPollOutcome]
///   carries [PollPolicy.nextDelay] of the resulting streak — the same
///   backoff [AlertPollJob.tick] applies, tracked per host.
/// - Results return in input [hostIds] order (stable for UI merge),
///   regardless of completion order.
/// - Never throws: a total outage yields all-unanswered outcomes (the
///   caller decides, mirroring `pollHostAlerts`), never an exception —
///   even [hostIds] itself being hostile is swallowed to an empty list.
Future<List<HostPollOutcome<T>>> pollHostsConcurrently<T>({
  required List<String> hostIds,
  required Future<T> Function(String hostId) fetch,
  Map<String, int>? previousFailures,
  PollPolicy policy = const PollPolicy(),
  Duration perHostTimeout = const Duration(seconds: 15),
}) async {
  List<String> ids;
  try {
    ids = List<String>.of(hostIds);
  } catch (_) {
    return const [];
  }
  final prior = previousFailures ?? const <String, int>{};
  Future<HostPollOutcome<T>> one(String id, int index) async {
    try {
      final v = await fetch(id).timeout(perHostTimeout);
      return HostPollOutcome<T>(
        index: index,
        hostId: id,
        answered: true,
        consecutiveFailures: 0,
        nextDelay: policy.nextDelay(0),
        value: v,
      );
    } catch (_) {
      var streak = 1;
      try {
        streak = (prior[id] ?? 0) + 1;
      } catch (_) {
        streak = 1;
      }
      return HostPollOutcome<T>(
        index: index,
        hostId: id,
        answered: false,
        consecutiveFailures: streak,
        nextDelay: policy.nextDelay(streak),
      );
    }
  }

  List<HostPollOutcome<T>> out;
  try {
    out = await Future.wait([
      for (var i = 0; i < ids.length; i++) one(ids[i], i),
    ]);
  } catch (_) {
    // Unreachable (every leg swallows), kept so a future refactor of
    // [one] can never turn a poll tick into a crash.
    return const [];
  }
  out.sort((a, b) => a.index.compareTo(b.index));
  return out;
}
