import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// TOFU (trust-on-first-use) SSH host-key pin store.
///
/// dartssh2 accepts ANY host key when `onVerifyHostKey` is null — the
/// library's own docs warn this leaves the connection open to
/// man-in-the-middle attacks. Every [SSHClient] in this app therefore
/// passes [SshHostKeys.verifierFor], so the first key seen for a
/// `host:port` is pinned and any later change for the same key type is
/// rejected (fail-closed).
///
/// Pins are `SHA256:...` fingerprints in OpenSSH format — public key
/// fingerprints, not secret material — kept in SharedPreferences under
/// `hostkey_<host>:<port>` as a JSON map `{keyType: fingerprint}` so one
/// host can pin several key types (rsa + ed25519, …). A change is only a
/// mismatch for the SAME key type presenting a DIFFERENT fingerprint.
///
/// First-connect UX: TOFU means the very first connection trusts the key
/// it sees. Verify that fingerprint out-of-band (compare with the server's
/// `/etc/ssh/ssh_host_*_key.pub`, e.g.
/// `ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub`) before sending real
/// credentials — the Settings test-connection reports it as "new host key
/// pinned". After a legitimate host reinstall, use [forget] (Settings →
/// server dialog → FORGET) and re-verify, never blindly.
enum HostKeyVerdict {
  /// No pin for this key type yet — pinned now, connection allowed.
  firstSeen,

  /// Same key type presents the pinned fingerprint — allowed.
  match,

  /// Same key type presents a DIFFERENT fingerprint — rejected.
  /// Possible MITM, host reinstall, or IP/DNS now pointing elsewhere.
  mismatch,
}

/// One verification outcome, surfaced to the UI via [SshHostKeys.verifierFor].
class HostKeyEvent {
  final String host;
  final int port;
  final String type;
  final String fingerprint;
  final HostKeyVerdict verdict;

  const HostKeyEvent({
    required this.host,
    required this.port,
    required this.type,
    required this.fingerprint,
    required this.verdict,
  });
}

class SshHostKeys {
  /// Prefs-key namespace for pins. Values are JSON `{keyType: fp}`.
  static const keyPrefix = 'hostkey_';

  static String prefsKey(String host, int port) =>
      '$keyPrefix${host.trim().toLowerCase()}:$port';

  /// Decode the UTF-8 `SHA256:...` fingerprint dartssh2 hands to
  /// [SSHHostkeyVerifyHandler]. Never throws; '' means unusable.
  static String fingerprintString(List<int> raw) {
    try {
      return utf8.decode(raw, allowMalformed: true);
    } catch (_) {
      return '';
    }
  }

  /// Pinned `{keyType: fingerprint}` for one host:port, or {} when none.
  /// Malformed entries are treated as empty, never thrown on.
  static Future<Map<String, String>> pinsFor(String host, int port) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(prefsKey(host, port));
      if (raw == null || raw.isEmpty) return {};
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return {};
      final out = <String, String>{};
      decoded.forEach((k, v) {
        if (k is String && v is String && k.isNotEmpty && v.isNotEmpty) {
          out[k] = v;
        }
      });
      return out;
    } catch (_) {
      return {};
    }
  }

  /// Human-readable one-liner for settings/debug UI, e.g.
  /// `ed25519 SHA256:abc… / rsa SHA256:def…`. '' when nothing is pinned.
  /// Fingerprints are non-secret; safe to display and log.
  static Future<String> summary(String host, int port) async {
    final pins = await pinsFor(host, port);
    if (pins.isEmpty) return '';
    final keys = pins.keys.toList()..sort();
    return keys.map((t) => '$t ${pins[t]}').join(' / ');
  }

  /// Check [fingerprint] for ([host], [port], [type]) against the pin store.
  /// Pins on first sight. Fail-closed: any store I/O error yields
  /// [HostKeyVerdict.mismatch] rather than silently skipping verification.
  static Future<HostKeyVerdict> checkAndRemember(
    String host,
    int port,
    String type,
    String fingerprint,
  ) async {
    if (type.isEmpty || fingerprint.isEmpty) return HostKeyVerdict.mismatch;
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = prefsKey(host, port);
      final pins = await pinsFor(host, port);
      final known = pins[type] ?? '';
      if (known.isEmpty) {
        pins[type] = fingerprint;
        await prefs.setString(key, jsonEncode(pins));
        return HostKeyVerdict.firstSeen;
      }
      return known == fingerprint
          ? HostKeyVerdict.match
          : HostKeyVerdict.mismatch;
    } catch (_) {
      return HostKeyVerdict.mismatch;
    }
  }

  /// Drop one host:port's pins (legitimate host reinstall / key rotation).
  /// The next connection re-pins via TOFU — verify out-of-band first.
  static Future<void> forget(String host, int port) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(prefsKey(host, port));
    } catch (_) {}
  }

  /// Drop-in `onVerifyHostKey` callback for every [SSHClient] in the app.
  /// Allows first-seen + matching pins, rejects changed keys AND malformed
  /// inputs. [onEvent] fires exactly once per handshake for UI surfacing
  /// (Settings test-connection tailors its message from it).
  static SSHHostkeyVerifyHandler verifierFor(
    String host,
    int port, {
    void Function(HostKeyEvent)? onEvent,
  }) {
    return (String type, Uint8List fingerprint) async {
      final fp = fingerprintString(fingerprint);
      final verdict = await checkAndRemember(host, port, type, fp);
      onEvent?.call(HostKeyEvent(
        host: host,
        port: port,
        type: type,
        fingerprint: fp,
        verdict: verdict,
      ));
      return verdict != HostKeyVerdict.mismatch;
    };
  }
}
