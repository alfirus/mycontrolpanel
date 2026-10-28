import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/server_connection.dart';

/// Secrets live in the OS keychain/keystore; everything else stays in
/// SharedPreferences. Server list JSON in prefs holds `secure:<key>`
/// markers instead of raw credentials — migrated automatically once.
class SecureStore {
  static const _sec = FlutterSecureStorage();
  static const _credPrefix = 'srv_cred_';
  static const _migratedFlag = 'secrets_migrated_v1';

  static String _credKey(String serverId) => '$_credPrefix$serverId';

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

  /// Remove a server's keychain entry (call on delete).
  static Future<void> deleteServerCredential(String serverId) async {
    await deleteSecret(_credKey(serverId));
  }
}
