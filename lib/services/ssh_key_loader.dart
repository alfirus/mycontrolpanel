import 'dart:io';
import 'package:dartssh2/dartssh2.dart';

class KeyLoadResult {
  final List<SSHKeyPair>? keys;
  final String? error;
  final bool needsPassphrase;
  const KeyLoadResult({this.keys, this.error, this.needsPassphrase = false});
}

class SshKeyLoader {
  static final _b64 = RegExp(r'^[A-Za-z0-9+/=]+$');

  /// Rebuilds a well-formed PEM block from messy pasted text:
  /// keeps header lines (Proc-Type/DEK-Info/Version/Comment), collects
  /// base64 body lines, re-wraps at 64 cols with proper BEGIN/END.
  /// Returns input unchanged if it already looks like a full PEM block
  /// (both BEGIN and END present) or a file path.
  static String _normalizePem(String input) {
    final t = input.trim();
    final hasBegin = t.contains('-----BEGIN');
    final hasEnd = t.contains('-----END');
    if (hasBegin && hasEnd) return t; // already complete
    if (!t.contains('Proc-Type') && !t.contains('DEK-Info') &&
        !_b64.hasMatch(t.split('\n').first.trim())) {
      return t; // probably a file path — leave for path handling
    }
    String? beginKind;
    if (hasBegin) {
      final m = RegExp(r'-----BEGIN ([^-]+)-----').firstMatch(t);
      if (m != null) beginKind = m.group(1)!.trim();
    }
    final headers = <String>[];
    final body = StringBuffer();
    for (final raw in t.split('\n')) {
      final line = raw.trim();
      if (line.isEmpty) continue;
      if (line.startsWith('-----')) continue; // drop partial headers/footers
      if (line.startsWith('Proc-Type:') ||
          line.startsWith('DEK-Info:') ||
          line.startsWith('Version:') ||
          line.startsWith('Comment:')) {
        headers.add(line);
        continue;
      }
      final compact = line.replaceAll(RegExp(r'\s+'), '');
      if (compact.isNotEmpty && _b64.hasMatch(compact)) body.write(compact);
    }
    final kind = beginKind ??
        (headers.isNotEmpty ? 'RSA PRIVATE KEY' : 'RSA PRIVATE KEY');
    final b64 = body.toString();
    if (b64.isEmpty) return t;
    final wrapped = RegExp('.{1,64}').allMatches(b64).map((m) => m.group(0)!).join('\n');
    final headerBlock = headers.isEmpty ? '' : '${headers.join('\n')}\n';
    return '-----BEGIN $kind-----\n$headerBlock$wrapped\n-----END $kind-----';
  }

  /// Resolves saved credential (file path OR pasted PEM) into key pairs.
  static Future<KeyLoadResult> load(String credential, {String? passphrase}) async {
    var pem = credential.trim();
    // Normalize: rebuild a clean PEM block. Handles pastes missing the
    // BEGIN/END headers, stray blank lines, or trailing whitespace that
    // break strict PEM parsers ("PEM footer must start with -----END").
    pem = _normalizePem(pem);
    // Looks like a path (not PEM content)?
    if (!pem.contains('PRIVATE KEY') && !pem.contains('OPENSSH')) {
      var path = pem;
      if (path.startsWith('~/')) {
        final home = Platform.environment['HOME'] ?? '';
        path = '$home/${path.substring(2)}';
      }
      final file = File(path);
      if (!await file.exists()) {
        return KeyLoadResult(error: 'Key not visible to the app at: $pem\nThe file exists in Finder, but the macOS sandbox hides it. Fixes (best first): 1) Terminal tab → folder icon → pick the file (stores content, always works). 2) Paste the full key content into Settings instead of the path. 3) Move the key to ~/Downloads (now permitted) and retry.');
      }
      try {
        pem = await file.readAsString();
      } catch (e) {
        return KeyLoadResult(error: 'Cannot read key file (sandbox blocked?): $e\nTip: use the folder button to grant access, or paste the key content.');
      }
    }
    // Legacy DES-encrypted PEM (e.g. DEK-Info: DES-EDE3-CBC) can never be
    // decrypted by dartssh2 (AES-only) — don't prompt, explain the fix.
    final dek = RegExp(r'DEK-Info:\s*([A-Za-z0-9\-]+)').firstMatch(pem)?.group(1)?.toUpperCase() ?? '';
    if (dek.isNotEmpty && dek.contains('DES')) {
      return const KeyLoadResult(error:
          'This key uses legacy DES encryption (DES-EDE3-CBC), which this app cannot decrypt — any passphrase will fail.\n\n'
          'Convert it once on your Mac (keeps the same key, upgrades the cipher):\n'
          'ssh-keygen -p -m RFC4716 -f ~/.ssh/<key>\n'
          '(enter the old passphrase, then choose a new one)\n\n'
          'Then re-import the converted file via the folder button in Settings or Terminal.');
    }
    try {
      if (passphrase == null && SSHKeyPair.isEncryptedPem(pem)) {
        return const KeyLoadResult(needsPassphrase: true);
      }
      final keys = SSHKeyPair.fromPem(pem, passphrase);
      return KeyLoadResult(keys: keys);
    } catch (e) {
      final msg = e.toString();
      if (msg.contains('passphrase') || msg.contains('encrypted') || msg.contains('bcrypt')) {
        return const KeyLoadResult(needsPassphrase: true);
      }
      return KeyLoadResult(error: 'Invalid key: $e');
    }
  }
}
