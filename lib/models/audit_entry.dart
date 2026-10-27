import 'dart:convert';

/// One AI tool execution record: who approved what, when, and the outcome.
class AuditEntry {
  final String id;
  final DateTime time;
  final String tool;
  final Map<String, dynamic> args;
  final String decision; // approved, denied, blocked, auto
  final String result;
  final String provider;
  final String model;
  final int durationMs;

  const AuditEntry({
    required this.id,
    required this.time,
    required this.tool,
    required this.args,
    required this.decision,
    required this.result,
    required this.provider,
    required this.model,
    required this.durationMs,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'time': time.toIso8601String(),
        'tool': tool,
        'args': args,
        'decision': decision,
        'result': result,
        'provider': provider,
        'model': model,
        'durationMs': durationMs,
      };

  factory AuditEntry.fromJson(Map<String, dynamic> j) => AuditEntry(
        id: (j['id'] ?? '').toString(),
        time: DateTime.tryParse((j['time'] ?? '').toString()) ?? DateTime.now(),
        tool: (j['tool'] ?? '').toString(),
        args: ((j['args'] as Map?) ?? const {}).cast<String, dynamic>(),
        decision: (j['decision'] ?? '').toString(),
        result: (j['result'] ?? '').toString(),
        provider: (j['provider'] ?? '').toString(),
        model: (j['model'] ?? '').toString(),
        durationMs: (j['durationMs'] as num? ?? 0).toInt(),
      );

  static String encodeList(List<AuditEntry> list) =>
      jsonEncode(list.map((e) => e.toJson()).toList());

  static List<AuditEntry> decodeList(String s) {
    try {
      final l = jsonDecode(s) as List;
      return l.map((e) => AuditEntry.fromJson((e as Map).cast<String, dynamic>())).toList();
    } catch (_) {
      return [];
    }
  }
}
