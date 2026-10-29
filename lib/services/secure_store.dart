import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/server_connection.dart';
import 'secret_hygiene.dart';

/// Secrets live in the OS keychain/keystore; everything else stays in
/// SharedPreferences. Server list JSON in prefs holds `secure:<key>`
/// markers instead of raw credentials — migrated automatically once.
class SecureStore {
  static const _sec = FlutterSecureStorage();
  static const _credPrefix = 'srv_cred_';
  static const _migratedFlag = 'secrets_migrated_v1';

  /// Per-host metrics-agent token (v4 token gate, X-MCP-Agent-Token).
  /// Same keychain guarantees as server credentials; never in prefs JSON.
  static const _agentTokenPrefix = 'agent_tok_';

  static String _credKey(String serverId) => '$_credPrefix$serverId';

  /// Keychain key for one server's agent token (pure, unit-testable).
  static String agentTokenKey(String serverId) =>
      '$_agentTokenPrefix$serverId';

  static Future<String?> readSecret(String key) async {
    try {
      return await _sec.read(key: key);
    } catch (_) {
      return null;
    }
  }

  static Future<void> writeSecret(String key, String value) async {
    await _sec.write(key: key, value: value);
  }

  static Future<void> deleteSecret(String key) async {
    try {
      await _sec.delete(key: key);
    } catch (_) {}
  }

  /// One-time migration: prefs-resident secrets → keychain/keystore.
  /// Idempotent (guarded by flag) and best-effort (never throws).
  static Future<void> migrateIfNeeded() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getBool(_migratedFlag) == true) return;
      // 1. server credentials embedded in the connections JSON
      final raw = prefs.getString('server_connections');
      if (raw != null) {
        try {
          final list = jsonDecode(raw) as List;
          var changed = false;
          for (final e in list) {
            final m = e as Map<String, dynamic>;
            final cred = (m['credential'] ?? '').toString();
            final id = (m['id'] ?? '').toString();
            if (cred.isNotEmpty && id.isNotEmpty && !cred.startsWith('secure:')) {
              await _sec.write(key: _credKey(id), value: cred);
              m['credential'] = 'secure:${_credKey(id)}';
              changed = true;
            }
          }
          if (changed) await prefs.setString('server_connections', jsonEncode(list));
        } catch (_) {}
      }
      // 2. standalone tokens
      for (final k in ['github_token', 'gitlab_token', 'ai_key']) {
        final v = prefs.getString(k);
        if (v != null && v.isNotEmpty) {
          await _sec.write(key: k, value: v);
          await prefs.remove(k);
        }
      }
      await prefs.setBool(_migratedFlag, true);
    } catch (_) {}
  }

  /// Vault status for the Settings UI: whether the one-time migration ran
  /// plus how many plaintext secrets are still prefs-resident (missed or
  /// keychain-unavailable). Read-only, never throws — the UI decides.
  static Future<({bool migrated, int plaintext})> vaultStatus() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final migrated = prefs.getBool(_migratedFlag) == true;
      var plaintext = 0;
      final raw = prefs.getString('server_connections');
      if (raw != null) {
        try {
          plaintext += SecretHygiene.findRawCredentials(jsonDecode(raw) as List).length;
        } catch (_) {}
      }
      for (final k in ['github_token', 'gitlab_token', 'ai_key']) {
        final v = prefs.getString(k);
        if (v != null && v.isNotEmpty) plaintext++;
      }
      return (migrated: migrated, plaintext: plaintext);
    } catch (_) {
      return (migrated: false, plaintext: 0);
    }
  }

  /// Clear the migration flag and re-run (Settings RETRY path for when the
  /// keychain was unavailable at first launch). Best-effort, never throws.
  static Future<void> retryMigration() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_migratedFlag);
    } catch (_) {}
    await migrateIfNeeded();
  }

  /// Load servers, resolving `secure:` credential markers from the keychain.
  /// Owner-mandated full migration (Option A, 2026-10-28): raw prefs
  /// credentials are never surfaced from disk — any legacy plaintext found
  /// is moved into the keychain on the spot and the persisted entry masked.
  /// A missing secure entry resolves to empty (force re-entry).
  static Future<List<ServerConnection>> readServers() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('server_connections');
    if (raw == null) return [];
    final decoded = ServerConnection.decodeList(raw);
    final out = <ServerConnection>[];
    var healed = false;
    for (final s in decoded) {
      if (s.credential.startsWith('secure:')) {
        final key = s.credential.substring('secure:'.length);
        final secret = await readSecret(key);
        out.add(secret == null || secret.isEmpty
            ? s.copyWith(credential: '')
            : ServerConnection(
                id: s.id, name: s.name, host: s.host, port: s.port,
                username: s.username, authMethod: s.authMethod,
                credential: secret, region: s.region, os: s.os,
                env: s.env, tags: s.tags, createdAt: s.createdAt,
                enabled: s.enabled,
              ));
      } else if (s.credential.isNotEmpty) {
        // Legacy plaintext on disk: move it into the keychain now, keep the
        // secret in memory for this session only, persist only the marker.
        await writeSecret(_credKey(s.id), s.credential);
        healed = true;
        out.add(s);
      } else {
        out.add(s);
      }
    }
    if (healed) await writeServers(out);
    return out;
  }

  /// Save servers, extracting credentials into the keychain.
  static Future<void> writeServers(List<ServerConnection> servers) async {
    for (final s in servers) {
      final cred = s.credential;
      if (cred.isNotEmpty && !cred.startsWith('secure:')) {
        await writeSecret(_credKey(s.id), cred);
      }
    }
    final masked = servers.map((s) {
      if (s.credential.startsWith('secure:')) return s;
      return ServerConnection(
        id: s.id, name: s.name, host: s.host, port: s.port,
        username: s.username, authMethod: s.authMethod,
        credential: 'secure:${_credKey(s.id)}', region: s.region, os: s.os,
        env: s.env, tags: s.tags, createdAt: s.createdAt,
        enabled: s.enabled,
      );
    }).toList();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('server_connections', ServerConnection.encodeList(masked));
  }

  /// Remove a server's keychain entries (credential + agent token) —
  /// call on delete so nothing orphans in the keychain.
  static Future<void> deleteServerCredential(String serverId) async {
    await deleteSecret(_credKey(serverId));
    await deleteSecret(agentTokenKey(serverId));
  }

  /// Read this server's agent token (null when unset = open agent).
  static Future<String?> readAgentToken(String serverId) =>
      readSecret(agentTokenKey(serverId));

  /// Store (or, when [token] is blank, clear) this server's agent token.
  static Future<void> writeAgentToken(String serverId, String token) async {
    if (token.trim().isEmpty) {
      await deleteSecret(agentTokenKey(serverId));
    } else {
      await writeSecret(agentTokenKey(serverId), token.trim());
    }
  }

  /// Key rotation (mandated cutover, Option A): overwrite the keychain entry
  /// for [serverId] with [newCredential] without touching the masked prefs
  /// JSON (it already holds only the `secure:` marker). Best-effort.
  static Future<void> rotateServerCredential(
      String serverId, String newCredential) async {
    try {
      if (newCredential.isEmpty) {
        await deleteSecret(_credKey(serverId));
      } else {
        await writeSecret(_credKey(serverId), newCredential);
      }
    } catch (_) {}
  }

  /// Delete keychain entries whose server no longer exists (e.g. after
  /// clear-all or an import that drops hosts). Covers server credentials
  /// AND agent tokens. Best-effort, never throws.
  static Future<void> pruneServerCredentials(Set<String> validIds) async {
    try {
      final all = await _sec.readAll();
      for (final key in all.keys) {
        if (key.startsWith(_credPrefix)) {
          if (!validIds.contains(key.substring(_credPrefix.length))) {
            await deleteSecret(key);
          }
        } else if (key.startsWith(_agentTokenPrefix)) {
          if (!validIds.contains(key.substring(_agentTokenPrefix.length))) {
            await deleteSecret(key);
          }
        }
      }
    } catch (_) {}
  }
}
