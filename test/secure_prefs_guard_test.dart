import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Option-A enforcement (mandated 2026-10-28): secrets live in the OS
/// keychain via [SecureStore], never in SharedPreferences. `SecretHygiene`
/// audits RUNTIME state; this test audits the SOURCE: it scans every
/// `lib/**/*.dart` file and fails CI if a new direct-prefs secret path
/// lands outside the single store of record.
///
/// Rules:
///  1. Only `lib/services/secure_store.dart` may name the
///     `'server_connections'` prefs key (it owns masking + migration).
///  2. No file may write a secret-shaped prefs key
///     (`github_token`, `gitlab_token`, `ai_key`, `key_passphrase`,
///     `private_key`, `*_password`) via `setString`/`setStringList`.
///     Reads of legacy keys are allowed ONLY in secure_store.dart
///     (one-time migration); writes are allowed nowhere.
///
/// Pure-Dart file scan — runs under `flutter test` like every other gate.
void main() {
  group('secure prefs guard (Option A)', () {
    late List<File> dartFiles;

    setUpAll(() {
      final lib = Directory('lib');
      expect(lib.existsSync(), isTrue,
          reason: 'guard runs from the package root (flutter test cwd)');
      dartFiles = lib
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))
          .toList();
      expect(dartFiles, isNotEmpty);
    });

    test('server_connections key owned solely by secure_store.dart', () {
      final offenders = <String>[];
      for (final f in dartFiles) {
        // Windows paths use backslashes — normalize before matching.
        if (f.path.replaceAll('\\', '/').endsWith('lib/services/secure_store.dart')) continue;
        final src = f.readAsStringSync();
        if (src.contains("'server_connections'") ||
            src.contains('"server_connections"')) {
          offenders.add(f.path);
        }
      }
      expect(offenders, isEmpty,
          reason:
              'server_connections must only be touched via SecureStore; found in $offenders');
    });

    test('no direct prefs writes of secret-shaped keys', () {
      final secretKey = RegExp(
          r'''(github_token|gitlab_token|ai_key|key_passphrase|private_key|\w*password\w*)''');
      final writeCall =
          RegExp(r'''setString(List)?\(\s*['"]([^'"]+)['"]''');
      final offenders = <String>[];
      for (final f in dartFiles) {
        final src = f.readAsStringSync();
        for (final m in writeCall.allMatches(src)) {
          final key = m.group(2) ?? '';
          if (secretKey.hasMatch(key)) offenders.add('${f.path}::$key');
        }
      }
      expect(offenders, isEmpty,
          reason:
              'secrets must go through SecureStore (keychain), not prefs; found $offenders');
    });

    test('legacy token-key reads only in secure_store.dart (migration)', () {
      final legacyRead =
          RegExp(r'''getString\(\s*['"](github_token|gitlab_token|ai_key)['"]''');
      final offenders = <String>[];
      for (final f in dartFiles) {
        // Windows paths use backslashes — normalize before matching.
        if (f.path.replaceAll('\\', '/').endsWith('lib/services/secure_store.dart')) continue;
        if (legacyRead.hasMatch(f.readAsStringSync())) {
          offenders.add(f.path);
        }
      }
      expect(offenders, isEmpty,
          reason:
              'legacy prefs token reads belong only to the one-time migration; found in $offenders');
    });
  });
}
