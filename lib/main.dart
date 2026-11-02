// SPDX-License-Identifier: MIT
import 'dart:io' show exit;

import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'services/app_lock.dart';
import 'services/background_alerts.dart';
import 'services/desktop_alerts.dart';
import 'services/error_reporting.dart';
import 'services/release_health.dart';
import 'headless.dart';
import 'theme/app_theme.dart';
import 'screens/control_center_screen.dart';
import 'widgets/app_lock_screen.dart';

/// Sentry is armed here ONLY when the user opted in AND a DSN is stored
/// ([ErrorReporting.initIfOptedIn] is fully guarded — any failure falls
/// through to a plain runApp, so reporting can never break app launch
/// or a CI build that never opts in).
Future<void> main([List<String> args = const []]) async {
  WidgetsFlutterBinding.ensureInitialized();
  // Tray-mode headless tick (TM-1): `--poll-headless` runs one poll with
  // NO window and exits. This check sits before every other init so the
  // headless path can never boot UI, and normal launch (no flag) is
  // untouched. Contract: docs/specs/headless-cli-contract.md.
  final headlessExit = await runHeadlessIfRequested(args);
  if (headlessExit != null) exit(headlessExit);
  // Sentry release-health (Aisyah, DevOps): tag builds bake the track in
  // via --dart-define=SENTRY_ENVIRONMENT (release.yml); everything else
  // resolves to `development`. Guarded inside — never blocks launch.
  const sentryEnv = String.fromEnvironment('SENTRY_ENVIRONMENT');
  var sentryRelease = '';
  try {
    final info = await PackageInfo.fromPlatform();
    sentryRelease = ErrorReporting.buildRelease(
      packageName: info.packageName,
      version: info.version,
      buildNumber: info.buildNumber,
    );
  } catch (_) {}
  await ErrorReporting.initIfOptedIn(
    release: sentryRelease,
    environment: sentryEnv,
  );
  // Deploy heartbeat: at most one info event per install per 24 h so the
  // rollout census (docs/observability-dashboards.md) sees live releases.
  // Opt-in + interval gated inside; failures are silent by design.
  try {
    await ReleaseHealth.reportAppStart(
      release: sentryRelease,
      environment: ErrorReporting.resolveEnvironment(sentryEnv),
    );
  } catch (_) {}
  // Mobile background alerting (beta.1): re-register the WorkManager
  // dispatcher + periodic task when the user opted in. Desktop no-ops
  // (guarded inside); failures never block launch.
  try {
    await BackgroundAlerts.ensureInitialized();
  } catch (_) {}
  // Desktop local notifications (beta.1): init the win_toast /
  // notify-send / Darwin plugin paths + macOS user-allow prompt when the
  // user opted in via the SHARED background-alerts toggle. Mobile no-ops
  // (guarded inside); failures never block launch. Closed-app delivery
  // stays deferred to tray-mode work (see DesktopAlerts.closedAppNote).
  try {
    await DesktopAlerts.ensureInitialized();
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
