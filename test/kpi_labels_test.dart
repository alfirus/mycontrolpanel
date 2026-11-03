import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:my_control_panel/screens/control_center_screen.dart';
import 'package:my_control_panel/services/mock_services.dart';
import 'package:my_control_panel/services/service_locator.dart';

/// Elizabeth (t_05e8f0f2): pin the overview KPI strip labels so the
/// `DEPOYS` -> `DEPLOYS` typo fixed in PR #162 can never regress.
/// The strip renders `_kpiCell` labels on the default (Overview) tab with
/// no servers/tokens configured, so plain mocks are enough.

Services _mockServices() => Services(
      metrics: const MockMetricsPoller(),
      procStats: const MockProcStatsPoller(),
      crons: const MockCronRepository(),
      apps: const MockAppRepository(),
      alerts: const MockAlertRepository(),
      keys: const MockKeyLoader(),
      secrets: MockSecretStore(),
      github: const MockGithubRepository(),
    );

const _secureChannel =
    MethodChannel('plugins.it_nomads.com/flutter_secure_storage');

Future<void> _pumpOverview(WidgetTester tester) async {
  SharedPreferences.setMockInitialValues({
    'auto_update_check': false,
    'auto_refresh': false,
    'notifications': false,
    'secrets_migrated_v1': true,
  });
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(_secureChannel, (call) async => null);
  Services.overrideCurrent(_mockServices());
  addTearDown(() {
    Services.overrideCurrent(null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_secureChannel, null);
  });
  await tester.pumpWidget(const MaterialApp(home: ControlCenterScreen()));
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 200));
  }
}

void main() {
  group('Overview KPI strip labels', () {
    testWidgets('DEPLOYS label is spelled correctly (no DEPOYS regress)',
        (tester) async {
      await _pumpOverview(tester);
      expect(find.text('DEPLOYS'), findsOneWidget);
      expect(find.text('DEPOYS'), findsNothing);
    });

    testWidgets('sibling KPI labels render alongside DEPLOYS', (tester) async {
      await _pumpOverview(tester);
      for (final label in ['SERVERS', 'CRONS', 'APPS', 'ALERTS', 'SECURITY']) {
        expect(find.text(label), findsOneWidget, reason: label);
      }
    });
  });
}
