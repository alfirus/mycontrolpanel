// SPDX-License-Identifier: MIT
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'secure_store.dart';

/// Opt-in crash/error reporting via Sentry (issue #26).
///
/// Privacy: reporting is OFF by default. Nothing leaves the device unless
/// the user flips the Settings toggle AND saves a DSN. The DSN lives in
/// the OS keychain/keystore via [SecureStore] — never in prefs raw,
/// never hardcoded.
///
/// LIMIT (deliberate scope cut): Dart-layer only. No native
/// symbol-upload setup (sentry-cli / `--split-debug-info` / dSYM / NDK
/// upload), so release stack traces through native frames may arrive
/// unsymbolicated. Revisit if store builds need symbolicated crashes.
class ErrorReporting {
  ErrorReporting._();

  /// Prefs key for the explicit opt-in toggle. Default OFF.
  static const consentKey = 'sentry_opt_in';

  /// Keychain key for the Sentry DSN ([SecureStore] secret, never prefs).
  static const dsnKey = 'sentry_dsn';

  /// Pure consent gate: report only when opted-in AND a DSN is present.
  /// Unit-tested (test/sentry_consent_test.dart).
  static bool isEnabled({required bool optedIn, required String dsn}) =>
      optedIn && dsn.trim().isNotEmpty;

  /// Minimal DSN sanity check for the Settings form (pure, unit-tested).
  /// Accepts http(s) URLs; real validation is a test event (#26).
  static bool isValidDsn(String v) {
    final s = v.trim();
    if (s.isEmpty || s.contains(RegExp(r'\s'))) return false;
    final uri = Uri.tryParse(s);
    return uri != null &&
        (uri.scheme == 'https' || uri.scheme == 'http') &&
        uri.host.isNotEmpty;
  }

  /// Reads the persisted gate state. Never throws; unknown == disabled.
  static Future<({bool optedIn, bool hasDsn})> loadStatus() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final optedIn = prefs.getBool(consentKey) ?? false;
      final dsn = await SecureStore.readSecret(dsnKey) ?? '';
      return (
        optedIn: optedIn,
        hasDsn: isEnabled(optedIn: true, dsn: dsn),
      );
    } catch (_) {
      return (optedIn: false, hasDsn: false);
    }
  }

  /// Persists the opt-in toggle. Never throws.
  static Future<void> setOptIn(bool v) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(consentKey, v);
    } catch (_) {}
  }

  /// Persists (or clears, when blank) the DSN in the OS keychain.
  /// Never throws.
  static Future<void> setDsn(String dsn) async {
    final s = dsn.trim();
    try {
      if (s.isEmpty) {
        await SecureStore.deleteSecret(dsnKey);
      } else {
        await SecureStore.writeSecret(dsnKey, s);
      }
    } catch (_) {}
  }

  /// Sentry init for app startup. Fully guarded: any failure (or a
  /// disabled gate) falls through silently so reporting can never break
  /// app launch — or a CI build that never opts in.
  ///
  /// [release] / [environment] feed Sentry release-health (see
  /// docs/observability-dashboards.md): crash-free sessions are sliced by
  /// release (`<package>@<version>+<build>`) and environment
  /// (tag beta builds report `beta`, stable tags `production`, everything
  /// else `development`). Empty values fall back to Sentry's own defaults
  /// so old call sites keep working.
  static Future<void> initIfOptedIn(
      {String release = '', String environment = ''}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getBool(consentKey) != true) return;
      final dsn = (await SecureStore.readSecret(dsnKey) ?? '').trim();
      if (dsn.isEmpty) return;
      await SentryFlutter.init((o) {
        o.dsn = dsn;
        if (release.isNotEmpty) o.release = release;
        o.environment = resolveEnvironment(environment);
      });
    } catch (_) {
      // Reporting must never break startup.
    }
  }

  /// Builds a Sentry release string from package metadata.
  /// Pure — unit-tested (test/release_health_test.dart).
  static String buildRelease({
    required String packageName,
    required String version,
    String buildNumber = '',
  }) {
    final v = buildNumber.trim().isEmpty
        ? version.trim()
        : '${version.trim()}+${buildNumber.trim()}';
    return '${packageName.trim()}@$v';
  }

  /// Maps a raw environment name to the Sentry environment. Tag-track
  /// builds pass `beta`/`stable` via `--dart-define=SENTRY_ENVIRONMENT`
  /// (release.yml): beta stays `beta`, stable releases are `production`,
  /// and anything else (local, PR, store sideloads) is `development` so
  /// dev noise never pollutes the crash-free SLO.
  /// Pure — unit-tested (test/release_health_test.dart).
  static String resolveEnvironment(String raw) {
    final s = raw.trim().toLowerCase();
    if (s == 'beta') return 'beta';
    if (s == 'stable') return 'production';
    return 'development';
  }

  /// Arms Sentry on demand (Settings test-event path, when the user opts
  /// in mid-session after startup init already ran). No-op when armed.
  static Future<void> _ensureArmed() async {
    if (Sentry.isEnabled) return;
    final dsn = (await SecureStore.readSecret(dsnKey) ?? '').trim();
    if (dsn.isEmpty) {
      throw StateError('Save a DSN first.');
    }
    await SentryFlutter.init((o) {
      o.dsn = dsn;
    });
  }

  /// Fires a test message at the configured DSN and returns its event id
  /// for the delivery confirmation. Throws a human-readable [StateError]
  /// when the gate is off or delivery fails — the UI surfaces it.
  static Future<String> sendTestEvent() async {
    final status = await loadStatus();
    if (!status.optedIn) {
      throw StateError('Turn the opt-in toggle on first.');
    }
    if (!status.hasDsn) {
      throw StateError('Save a DSN first.');
    }
    try {
      await _ensureArmed();
      final id = await Sentry.captureMessage(
        'MyControlPanel test event',
        level: SentryLevel.info,
      );
      return id.toString();
    } catch (e) {
      if (e is StateError) rethrow;
      throw StateError(
        'Test event failed: ${'$e'.replaceFirst('Exception: ', '').split('\n').first}',
      );
    }
  }

  /// Shuts Sentry down (opt-out path). Guarded, never throws.
  static Future<void> shutdown() async {
    try {
      await Sentry.close();
    } catch (_) {}
  }
}
