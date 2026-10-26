import 'package:flutter/material.dart';
import 'theme/app_theme.dart';
import 'screens/control_center_screen.dart';

void main() {
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
