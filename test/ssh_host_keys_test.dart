import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:my_control_panel/services/ssh_host_keys.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('prefsKey', () {
    test('namespaces per host+port, case-insensitive', () {
      expect(SshHostKeys.prefsKey('Example.COM ', 22), 'hostkey_example.com:22');
      expect(SshHostKeys.prefsKey('h', 1), isNot(SshHostKeys.prefsKey('h', 2)));
    });
  });

  group('fingerprintString', () {
    test('decodes dartssh2-style SHA256 fingerprint bytes', () {
      const fp = 'SHA256:AbCdEf123456';
      expect(SshHostKeys.fingerprintString(fp.codeUnits), fp);
    });

    test('empty input yields empty, never throws', () {
      expect(SshHostKeys.fingerprintString([]), '');
    });
  });

  group('checkAndRemember', () {
    test('first sight pins, repeat matches, change mismatches', () async {
      expect(
        await SshHostKeys.checkAndRemember('h', 22, 'ssh-ed25519', 'SHA256:AAA'),
        HostKeyVerdict.firstSeen,
      );
      expect(
        await SshHostKeys.checkAndRemember('h', 22, 'ssh-ed25519', 'SHA256:AAA'),
        HostKeyVerdict.match,
      );
      expect(
        await SshHostKeys.checkAndRemember('h', 22, 'ssh-ed25519', 'SHA256:BBB'),
        HostKeyVerdict.mismatch,
      );
      // Mismatch never overwrites the pin.
      expect((await SshHostKeys.pinsFor('h', 22))['ssh-ed25519'], 'SHA256:AAA');
    });

    test('each key type pins independently', () async {
      expect(
        await SshHostKeys.checkAndRemember('h', 22, 'ssh-ed25519', 'SHA256:A'),
        HostKeyVerdict.firstSeen,
      );
      expect(
        await SshHostKeys.checkAndRemember('h', 22, 'ssh-rsa', 'SHA256:B'),
        HostKeyVerdict.firstSeen,
      );
      expect(
        await SshHostKeys.checkAndRemember('h', 22, 'ssh-rsa', 'SHA256:B'),
        HostKeyVerdict.match,
      );
    });

    test('empty type or fingerprint is a mismatch (fail-closed)', () async {
      expect(await SshHostKeys.checkAndRemember('h', 22, '', 'SHA256:A'),
          HostKeyVerdict.mismatch);
      expect(await SshHostKeys.checkAndRemember('h', 22, 'ssh-rsa', ''),
          HostKeyVerdict.mismatch);
    });

    test('hosts and ports are isolated', () async {
      await SshHostKeys.checkAndRemember('a', 22, 'ssh-rsa', 'SHA256:X');
      expect(
        await SshHostKeys.checkAndRemember('b', 22, 'ssh-rsa', 'SHA256:X'),
        HostKeyVerdict.firstSeen,
      );
      expect(
        await SshHostKeys.checkAndRemember('a', 2222, 'ssh-rsa', 'SHA256:X'),
        HostKeyVerdict.firstSeen,
      );
    });

    test('forget clears pins so the next sight re-pins', () async {
      await SshHostKeys.checkAndRemember('h', 22, 'ssh-rsa', 'SHA256:X');
      await SshHostKeys.forget('h', 22);
      expect(await SshHostKeys.pinsFor('h', 22), isEmpty);
      expect(
        await SshHostKeys.checkAndRemember('h', 22, 'ssh-rsa', 'SHA256:Y'),
        HostKeyVerdict.firstSeen,
      );
    });
  });

  group('summary', () {
    test('empty when nothing pinned, sorted one-liner otherwise', () async {
      expect(await SshHostKeys.summary('h', 22), '');
      await SshHostKeys.checkAndRemember('h', 22, 'ssh-rsa', 'SHA256:B');
      await SshHostKeys.checkAndRemember('h', 22, 'ssh-ed25519', 'SHA256:A');
      expect(await SshHostKeys.summary('h', 22),
          'ssh-ed25519 SHA256:A / ssh-rsa SHA256:B');
    });
  });

  group('verifierFor', () {
    test('allows first-seen and match, rejects change', () async {
      final seen = <HostKeyEvent>[];
      final verify = SshHostKeys.verifierFor('h', 22, onEvent: seen.add);
      expect(await verify('ssh-ed25519', _fp('SHA256:A')), isTrue);
      expect(seen.single.verdict, HostKeyVerdict.firstSeen);
      expect(await verify('ssh-ed25519', _fp('SHA256:A')), isTrue);
      expect(seen.last.verdict, HostKeyVerdict.match);
      expect(await verify('ssh-ed25519', _fp('SHA256:EVIL')), isFalse);
      expect(seen.last.verdict, HostKeyVerdict.mismatch);
      expect(seen, hasLength(3));
    });

    test('rejects empty type or empty fingerprint', () async {
      final verify = SshHostKeys.verifierFor('h', 22);
      expect(await verify('', _fp('SHA256:A')), isFalse);
      expect(await verify('ssh-rsa', _fp('')), isFalse);
    });
  });
}

Uint8List _fp(String s) => Uint8List.fromList(s.codeUnits);
