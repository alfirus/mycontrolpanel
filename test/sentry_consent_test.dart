import 'package:flutter_test/flutter_test.dart';

import 'package:my_control_panel/services/error_reporting.dart';

/// Consent-gating logic for Sentry opt-in reporting (issue #26).
/// Pure functions only — no keychain/prefs/network touches, so these run
/// on the VM without plugins.
void main() {
  group('ErrorReporting.isEnabled consent gate', () {
    test('default is OFF: no opt-in means disabled even with a DSN', () {
      expect(
        ErrorReporting.isEnabled(
          optedIn: false,
          dsn: 'https://public@sentry.example.com/1',
        ),
        isFalse,
      );
    });

    test('opted-in without a DSN stays disabled', () {
      expect(ErrorReporting.isEnabled(optedIn: true, dsn: ''), isFalse);
      expect(ErrorReporting.isEnabled(optedIn: true, dsn: '   '), isFalse);
    });

    test('opted-in with a DSN enables reporting', () {
      expect(
        ErrorReporting.isEnabled(
          optedIn: true,
          dsn: 'https://public@sentry.example.com/1',
        ),
        isTrue,
      );
    });

    test('whitespace-padded DSN still counts as present', () {
      expect(
        ErrorReporting.isEnabled(
          optedIn: true,
          dsn: '  https://public@sentry.example.com/1\n',
        ),
        isTrue,
      );
    });
  });

  group('ErrorReporting.isValidDsn', () {
    test('accepts https DSN URLs', () {
      expect(
        ErrorReporting.isValidDsn('https://public@sentry.example.com/1'),
        isTrue,
      );
    });

    test('accepts http DSNs (self-hosted without TLS)', () {
      expect(
        ErrorReporting.isValidDsn('http://sentry.lan:9000/2'),
        isTrue,
      );
    });

    test('rejects blanks, non-URLs and non-http schemes', () {
      expect(ErrorReporting.isValidDsn(''), isFalse);
      expect(ErrorReporting.isValidDsn('   '), isFalse);
      expect(ErrorReporting.isValidDsn('not a url'), isFalse);
      expect(ErrorReporting.isValidDsn('ftp://sentry.example.com/1'), isFalse);
      expect(ErrorReporting.isValidDsn('sentry.example.com/1'), isFalse);
    });
  });

  group('ErrorReporting storage keys', () {
    test('consent lives in prefs, DSN lives in the keychain', () {
      // Regression: the DSN must never be stored as a prefs raw value.
      // Consent key stays a prefs bool (default OFF); the DSN key is only
      // ever passed to SecureStore readSecret/writeSecret/deleteSecret.
      expect(ErrorReporting.consentKey, 'sentry_opt_in');
      expect(ErrorReporting.dsnKey, 'sentry_dsn');
      expect(ErrorReporting.consentKey, isNot(ErrorReporting.dsnKey));
    });
  });
}
