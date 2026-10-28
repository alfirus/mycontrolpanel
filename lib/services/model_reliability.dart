/// Model reliability KPIs for the Metrics & Uptime screens.
///
/// Pure-Dart rollup over [InferenceAttempt] history (see
/// `llm_reliability.dart`) plus host load context. Dependency-free so it
/// is trivially unit-testable and safe to call from any screen:
///
/// - latency p50/p95, error rate, throughput (attempts/hour)
/// - estimated tokens + estimated cost (per-provider per-1k-token rates;
///   unknown providers cost 0 and are flagged via [hasUnknownPricing])
/// - capacity score 0..1 (lower is hotter): blends error rate, p95
///   latency against a 30s budget, and host load1 when supplied
/// - [reliabilityGrade] maps the score to a one-glance A..F badge
///
/// Cost rates are app-side estimates for trend display, not invoices.
/// Local providers (LM Studio / Ollama) default to zero cost.
library;

import 'llm_reliability.dart';

/// Per-1k-token USD rates used for cost trending (estimates, not bills).
class PriceTable {
  final Map<String, double> promptPer1k;
  final Map<String, double> completionPer1k;

  const PriceTable({
    this.promptPer1k = const {},
    this.completionPer1k = const {},
  });

  double promptRate(String provider) => promptPer1k[provider] ?? 0.0;
  double completionRate(String provider) => completionPer1k[provider] ?? 0.0;

  /// Sane built-in defaults; callers may override per deployment.
  /// Local providers intentionally cost 0.
  static const PriceTable defaults = PriceTable(
    promptPer1k: {
      'openai': 0.005,
      'openRouter': 0.005,
      'anthropic': 0.003,
      'gemini': 0.00125,
      'openCodeZen': 0.002,
      'openCodeGo': 0.002,
      'lmStudio': 0.0,
      'ollama': 0.0,
      'openaiCompatible': 0.0,
    },
    completionPer1k: {
      'openai': 0.015,
      'openRouter': 0.015,
      'anthropic': 0.015,
      'gemini': 0.005,
      'openCodeZen': 0.008,
      'openCodeGo': 0.008,
      'lmStudio': 0.0,
      'ollama': 0.0,
      'openaiCompatible': 0.0,
    },
  );
}

/// One-glance reliability snapshot for a provider (or the whole fleet
/// when computed over all attempts).
class ReliabilityKpis {
  final int attempts;
  final int errors;
  final double? latencyP50Ms;
  final double? latencyP95Ms;
  final double attemptsPerHour;
  final int estPromptTokens;
  final int estCompletionTokens;
  final double estCostUsd;
  final bool hasUnknownPricing;
  final double capacityScore;
  final String grade;

  const ReliabilityKpis({
    required this.attempts,
    required this.errors,
    required this.latencyP50Ms,
    required this.latencyP95Ms,
    required this.attemptsPerHour,
    required this.estPromptTokens,
    required this.estCompletionTokens,
    required this.estCostUsd,
    required this.hasUnknownPricing,
    required this.capacityScore,
    required this.grade,
  });

  double get errorRate => attempts == 0 ? 0.0 : errors / attempts;

  static const ReliabilityKpis empty = ReliabilityKpis(
    attempts: 0,
    errors: 0,
    latencyP50Ms: null,
    latencyP95Ms: null,
    attemptsPerHour: 0,
    estPromptTokens: 0,
    estCompletionTokens: 0,
    estCostUsd: 0,
    hasUnknownPricing: false,
    capacityScore: 1,
    grade: '—',
  );
}

class ModelReliability {
  /// p95 budget (ms) at which latency alone saturates the capacity score.
  static const double latencyBudgetMs = 30000;

  static double? percentile(List<double> xs, double q) {
    if (xs.isEmpty) return null;
    final sorted = List.of(xs)..sort();
    final idx = ((sorted.length * q).ceil() - 1).clamp(0, sorted.length - 1);
    return sorted[idx];
  }

  /// Roll up [attempts] (optionally pre-filtered by provider) into KPIs.
  /// [nowMs] anchors the attempts/hour window; [load1] adds host pressure
  /// (from agent /sysstats) when available.
  static ReliabilityKpis summarize(
    List<InferenceAttempt> attempts, {
    int? nowMs,
    double? load1,
    PriceTable prices = PriceTable.defaults,
    double windowHours = 24,
  }) {
    if (attempts.isEmpty) return ReliabilityKpis.empty;
    final now = nowMs ?? DateTime.now().millisecondsSinceEpoch;
    final windowStart = now - (windowHours * 3600 * 1000).round();
    final inWindow =
        attempts.where((a) => a.atMs >= windowStart).toList(growable: false);
    final basis = inWindow.isEmpty ? attempts : inWindow;

    final lats = basis.map((a) => a.latencyMs).toList();
    final errors = basis.where((a) => !a.success).length;
    var pt = 0, ct = 0, cost = 0.0, unknown = false;
    for (final a in basis) {
      pt += a.estPromptTokens;
      ct += a.estCompletionTokens;
      final pr = prices.promptRate(a.provider);
      final cr = prices.completionRate(a.provider);
      if ((a.estPromptTokens + a.estCompletionTokens) > 0 &&
          pr == 0.0 &&
          cr == 0.0 &&
          !_isLocal(a.provider)) {
        unknown = true;
      }
      cost += a.estPromptTokens / 1000 * pr + a.estCompletionTokens / 1000 * cr;
    }

    final spanMs = basis.length < 2
        ? 3600 * 1000
        : (basis.map((a) => a.atMs).reduce((x, y) => x > y ? x : y) -
                basis.map((a) => a.atMs).reduce((x, y) => x < y ? x : y))
            .clamp(60 * 1000, 7 * 24 * 3600 * 1000);
    final perHour = basis.length / (spanMs / 3600000);

    final p95 = percentile(lats, 0.95);
    final score = capacityScore(
      errorRate: basis.length == 0 ? 0 : errors / basis.length,
      p95Ms: p95,
      load1: load1,
    );
    return ReliabilityKpis(
      attempts: basis.length,
      errors: errors,
      latencyP50Ms: percentile(lats, 0.5),
      latencyP95Ms: p95,
      attemptsPerHour: perHour,
      estPromptTokens: pt,
      estCompletionTokens: ct,
      estCostUsd: cost,
      hasUnknownPricing: unknown,
      capacityScore: score,
      grade: reliabilityGrade(score),
    );
  }

  /// 0..1 headroom score (1 = comfortable). Worst-signal-wins blending so
  /// a single red dimension cannot hide behind green ones.
  static double capacityScore({
    required double errorRate,
    required double? p95Ms,
    double? load1,
  }) {
    final errW = (1 - errorRate.clamp(0, 1)) * 0.5;
    final latW = p95Ms == null
        ? 0.3
        : (1 - (p95Ms / latencyBudgetMs).clamp(0, 1)) * 0.3;
    final loadW = load1 == null ? 0.2 : (1 - (load1 / 8).clamp(0, 1)) * 0.2;
    return (errW + latW + loadW).clamp(0, 1);
  }

  static String reliabilityGrade(double score) {
    if (score >= 0.9) return 'A';
    if (score >= 0.75) return 'B';
    if (score >= 0.6) return 'C';
    if (score >= 0.4) return 'D';
    return 'F';
  }

  static bool _isLocal(String provider) {
    final p = provider.toLowerCase();
    return p.contains('lmstudio') || p.contains('ollama');
  }
}
