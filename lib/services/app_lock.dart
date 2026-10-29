import 'package:flutter/foundation.dart';
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// SharedPreferences key for the Settings "Biometrics" toggle.
/// Written by [SettingsScreen], read here — one key, no duplication.
const appLockPrefsKey = 'biometrics';

/// Reason shown in the OS auth dialog.
const appLockReason = 'Unlock My Control Panel';

/// Copy shown when the device cannot authenticate at all
/// (no biometrics enrolled AND no device PIN/passcode, or a platform
/// without a local_auth plugin such as Linux).
const appLockUnavailableMessage =
    'This device has no unlock method available (no biometrics or '
    'device PIN set up). Turn the Biometrics toggle off in Settings '
    'to skip this screen.';

/// Minimal seam over [LocalAuthentication] so the lock logic stays
/// unit-testable without a platform channel.
abstract class AuthGate {
  Future<bool> isDeviceSupported();
  Future<bool> canCheckBiometrics();
  Future<bool> authenticate({required String reason});
}

/// Production gate backed by `local_auth`.
///
/// `biometricOnly: false` is deliberate: where biometrics are missing the
/// OS falls back to the device PIN/passcode instead of failing outright.
class LocalAuthGate implements AuthGate {
  LocalAuthGate([LocalAuthentication? auth])
      : _auth = auth ?? LocalAuthentication();

  final LocalAuthentication _auth;

  @override
  Future<bool> isDeviceSupported() => _auth.isDeviceSupported();

  @override
  Future<bool> canCheckBiometrics() => _auth.canCheckBiometrics;

  @override
  Future<bool> authenticate({required String reason}) =>
      _auth.authenticate(
        localizedReason: reason,
        // Biometric-first, but fall back to the device PIN/passcode
        // where biometrics are unavailable (local_auth 3.x API).
        biometricOnly: false,
      );
}

/// App-lock state: engages on cold start and on resume-from-background
/// whenever the Settings toggle is on.
///
/// Lifecycle: `load()` once at startup, `relock()` on every resume
/// (it re-reads prefs so a toggle flip in Settings takes effect without
/// a restart), `unlock()` from the lock screen.
class AppLock extends ChangeNotifier {
  AppLock({AuthGate? gate}) : _gate = gate ?? LocalAuthGate();

  final AuthGate _gate;

  /// Settings toggle state (last read from prefs).
  bool enabled = false;

  /// True when the lock screen must cover the app.
  bool locked = false;

  /// True while an OS auth dialog is in flight.
  bool busy = false;

  /// Last unlock failure / availability note for the lock screen.
  /// Null means "no problem to report".
  String? message;

  /// Cold start: read the toggle; engage the lock when it is on.
  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    enabled = prefs.getBool(appLockPrefsKey) ?? false;
    locked = enabled;
    message = null;
    notifyListeners();
  }

  /// Resume from background: re-read the toggle (Settings may have
  /// changed it while we were away) and re-engage when on.
  Future<void> relock() async {
    final prefs = await SharedPreferences.getInstance();
    enabled = prefs.getBool(appLockPrefsKey) ?? false;
    final shouldLock = enabled;
    if (locked != shouldLock) {
      locked = shouldLock;
      message = null;
      notifyListeners();
    }
  }

  /// Attempt unlock via the OS (biometrics, else device PIN/passcode).
  /// Returns true on success; on failure/cancel the app stays locked and
  /// [message] explains what happened.
  Future<bool> unlock() async {
    if (!enabled) {
      locked = false;
      message = null;
      notifyListeners();
      return true;
    }
    busy = true;
    message = null;
    notifyListeners();
    try {
      if (!await _gate.isDeviceSupported()) {
        message = appLockUnavailableMessage;
        return false;
      }
      final ok = await _gate.authenticate(reason: appLockReason);
      if (ok) {
        locked = false;
        message = null;
      } else {
        // User cancelled or failed auth: stay locked, neutral copy.
        message = 'Unlock cancelled — try again.';
      }
      return ok;
    } catch (_) {
      // MissingPluginException (e.g. Linux has no local_auth plugin),
      // PlatformException NotAvailable, etc.
      message = appLockUnavailableMessage;
      return false;
    } finally {
      busy = false;
      notifyListeners();
    }
  }
}
