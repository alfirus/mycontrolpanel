import 'package:flutter_test/flutter_test.dart';
import 'package:my_control_panel/services/secret_hygiene.dart';

void main() {
  group('isSecureRef', () {
    test('detects keychain markers', () {
      expect(SecretHygiene.isSecureRef('secure:srv_cred_abc'), isTrue);
      expect(SecretHygiene.isSecureRef('hunter2'), isFalse);
      expect(SecretHygiene.isSecureRef(''), isFalse);
    });
  });

  group('findRawCredentials', () {
    test('flags only non-empty raw credentials', () {
      final servers = [
        {'id': 'a', 'credential': 'secure:srv_cred_a'},
        {'id': 'b', 'credential': 'plaintext-password'},
        {'id': 'c', 'credential': ''},
        {'id': '', 'credential': 'orphan-secret'},
        'not-a-map',
      ];
      expect(SecretHygiene.findRawCredentials(servers), ['b']);
    });

    test('clean list yields empty', () {
      expect(SecretHygiene.findRawCredentials([]), isEmpty);
      expect(
        SecretHygiene.findRawCredentials([
          {'id': 'a', 'credential': 'secure:x'},
        ]),
        isEmpty,
      );
    });
  });

  group('redactForLog', () {
    test('masks sensitive keys, keeps the rest', () {
      final out = SecretHygiene.redactForLog({
        'host': 'example.com',
        'password': 'hunter2',
        'GitHub_Token': 'ghp_abc',
        'port': 22,
      });
      expect(out['host'], 'example.com');
      expect(out['port'], 22);
      expect(out['password'], '••••••');
      expect(out['GitHub_Token'], '••••••');
    });

    test('does not mutate the input', () {
      final input = {'token': 'abc'};
      SecretHygiene.redactForLog(input);
      expect(input['token'], 'abc');
    });
  });

  group('auditServers', () {
    test('counts secure/raw/empty', () {
      final audit = SecretHygiene.auditServers([
        {'id': 'a', 'credential': 'secure:srv_cred_a'},
        {'id': 'b', 'credential': 'raw-secret'},
        {'id': 'c', 'credential': ''},
      ]);
      expect(audit['secure'], 1);
      expect(audit['raw'], ['b']);
      expect(audit['empty'], 1);
    });
  });
}
