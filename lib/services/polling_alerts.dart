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
