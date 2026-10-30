import 'package:flutter/material.dart';
import 'services/app_lock.dart';
import 'services/background_alerts.dart';
import 'services/error_reporting.dart';
import 'theme/app_theme.dart';
import 'screens/control_center_screen.dart';
import 'widgets/app_lock_screen.dart';

/// Sentry is armed here ONLY when the user opted in AND a DSN is stored
/// ([ErrorReporting.initIfOptedIn] is fully guarded — any failure falls
/// through to a plain runApp, so reporting can never break app launch
/// or a CI build that never opts in).
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await ErrorReporting.initIfOptedIn();
  // Mobile background alerting (beta.1): re-register the WorkManager
  // dispatcher + periodic task when the user opted in. Desktop no-ops
  // (guarded inside); failures never block launch.
  try {
    await BackgroundAlerts.ensureInitialized();
  } catch (_) {}
  runApp(const MyControlPanelApp());
}

class MyControlPanelApp extends StatefulWidget {
  /// Injectable for tests — production builds use the default [AppLock].
  const MyControlPanelApp({super.key, this.appLock});

  final AppLock? appLock;

  @override
  State<MyControlPanelApp> createState() => _MyControlPanelAppState();
}

class _MyControlPanelAppState extends State<MyControlPanelApp>
    with WidgetsBindingObserver {
  late final AppLock _lock;
  bool get _ownsLock => widget.appLock == null;

  @override
  void initState() {
    super.initState();
    _lock = widget.appLock ?? AppLock();
    WidgetsBinding.instance.addObserver(this);
    // Cold start: engages the lock screen when the toggle is on.
    _lock.load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (_ownsLock) _lock.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Resume from background: re-engage when the toggle is on.
    // (relock() re-reads prefs, so a toggle flip in Settings applies
    // without a restart.)
    if (state == AppLifecycleState.resumed) {
      _lock.relock();
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'My Control Panel',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark,
      home: ListenableBuilder(
        listenable: _lock,
        builder: (context, _) {
          if (_lock.locked) return AppLockScreen(lock: _lock);
          return const ControlCenterScreen();
        },
      ),
    );
  }
}
