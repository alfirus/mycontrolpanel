import 'package:flutter/material.dart';
import 'services/error_reporting.dart';
import 'theme/app_theme.dart';
import 'screens/control_center_screen.dart';

/// Sentry is armed here ONLY when the user opted in AND a DSN is stored
/// ([ErrorReporting.initIfOptedIn] is fully guarded — any failure falls
/// through to a plain runApp, so reporting can never break app launch
/// or a CI build that never opts in).
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await ErrorReporting.initIfOptedIn();
  runApp(const MyControlPanelApp());
}

class MyControlPanelApp extends StatelessWidget {
  const MyControlPanelApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'My Control Panel',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark,
      home: const ControlCenterScreen(),
    );
  }
}
