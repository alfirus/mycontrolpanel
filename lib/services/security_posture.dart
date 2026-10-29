import '../models/mock_data.dart';
import '../models/server_connection.dart';
import 'secret_hygiene.dart';

/// Live security posture for the SECURITY panel (spec 04-state-patterns).
///
/// Pure mapping from the saved-server vault to [SecurityItem] rows — no
/// network, no keychain reads here (the screen already holds resolved
/// [ServerConnection]s). Findings:
/// - `critical` — server credential is raw pre-migration material
///   ([SecretHygiene.findRawCredentials]): migrate via Settings.
/// - `warning` — server has no credential stored at all.
/// A clean vault yields `[]` and the screen renders the StateView empty
/// frame ("VAULT CLEAN"); with no servers configured the screen keeps
/// the mock DEMO fallback instead.
class SecurityPosture {
  /// Findings for [servers], newest-relevant first (critical before
  /// warning, then server name for a stable order).
  static List<SecurityItem> findingsFor(List<ServerConnection> servers) {
    final rawIds = SecretHygiene.findRawCredentials([
      for (final s in servers) {'id': s.id, 'credential': s.credential},
    ]).toSet();
    final out = <SecurityItem>[];
    for (final s in servers) {
      if (rawIds.contains(s.id)) {
        out.add(SecurityItem(
          title: 'Plaintext credential on ${s.name} — migrate to keychain',
          severity: 'critical',
          category: 'Secrets',
          status: 'open',
          detectedAt: DateTime.now(),
        ));
      } else if (s.credential.isEmpty) {
        out.add(SecurityItem(
          title: 'No credential stored for ${s.name}',
          severity: 'warning',
          category: 'Secrets',
          status: 'open',
          detectedAt: DateTime.now(),
        ));
      }
    }
    int rank(String sev) => sev == 'critical' ? 0 : 1;
    out.sort((a, b) {
      final r = rank(a.severity).compareTo(rank(b.severity));
      if (r != 0) return r;
      return a.title.compareTo(b.title);
    });
    return out;
  }
}
