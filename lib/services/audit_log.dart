import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import '../models/audit_entry.dart';

/// Append-only AI audit trail (capped at 200, newest first).
class AuditLog {
  static const _key = 'ai_audit_log';
  static const _cap = 200;

  static Future<void> record({
    required String tool,
    required Map<String, dynamic> args,
    required String decision, // approved | denied | blocked | auto
    required String result,
    required String provider,
    required String model,
    required int durationMs,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key);
      final list = raw == null ? <AuditEntry>[] : AuditEntry.decodeList(raw);
      list.insert(
        0,
        AuditEntry(
          id: const Uuid().v4(),
          time: DateTime.now(),
          tool: tool,
          args: Map<String, dynamic>.from(args),
          decision: decision,
          result: result.length > 500 ? '${result.substring(0, 500)}…' : result,
          provider: provider,
          model: model,
          durationMs: durationMs,
        ),
      );
      while (list.length > _cap) {
        list.removeLast();
      }
      await prefs.setString(_key, AuditEntry.encodeList(list));
    } catch (_) {}
  }

  static Future<List<AuditEntry>> read() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key);
      if (raw == null) return [];
      return AuditEntry.decodeList(raw);
    } catch (_) {
      return [];
    }
  }

  static Future<void> clear() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_key);
    } catch (_) {}
  }
}
