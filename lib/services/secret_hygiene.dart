/// Secrets-hygiene helpers (pure Dart, no plugins).
///
/// The credential store of record is `SecureStore` (flutter_secure_storage
/// for secrets, SharedPreferences for everything else, `secure:` markers in
/// the server JSON). This file adds the *audit* layer on top without touching
/// the store itself:
///
/// - [isSecureRef] / [findRawCredentials] spot prefs-resident secrets that
///   missed migration (post-migration every credential is `secure:<key>`).
/// - [redactForLog] masks secret-shaped map entries before they reach logs.
/// - [auditServers] summarizes one decoded server list for settings/debug UI.
///
/// Rotation + pruning live in `SecureStore` (see the mandated Option-A
/// cutover); import nothing here so these helpers stay unit-testable.
class SecretHygiene {
  static const securePrefix = 'secure:';

  /// Keys whose values must never reach logs or crash reports.
  static const sensitiveKeys = {
    'password',
    'credential',
    'token',
    'secret',
    'api_key',
    'apikey',
    'private_key',
    'passphrase',
  };

  /// True when [value] is a keychain reference, not secret material.
  static bool isSecureRef(String value) => value.startsWith(securePrefix);

  /// Ids of servers whose `credential` is non-empty raw material
  /// (i.e. not a `secure:` marker and not blank). Empty means clean.
  /// Each entry is expected to carry `id` + `credential` string fields;
  /// malformed entries are skipped, never thrown on.
  static List<String> findRawCredentials(List<dynamic> servers) {
    final raw = <String>[];
    for (final e in servers) {
      if (e is! Map) continue;
      final id = (e['id'] ?? '').toString();
      final cred = (e['credential'] ?? '').toString();
      if (id.isEmpty || cred.isEmpty) continue;
      if (!isSecureRef(cred)) raw.add(id);
    }
    return raw;
  }

  /// Copy of [entry] with sensitive values replaced by `••••••`.
  /// A key is sensitive when its lowercase form contains any [sensitiveKeys]
  /// fragment (so `github_token`, `access_token`, … are masked too).
  /// Non-string values pass through; unknown keys pass through.
  static Map<String, dynamic> redactForLog(Map<String, dynamic> entry) {
    final out = Map<String, dynamic>.of(entry);
    for (final key in out.keys.toList()) {
      final lower = key.toLowerCase();
      if (sensitiveKeys.any(lower.contains)) {
        out[key] = '••••••';
      }
    }
    return out;
  }

  /// `{secure: n, raw: [ids], empty: n}` over one decoded server list.
  static Map<String, dynamic> auditServers(List<dynamic> servers) {
    var secure = 0;
    var empty = 0;
    final raw = <String>[];
    for (final e in servers) {
      if (e is! Map) continue;
      final id = (e['id'] ?? '').toString();
      final cred = (e['credential'] ?? '').toString();
      if (cred.isEmpty) {
        empty++;
      } else if (isSecureRef(cred)) {
        secure++;
      } else if (id.isNotEmpty) {
        raw.add(id);
      }
    }
    return {'secure': secure, 'raw': raw, 'empty': empty};
  }
}
