// SPDX-License-Identifier: MIT
/// Delivery-log rotation policy (Beta.2, Nadia owns).
///
/// The alert delivery log is JSONL (one [AlertDeliveryRecord] per line,
/// plus `tick`/`mem` sample lines — see `agent_operability.dart`). This
/// file is the pure-Dart half: size caps, generation names, prune plans.
/// The `agent_check --rotate` entry-point executes the plan with
/// `dart:io`; `flutter test` pins the policy here without touching disk.
///
/// Budgets: 512 KiB per generation, 3 live generations
/// (`delivery.log`, `.1`, `.2` — ~1.5 MiB ceiling). Rotation never
/// rewrites history inside an SLO window: `agent_check --check` reads
/// ALL live generations, newest last, so a rotate between ticks cannot
/// hide a drop.
library;

/// Size + retention policy for one JSONL delivery log.
abstract class AlertLogRotation {
  /// Rotate when the live log reaches this size (512 KiB).
  static const int maxBytes = 512 * 1024;

  /// Live generations kept: `delivery.log` + this many numbered back
  /// generations (`delivery.log.1` …). Older ones are pruned.
  static const int generations = 2;

  /// Base name of the delivery log (overridable for tests).
  static const String baseName = 'delivery.log';

  /// True when [bytes] reaches the rotation threshold.
  static bool rotationDue(int bytes) => bytes >= maxBytes;

  /// Generation path: gen 0 is the live log, gen ≥1 appends `.<gen>`.
  static String generationPath(String basePath, int gen) =>
      gen <= 0 ? basePath : '$basePath.$gen';

  /// All live paths, newest first: base, .1, …, .N.
  static List<String> livePaths(String basePath) => List.generate(
        generations + 1,
        (gen) => generationPath(basePath, gen),
      );

  /// Prune plan: which numbered generations to delete given the set of
  /// generation numbers currently on disk. Never touches gen 0 (live).
  static List<int> pruneAbove(Set<int> present) =>
      present.where((g) => g > generations).toList()..sort();

  /// Parse a generation number back out of a log path. Returns null
  /// when [path] is not a generation of [basePath].
  static int? generationOf(String basePath, String path) {
    if (path == basePath) return 0;
    if (!path.startsWith('$basePath.')) return null;
    final suffix = path.substring(basePath.length + 1);
    if (suffix.isEmpty || suffix.length > 2) return null;
    final gen = int.tryParse(suffix);
    if (gen == null || gen <= 0) return null;
    return gen;
  }
}
