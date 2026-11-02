// SPDX-License-Identifier: MIT
/// JSONL run ledger for supervised headless ticks (TM-2, Zara owns).
///
/// Every `mycontrolpanel-check` supervised run appends exactly one record
/// to `<stateDir>/headless_runs.jsonl` — the durable half of scheduler
/// observability. `status` (PR2) reads the tail for stale-run and
/// missed-heartbeat detection; operators read it with
/// `mycontrolpanel-check ledger --tail N`.
///
/// Secrecy by construction: [buildRecord] takes explicit scalar fields
/// only — raw tick stdout is NEVER passed through — so provider output
/// can only land in the ledger via the allowlisted `status` / `exitCode` /
/// `freshTitles` / `reason` fields (all secret-free by the frozen
/// headless contract, `docs/specs/headless-cli-contract.md` §3).
/// `test/ops_ledger_test.dart` pins that no vault marker or token
/// fragment can reach the file.
///
/// Pure `dart:io` / `dart:convert` only — no Flutter, no plugins — so the
/// CLI (`bin/mycontrolpanel_check.dart`) stays runnable under `dart run`
/// and unit tests stay dependency-free.
library;

import 'dart:convert';
import 'dart:io';

/// Append-only JSONL ledger for supervised headless-tick runs.
abstract class RunLedger {
  /// Ledger file name inside the per-user headless state dir.
  static const fileName = 'headless_runs.jsonl';

  /// Ledger record schema version (bump + migrate readers if extended).
  static const recordVersion = 1;

  /// Max fresh titles retained per record (payload parity: titles only).
  static const maxFreshTitles = 5;

  static File ledgerFile(Directory dir) => File(
      '${dir.path}${Platform.pathSeparator}$fileName');

  /// Build one ledger record from allowlisted tick fields.
  ///
  /// - [provider] is a display label (basename, never a full path — full
  ///   install paths embed the OS username).
  /// - [freshTitles] are user-visible alert titles (contract §3: titles
  ///   only, never credentials/markers); truncated to [maxFreshTitles].
  /// - [reason] is the tick's skip/error reason verbatim (contract §3:
  ///   present only on skipped/error ticks, secret-free by contract).
  static Map<String, dynamic> buildRecord({
    required int atMs,
    required String provider,
    required int exitCode,
    required String status,
    required int durationMs,
    List<String> freshTitles = const [],
    String? reason,
  }) {
    final record = <String, dynamic>{
      'v': recordVersion,
      'atMs': atMs,
      'provider': provider,
      'exitCode': exitCode,
      'status': status,
      'durationMs': durationMs,
      'freshCount': freshTitles.length,
      'freshTitles': freshTitles.take(maxFreshTitles).toList(),
      if (reason != null && reason.isNotEmpty) 'reason': reason,
    };
    return record;
  }

  /// Append [record] as one JSON line (best-effort, never throws — a
  /// supervised tick that ran must not fail on bookkeeping).
  ///
  /// Returns true when the record landed on disk.
  static bool append(File file, Map<String, dynamic> record) {
    try {
      file.parent.createSync(recursive: true);
      final line = '${jsonEncode(record)}\n';
      if (!file.existsSync()) {
        file.writeAsStringSync(line);
        _restrict(file);
      } else {
        file.writeAsStringSync(line, mode: FileMode.append);
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Read the last [limit] records (newest last). Corrupt lines are
  /// skipped; a missing/unreadable file yields `[]`. Never throws.
  static List<Map<String, dynamic>> tail(File file, {int limit = 20}) {
    try {
      if (!file.existsSync()) return const [];
      final lines = file.readAsLinesSync();
      final out = <Map<String, dynamic>>[];
      for (final line in lines) {
        if (line.trim().isEmpty) continue;
        try {
          final decoded = jsonDecode(line);
          if (decoded is Map<String, dynamic>) out.add(decoded);
        } catch (_) {
          continue; // one corrupt line never sinks the ledger read
        }
      }
      if (out.length <= limit) return out;
      return out.sublist(out.length - limit);
    } catch (_) {
      return const [];
    }
  }

  /// Newest record, or null when the ledger is empty/unreadable.
  static Map<String, dynamic>? latest(File file) {
    final records = tail(file, limit: 1);
    return records.isEmpty ? null : records.first;
  }

  /// Best-effort owner-only permissions on POSIX (no-op elsewhere /
  /// on failure — the state dir itself is already per-user per ADR-003).
  static void _restrict(File file) {
    try {
      if (!Platform.isWindows) {
        Process.runSync('chmod', ['0600', file.path]);
      }
    } catch (_) {}
  }
}
