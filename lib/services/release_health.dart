// SPDX-License-Identifier: MIT
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Opt-in deploy heartbeat for release-health (Aisyah, DevOps).
///
/// Crash-free sessions tell us when the app dies; they say nothing about
/// *which* releases are alive in the field. The heartbeat closes that gap:
/// at most one lightweight info event per app-install per 24 h, carrying
/// the release + environment as tags. Sentry Discover counts distinct
/// `release`s per day — that chart is the rollout census
/// (docs/observability-dashboards.md).
///
/// Fully guarded: reporting only fires when the user opted into Sentry
/// AND Sentry is armed. Never throws; failures are silent by design.
class ReleaseHealth {
  ReleaseHealth._();

  /// Prefs key for the last heartbeat timestamp (ms since epoch).
  static const lastHeartbeatKey = 'release_health_last_heartbeat_ms';

  /// At most one heartbeat per [interval] (default 24 h).
  /// Pure — unit-tested (test/release_health_test.dart).
  static bool shouldSendHeartbeat({
    required int lastSentMs,
    required int nowMs,
    Duration interval = const Duration(hours: 24),
  }) {
    if (lastSentMs <= 0) return true;
    if (nowMs <= lastSentMs) return false;
    return nowMs - lastSentMs >= interval.inMilliseconds;
  }

  /// Builds the heartbeat payload. Pure — unit-tested.
  static Map<String, String> heartbeatPayload({
    required String release,
    required String environment,
  }) {
    return {
      'release': release,
      'environment': environment,
    };
  }

  /// Sends the heartbeat when due. Opt-in gated, interval gated, never
  /// throws. Call once per app start (see `main()`).
  static Future<void> reportAppStart({
    required String release,
    required String environment,
  }) async {
    try {
      if (!Sentry.isEnabled) return;
      final prefs = await SharedPreferences.getInstance();
      final nowMs = DateTime.now().millisecondsSinceEpoch;
      final last = prefs.getInt(lastHeartbeatKey) ?? 0;
      if (!shouldSendHeartbeat(lastSentMs: last, nowMs: nowMs)) return;
      final payload = heartbeatPayload(
        release: release,
        environment: environment,
      );
      await Sentry.captureMessage(
        'MyControlPanel heartbeat',
        level: SentryLevel.info,
        withScope: (scope) {
          payload.forEach(scope.setTag);
        },
      );
      await prefs.setInt(lastHeartbeatKey, nowMs);
    } catch (_) {
      // Heartbeats must never break startup.
    }
  }
}
