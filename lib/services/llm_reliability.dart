/// Inference attempt log + provider fallback chain for the AI Chatbox.
///
/// The transport layer ([AiService]) already speaks every provider; what
/// was missing is operational memory: which provider/model just failed,
/// how slow the last turns were, and where to fall back next. This file
/// owns that memory with zero new dependencies:
///
/// - [InferenceAttempt] — one completed (or failed) chat turn: provider
///   id, model, latency, success flag, estimated prompt/completion tokens.
/// - [AttemptRing] — capped (200) in-memory ring of attempts; call sites
///   persist `toJson` lists via SharedPreferences (same pattern as
///   [MetricsHistory]) so this file stays dependency-free and unit
///   testable. Only non-secret telemetry is stored (no prompts, no keys,
///   no bodies).
/// - [ProviderHealth] + [FallbackChain] — consecutive-failure cooldown
///
/// Token counts are client-side estimates (chars/4 heuristic) — good
/// enough for cost trending on the reliability dashboard, never billed
/// as exact usage. Cost math itself lives in `model_reliability.dart`.
library;

/// One chat turn, recorded after it completes or fails.
class InferenceAttempt {
  final String provider;
  final String model;
  final double latencyMs;
  final bool success;
  final String? errorKind;
  final int estPromptTokens;
  final int estCompletionTokens;
  final int atMs;

  const InferenceAttempt({
    required this.provider,
    required this.model,
    required this.latencyMs,
    required this.success,
    this.errorKind,
    this.estPromptTokens = 0,
    this.estCompletionTokens = 0,
    required this.atMs,
  });

  /// Rough client-side token estimate (chars/4). Documented heuristic —
  /// use for trend/cost estimation, not billing.
  static int estimateTokens(String text) =>
      text.isEmpty ? 0 : (text.length / 4).ceil();

  Map<String, dynamic> toJson() => {
        'p': provider,
        'm': model,
        'lat': latencyMs,
        'ok': success,
        'err': errorKind,
        'pt': estPromptTokens,
        'ct': estCompletionTokens,
        't': atMs,
      };

  static InferenceAttempt? fromJson(Map<String, dynamic> j) {
    try {
      final p = j['p'];
      final m = j['m'];
      final lat = j['lat'];
      final t = j['t'];
      if (p is! String || m is! String || lat is! num || t is! num) {
        return null;
      }
      final ok = j['ok'];
      final pt = j['pt'];
      final ct = j['ct'];
      return InferenceAttempt(
        provider: p,
        model: m,
        latencyMs: lat.toDouble(),
        success: ok is bool ? ok : true,
        errorKind: j['err'] is String ? j['err'] as String : null,
        estPromptTokens: pt is num ? pt.toInt() : 0,
        estCompletionTokens: ct is num ? ct.toInt() : 0,
        atMs: t.toInt(),
      );
    } catch (_) {
      return null;
    }
  }
}

/// Capped in-memory ring of attempts (newest last). Persist via
/// `ring.map((a) => a.toJson()).toList()` wherever the app already owns
/// SharedPreferences access; restore with [InferenceAttempt.fromJson].
class AttemptRing {
  static const int cap = 200;
  final List<InferenceAttempt> _items = [];

  void add(InferenceAttempt a) {
    _items.add(a);
    while (_items.length > cap) {
      _items.removeAt(0);
    }
  }

  List<InferenceAttempt> get items => List.unmodifiable(_items);
  int get length => _items.length;
}

/// Consecutive-failure cooldown tracker (pure, testable without storage).
class ProviderHealth {
  final int maxConsecutiveFailures;
  final Duration cooldown;

  final Map<String, int> _streak = {};
  final Map<String, int> _cooledUntilMs = {};

  ProviderHealth({
    this.maxConsecutiveFailures = 3,
    this.cooldown = const Duration(minutes: 5),
  });

  void record(String provider, bool success, int nowMs) {
    if (success) {
      _streak.remove(provider);
      return;
    }
    final n = (_streak[provider] ?? 0) + 1;
    _streak[provider] = n;
    if (n >= maxConsecutiveFailures) {
      _cooledUntilMs[provider] = nowMs + cooldown.inMilliseconds;
    }
  }

  bool inCooldown(String provider, int nowMs) =>
      (_cooledUntilMs[provider] ?? 0) > nowMs;

  int streak(String provider) => _streak[provider] ?? 0;
}

/// Pure fallback ordering: skip cooled-down providers, keep caller
/// preference order otherwise. Returns the providers to try, in order.
class FallbackChain {
  static List<String> order(
    List<String> preference,
    ProviderHealth health,
    int nowMs,
  ) {
    final healthy = <String>[];
    final cooled = <String>[];
    for (final p in preference) {
      if (health.inCooldown(p, nowMs)) {
        cooled.add(p);
      } else {
        healthy.add(p);
      }
    }
    // Cooled providers stay reachable as last resort (local-first chat
    // must never hard-fail while any endpoint is configured).
    return [...healthy, ...cooled];
  }

  /// Provider id for a fresh attempt given history: first healthy in
  /// preference order, or null when nothing is configured.
  static String? pick(
    List<String> preference,
    ProviderHealth health,
    int nowMs,
  ) {
    final ordered = order(preference, health, nowMs);
    return ordered.isEmpty ? null : ordered.first;
  }
}
