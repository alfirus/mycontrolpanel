// SPDX-License-Identifier: MIT
/// Adaptive anomaly scoring — app-side companion (Farah — ML).
///
/// Mirrors the on-device Python scorer (`agent/anomaly_scorer.py`, served
/// by the agent's `GET /anomaly`, v6+): sensitivity tiers, the 0..100
/// score contract, and the why-this-alerted copy. Dependency-light by
/// design: `shared_preferences` for the persisted picker value, no new
/// pubspec entries, no network in this file (fetching lives on
/// [AgentService.fetchAnomaly]).
///
/// Reuse contract (PRs #116/#117/#118 — no new payload formats, no new
/// rails): the sensitivity picker persists one shared pref read by every
/// rail; [anomalyWhyCopy] builds the human reason that travels inside the
/// existing [AlertEntry.title] through the existing
/// `NotificationHook.build` funnels on mobile (WorkManager),
/// desktop (in-app timer), and the snack bar. The stale-state line (#118)
/// is untouched.
library;

import 'package:shared_preferences/shared_preferences.dart';

/// Alert-quality sensitivity. Higher = more alerts, more noise.
enum AnomalySensitivity {
  /// Rare, high-confidence alerts only (z >= 4, score >= 70).
  low,

  /// Balanced default (z >= 3, score >= 50).
  medium,

  /// Catch everything, expect noise (z >= 2, score >= 30).
  high;

  /// Short label for the Settings picker + alert copy.
  String get label => switch (this) {
        AnomalySensitivity.low => 'Low',
        AnomalySensitivity.medium => 'Medium',
        AnomalySensitivity.high => 'High',
      };

  /// Value sent as the agent `/anomaly?sensitivity=` query param.
  String get queryValue => name;

  static AnomalySensitivity parse(String? raw) => switch (raw) {
        'low' => AnomalySensitivity.low,
        'high' => AnomalySensitivity.high,
        _ => AnomalySensitivity.medium,
      };
}

/// Shared pref for the sensitivity picker. Default Medium (owner-safe:
/// quieter than High, more useful than Low). Read by every alert rail.
class AnomalyScoringPrefs {
  static const prefKey = 'anomaly_sensitivity';

  static Future<AnomalySensitivity> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return AnomalySensitivity.parse(prefs.getString(prefKey));
    } catch (_) {
      return AnomalySensitivity.medium;
    }
  }

  static Future<void> save(AnomalySensitivity sensitivity) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(prefKey, sensitivity.name);
    } catch (_) {}
  }
}

/// One scored sample from the agent's `/anomaly` endpoint (v6+).
/// Null (via [AnomalyScore.parse]) covers every non-v6 answer — unreachable,
/// pre-v6 agent, bad shape — so callers fall back to the local detectors
/// (`AnomalyBaseline`, static rules) instead of crashing the rail.
class AnomalyScore {
  final String metric;
  final double value;
  final double score;
  final String reason;
  final bool firing;
  final double z;
  final double baseline;
  final AnomalySensitivity sensitivity;

  const AnomalyScore({
    required this.metric,
    required this.value,
    required this.score,
    required this.reason,
    required this.firing,
    required this.z,
    required this.baseline,
    required this.sensitivity,
  });

  static AnomalyScore? parse(Map<String, dynamic> map) {
    try {
      final version = map['version'];
      if (version is! num || version.toInt() < 6) return null;
      final score = map['score'];
      final reason = map['reason'];
      final firing = map['firing'];
      if (score is! num || reason is! String || firing is! bool) return null;
      final value = map['value'];
      final z = map['z'];
      final baseline = map['baseline'];
      return AnomalyScore(
        metric: (map['metric'] ?? 'cpu').toString(),
        value: value is num ? value.toDouble() : 0.0,
        score: score.toDouble().clamp(0.0, 100.0).toDouble(),
        reason: reason,
        firing: firing,
        z: z is num ? z.toDouble() : 0.0,
        baseline: baseline is num ? baseline.toDouble() : 0.0,
        sensitivity:
            AnomalySensitivity.parse(map['sensitivity']?.toString()),
      );
    } catch (_) {
      return null;
    }
  }

  /// Rendered title fragment for the alert rail (already inside the
  /// `NotificationHook.build` funnel — no new payload format).
  String get alertTitle =>
      'Anomaly alert — ${anomalyWhyCopy(metric: metric, value: value, baseline: baseline, score: this)}';
}

/// Why-this-alerted copy shared by every rail.
///
/// `CPU 87% vs usual 31% at 14:00 · score 78/100 (Medium)` — the value vs
/// the baseline it deviated from, the 0..100 magnitude, and the active
/// sensitivity so the user learns the picker actually does something.
/// Pass [scoreText] instead of [score] when the magnitude is not a 0..100
/// agent score (e.g. the local MAD modified-z in [AlertPipeline]).
String anomalyWhyCopy({
  required String metric,
  required double value,
  required double baseline,
  AnomalyScore? score,
  String? scoreText,
  AnomalySensitivity? sensitivity,
  String? hourBasis,
}) {
  String pct(double v) => '${(v.clamp(0.0, 1.0) * 100).toStringAsFixed(0)}%';
  final sens = (sensitivity ?? score?.sensitivity ?? AnomalySensitivity.medium);
  final at = (hourBasis != null && hourBasis.isNotEmpty) ? ' at $hourBasis' : '';
  final magnitude = score != null
      ? 'score ${score.score.toStringAsFixed(0)}/100'
      : (scoreText ?? 'score ?');
  return '$metric ${pct(value)} vs usual ${pct(baseline)}$at · $magnitude (${sens.label})';
}

/// Privacy note (binding wording, shown under the picker): scoring is
/// fully on-device — baselines live in the agent's process memory on the
/// user's own server, computed from their own metrics. Nothing is sent
/// anywhere: no cloud, no telemetry, no new permissions.
const anomalyPrivacyNote =
    'Fully on-device: baselines live in the agent on your server, '
    'computed from your own metrics. Nothing leaves your infrastructure.';
