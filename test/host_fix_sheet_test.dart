// SPDX-License-Identifier: MIT
/// Widget test for the approve-first host-fix flow: tapping a fix first
/// reveals the dry-run preview (nothing runs yet); CONFIRM runs the SSH
/// command once, audit-logs it, and lands the result on the toast rail.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_control_panel/models/alert_entry.dart';
import 'package:my_control_panel/services/audit_log.dart';
import 'package:my_control_panel/widgets/host_fix_sheet.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _alert = AlertEntry(
  title: 'Service failed: nginx',
  source: 'systemd • web-01',
  severity: 'critical',
  serverId: 's-web-01',
  serverName: 'web-01',
);

Widget _harness(HostFixRunner runner, {required VoidCallback onChanged}) {
  return MaterialApp(
    home: Scaffold(
      body: Builder(
        builder: (context) => TextButton(
          onPressed: () => showHostFixSheet(
            context: context,
            alert: _alert,
            runner: runner,
            onChanged: onChanged,
          ),
          child: const Text('OPEN FIX'),
        ),
      ),
    ),
  );
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('approve flow: preview first, run once on confirm, toast result',
      (tester) async {
    final ran = <String>[];
    var changed = 0;
    await tester.pumpWidget(_harness(
      (cmd) async {
        ran.add(cmd);
        return '[exit 0]\nactive';
      },
      onChanged: () => changed++,
    ));

    await tester.tap(find.text('OPEN FIX'));
    await tester.pumpAndSettle();
    expect(find.text('RESTART'), findsOneWidget);

    // First tap arms the confirm step — dry-run preview, nothing runs.
    await tester.tap(find.text('RESTART'));
    await tester.pumpAndSettle();
    expect(ran, isEmpty);
    expect(find.textContaining('Will run: sudo systemctl restart nginx'), findsOneWidget);

    // Confirm runs exactly once, closes the sheet, toasts the result.
    await tester.tap(find.text('CONFIRM RESTART'));
    await tester.pumpAndSettle();
    expect(ran, ['sudo systemctl restart nginx && sleep 1 && systemctl is-active nginx']);
    expect(changed, 1);
    expect(find.text('RESTART on web-01 ✓'), findsOneWidget);
    expect(find.text('CONFIRM RESTART'), findsNothing);

    // Approval was audit-logged.
    final log = await AuditLog.read();
    expect(log.any((e) => e.tool == 'host_fix.restartService' && e.decision == 'approved'),
        isTrue);
  });

  testWidgets('failed run stays open and shows the error', (tester) async {
    await tester.pumpWidget(_harness(
      (_) async => throw Exception('boom: connection refused\ndetail'),
      onChanged: () {},
    ));

    await tester.tap(find.text('OPEN FIX'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('RESTART'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('CONFIRM RESTART'));
    await tester.pumpAndSettle();

    expect(find.textContaining('boom: connection refused'), findsOneWidget);
    // Sheet stays open for retry; failure is audit-logged too.
    expect(find.text('CONFIRM RESTART'), findsOneWidget);
    final log = await AuditLog.read();
    expect(log.any((e) => e.tool == 'host_fix.restartService' && e.result.contains('boom')),
        isTrue);
  });

  testWidgets('alert with no fix shows empty state', (tester) async {
    const other = AlertEntry(
      title: '3 failed SSH logins in 24h',
      source: 'auth • web-01',
      severity: 'warning',
      serverId: 's-web-01',
      serverName: 'web-01',
    );
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => showHostFixSheet(
              context: context,
              alert: other,
              runner: (_) async => '',
              onChanged: () {},
            ),
            child: const Text('OPEN FIX'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('OPEN FIX'));
    await tester.pumpAndSettle();
    expect(find.textContaining('No one-click fix'), findsOneWidget);
    expect(find.text('CLOSE'), findsOneWidget);
  });
}
