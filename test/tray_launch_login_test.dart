// SPDX-License-Identifier: MIT
// Launch-at-login tests (Elizabeth): per-user scope, no elevation, no
// secrets in artifacts — ADR-003 invariants for all three OS paths.
import 'package:flutter_test/flutter_test.dart';
import 'package:my_control_panel/services/headless_security.dart';
import 'package:my_control_panel/tray/launch_login.dart';

LoginItemDeps linuxDeps({
  Map<String, String>? files,
  List<List<String>>? deleted,
  List<Map<String, String>>? written,
  String exe = '/opt/mcp/mycontrolpanel',
}) =>
    LoginItemDeps(
      isWindows: false,
      isLinux: true,
      isMacOS: false,
      home: '/home/u',
      exePath: exe,
      readFile: (p) async => (files ?? {})[p],
      writeFile: (p, c) async {
        written?.add({p: c});
        (files ?? {})[p] = c;
      },
      deleteFile: (p) async {
        deleted?.add([p]);
        (files ?? {}).remove(p);
      },
    );

LoginItemDeps macDeps({
  Map<String, String>? files,
  String exe = '/Applications/MyControlPanel.app/Contents/MacOS/mycontrolpanel',
}) =>
    LoginItemDeps(
      isWindows: false,
      isLinux: false,
      isMacOS: true,
      home: '/Users/u',
      exePath: exe,
      readFile: (p) async => (files ?? {})[p],
      writeFile: (p, c) async => (files ?? {})[p] = c,
      deleteFile: (p) async => (files ?? {}).remove(p),
    );

void main() {
  group('linux autostart entry', () {
    test('render carries the exe path and nothing else sensitive', () {
      final entry = LoginItemManager.renderDesktopFile(
          exePath: '/opt/mcp/mycontrolpanel');
      expect(entry, contains('Exec="/opt/mcp/mycontrolpanel"'));
      expect(
          HeadlessSecurity.findSecretMaterialInArgs(
              entry.split('\n')),
          isEmpty);
    });

    test('install → on → remove → off round-trip', () async {
      final files = <String, String>{};
      final m = LoginItemManager(linuxDeps(files: files));
      expect(await m.isOn(), isFalse);
      await m.setEnabled(true);
      expect(await m.isOn(), isTrue);
      final path = files.keys.single;
      expect(path, contains('.config/autostart/mycontrolpanel.desktop'));
      expect(path.startsWith('/home/u/'), isTrue);
      await m.setEnabled(false);
      expect(await m.isOn(), isFalse);
      expect(files, isEmpty);
    });
  });

  group('macos login agent', () {
    test('per-user scope only, secret-clean', () async {
      final files = <String, String>{};
      const exe =
          '/Applications/MyControlPanel.app/Contents/MacOS/mycontrolpanel';
      final m = LoginItemManager(macDeps(files: files, exe: exe));
      await m.setEnabled(true);
      final path = files.keys.single;
      expect(path,
          '/Users/u/Library/LaunchAgents/com.mycontrolpanel.login.plist');
      expect(path, isNot(contains('LaunchDaemons')));
      final plist = files.values.single;
      expect(plist, contains('<string>$exe</string>'));
      expect(plist, contains('<key>RunAtLoad</key>'));
      expect(plist, isNot(contains('LaunchDaemon')));
      // Note: this login item launches the *app*, not the headless tick,
      // so the scheduler-artifact validator (which mandates the frozen
      // `--poll-headless` argv) does not apply — the per-user scope +
      // elevation + secret-clean pins above are the ADR-003 contract here.
      expect(
          HeadlessSecurity.findSecretMaterialInArgs(
              plist.split('\n')),
          isEmpty);
    });
  });

  group('windows run key', () {
    test('per-user hive only, exact reg shapes', () async {
      final calls = <List<String>>[];
      Future<LoginCmdResult> run(String exe, List<String> args) async {
        calls.add([exe, ...args]);
        if (args.first == 'query') {
          return (exitCode: 0, stdout: '    MyControlPanel    REG_SZ    C:\\mcp\\app.exe');
        }
        return (exitCode: 0, stdout: '');
      }

      const deps = LoginItemDeps(
        isWindows: true,
        isLinux: false,
        isMacOS: false,
        home: 'C:\\Users\\u',
        exePath: 'C:\\mcp\\app.exe',
      );
      final m = LoginItemManager(LoginItemDeps(
        isWindows: true,
        isLinux: false,
        isMacOS: false,
        home: 'C:\\Users\\u',
        exePath: 'C:\\mcp\\app.exe',
        run: run,
      ));
      expect(deps.home, isNotEmpty);

      await m.setEnabled(true);
      final add = calls.single;
      expect(add[0], 'reg');
      expect(add, contains('HKCU\\Software\\Microsoft\\Windows\\CurrentVersion\\Run'));
      expect(add, contains('MyControlPanel'));
      expect(add, isNot(contains('HKLM')));
      expect(
          HeadlessSecurity.findSecretMaterialInArgs(add), isEmpty);

      calls.clear();
      expect(await m.isOn(), isTrue);
      final query = calls.single;
      expect(query[1], 'query');
      expect(query, isNot(contains('HKLM')));
    });
  });

  group('consent following', () {
    test('syncWithConsent installs on ON, removes on OFF', () async {
      final files = <String, String>{};
      final m = LoginItemManager(linuxDeps(files: files));
      await m.syncWithConsent(true);
      expect(await m.isOn(), isTrue);
      await m.syncWithConsent(false);
      expect(await m.isOn(), isFalse);
    });
  });
}
