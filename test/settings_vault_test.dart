import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:my_control_panel/screens/settings_screen.dart' show validateServerHost;
import 'package:my_control_panel/services/secure_store.dart';

void main() {
  group('validateServerHost', () {
    test('blank is required', () {
      expect(validateServerHost(null), 'Required');
      expect(validateServerHost('   '), 'Required');
    });

    test('accepts IPv4, DNS names and localhost', () {
      expect(validateServerHost('10.0.1.10'), isNull);
      expect(validateServerHost('prod.example.com'), isNull);
      expect(validateServerHost('localhost'), isNull);
      expect(validateServerHost('  db-01.internal  '), isNull);
    });

    test('rejects bad IPv4 octets', () {
      expect(validateServerHost('999.1.1.1'), 'Invalid IPv4 address');
      expect(validateServerHost('1.2.3'), isNotNull);
    });

    test('rejects URLs, ports and malformed names', () {
      expect(validateServerHost('https://example.com'), 'Host or IP — not a URL');
      expect(validateServerHost('example.com:22'), 'No port here — use the Port field');
      expect(validateServerHost('bad_host'), 'Invalid hostname');
      expect(validateServerHost('-bad.com'), 'Invalid hostname');
      expect(validateServerHost('a..b'), 'Invalid hostname');
      expect(validateServerHost('has space.com'), 'Invalid hostname');
    });
  });

  group('SecureStore.vaultStatus', () {
    test('counts plaintext server creds + standalone tokens', () async {
      SharedPreferences.setMockInitialValues({
        'server_connections': jsonEncode([
          {'id': 'a', 'credential': 'secure:srv_cred_a'},
          {'id': 'b', 'credential': 'hunter2'},
          {'id': 'c', 'credential': ''},
        ]),
        'github_token': 'ghp_x',
      });
      final vs = await SecureStore.vaultStatus();
      expect(vs.migrated, isFalse);
      expect(vs.plaintext, 2); // server b + github token
    });

    test('clean vault reads zero with flag set', () async {
      SharedPreferences.setMockInitialValues({
        'secrets_migrated_v1': true,
        'server_connections': jsonEncode([
          {'id': 'a', 'credential': 'secure:srv_cred_a'},
        ]),
      });
      final vs = await SecureStore.vaultStatus();
      expect(vs.migrated, isTrue);
      expect(vs.plaintext, 0);
    });

    test('missing prefs snapshot is not an error', () async {
      SharedPreferences.setMockInitialValues({});
      final vs = await SecureStore.vaultStatus();
      expect(vs.plaintext, 0);
    });
  });
}
