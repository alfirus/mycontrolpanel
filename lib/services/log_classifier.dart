/// Log failure classifier — lightweight model flagging errors, brute-force
/// SSH attempts, and kernel issues (Log Tail + Security Watch).
///
/// Dependency-light by design: no imports at all (pure pattern + scoring
/// logic), no new pubspec entries. Works on the `LogLine.message` strings
/// already produced by [LogTailService.parse].
///
/// [LogClassifier.classify] scores one line against ordered rule groups and
/// returns the best [LogFinding] with a 0..1 confidence:
/// - `authBruteForce` — repeated sshd failures / invalid users / disconnect
///   storms (Security Watch input).
/// - `diskError` — I/O errors, no space left, read-only remounts.
/// - `kernelIssue` — OOM kills, panics, oopses, segfaults, hung tasks.
/// - `appError` — generic errors/exceptions/fatals and failing services.
/// - `benign` — routine startup/reload/OK lines (explicit negative class
///   so the eval can assert non-alerting lines stay quiet).
///
/// [classifyBatch] aggregates a tail into per-category counts plus the top
/// findings, ready for the Alerts engine or a Security Watch badge.
library;

/// Category assigned to one log line.
enum LogCategory { authBruteForce, diskError, kernelIssue, appError, benign }

/// One classified line.
class LogFinding {
  final LogCategory category;
  final double confidence;
  final String signal;
  final String line;

  const LogFinding({
    required this.category,
    required this.confidence,
    required this.signal,
    required this.line,
  });

  bool get isAlertable => category != LogCategory.benign;
}

/// Batch summary over a log tail.
class LogBatchReport {
  final Map<LogCategory, int> counts;
  final List<LogFinding> topFindings;

  const LogBatchReport(this.counts, this.topFindings);

  int count(LogCategory c) => counts[c] ?? 0;
  bool get hasAlertable => topFindings.any((f) => f.isAlertable);
}

class _Rule {
  final LogCategory category;
  final RegExp pattern;
  final double confidence;
  final String signal;

  const _Rule(this.category, this.pattern, this.confidence, this.signal);
}

/// Deterministic rule-model classifier. Rules are ordered by specificity:
/// first match wins, so high-signal security/kernel patterns outrank the
/// generic error fallback.
class LogClassifier {
  static final List<_Rule> _rules = [
    _Rule(
      LogCategory.authBruteForce,
      RegExp(r'failed\s+password|authentication\s+failure|invalid\s+user|'
          r'connection\s+closed\s+by\s+authenticating\s+user|'
          r'received\s+disconnect.*too\s+many|'
          r'maximum\s+authentication\s+attempts|'
          r'brute\s*force|sshd.*:.*(?:denied|refused)',
          caseSensitive: false),
      0.92,
      'ssh-auth-failure',
    ),
    _Rule(
      LogCategory.kernelIssue,
      RegExp(r'out\s+of\s+memory|killed\s+process|kernel\s+panic|'
          r'kernel\s+oops|bug:\s+unable\s+to\s+handle|segfault|'
          r'segmentation\s+fault|hung\s+task\s+timeout|'
          r'oom-?killer|general\s+protection\s+fault',
          caseSensitive: false),
      0.90,
      'kernel-fault',
    ),
    _Rule(
      LogCategory.diskError,
      RegExp(r'no\s+space\s+left|read-?only\s+file\s+system|'
          r'i/o\s+error|input/output\s+error|disk\s+(?:full|error)|'
          r'failed\s+to\s+write|ext4.*error|'
          r'device-mapper.*failed',
          caseSensitive: false),
      0.88,
      'disk-io',
    ),
    _Rule(
      LogCategory.appError,
      RegExp(r'\berror\b|\bfatal\b|\bexception\b|\bfailed\b|'
          r'connection\s+refused|timed?\s*out|'
          r'service.*entered\s+failed\s+state|unit.*failed',
          caseSensitive: false),
      0.70,
      'app-error',
    ),
    _Rule(
      LogCategory.benign,
      RegExp(r'started|listening\s+on|reload(?:ed|ing)?|deployment|'
          r'\bok\b|success(?:ful|fully)?|active\s+\(running\)|'
          r'systemd.*reached|session\s+(?:opened|closed)',
          caseSensitive: false),
      0.60,
      'routine',
    ),
  ];

  /// Classify one raw log line. Never throws; empty/odd input is benign.
  static LogFinding classify(String line) {
    final t = line.length > 300 ? line.substring(0, 300) : line;
    for (final r in _rules) {
      if (r.pattern.hasMatch(t)) {
        return LogFinding(
          category: r.category,
          confidence: r.confidence,
          signal: r.signal,
          line: t,
        );
      }
    }
    return LogFinding(
      category: LogCategory.benign,
      confidence: 0.40,
      signal: 'unmatched',
      line: t,
    );
  }

  /// Classify a tail; keep the [topK] alertable findings by confidence.
  static LogBatchReport classifyBatch(Iterable<String> lines, {int topK = 5}) {
    final counts = <LogCategory, int>{};
    final alertable = <LogFinding>[];
    for (final line in lines) {
      final f = classify(line);
      counts[f.category] = (counts[f.category] ?? 0) + 1;
      if (f.isAlertable) alertable.add(f);
    }
    alertable.sort((a, b) => b.confidence.compareTo(a.confidence));
    return LogBatchReport(counts, alertable.take(topK).toList());
  }
}
