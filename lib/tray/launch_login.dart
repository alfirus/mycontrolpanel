// SPDX-License-Identifier: MIT
/// Launch-at-login manager (Elizabeth, TM-3/TM-4 slice).
///
/// Per-user, no elevation, no secrets — ADR-003 by construction:
///
/// - Windows: `HKCU\…\Run` value (never HKLM) written via `reg add`.
/// - Linux: `~/.config/autostart/mycontrolpanel.desktop` (freedesktop).
/// - macOS: `~/Library/LaunchAgents/com.mycontrolpanel.login.plist`
///   (never `/Library/LaunchDaemons` — LaunchAgent scope, TM-3).
///
/// Artifacts carry the executable path ONLY (no flags, no tokens, no key
/// paths — pinned secret-clean in `test/tray_launch_login_test.dart`).
/// Note the login item launches the *app* (normal UI boot into the tray);
/// the OS schedulers invoke the headless tick separately via the frozen
/// `--poll-headless` argv.
///
/// Policy: the login item follows the shared `background_alerts` consent
/// (no second pref — same "no new prefs" rule as ADR-005). The tray shell
/// calls [syncWithConsent] on init and on consent change: ON ⇒ ensure the
/// item, OFF ⇒ remove it.
///
/// Pure `dart:io` behind injectable seams ([LoginItemDeps]) — tests drive
/// the manager with fake files + a fake `reg` runner, zero real I/O.
library;

import 'dart:io';

/// Result of one runner invocation (subset of `ProcessResult`).
typedef LoginCmdResult = ({int exitCode, String stdout});

/// Injectable environment for [LoginItemManager] (fake in tests).
class LoginItemDeps {
  final bool isWindows;
  final bool isLinux;
  final bool isMacOS;
  final String home;
  final String exePath;

  final Future<String?> Function(String path)? readFile;
  final Future<void> Function(String path, String contents)? writeFile;
  final Future<void> Function(String path)? deleteFile;
  final Future<LoginCmdResult> Function(String exe, List<String> args)? run;

  const LoginItemDeps({
    required this.isWindows,
    required this.isLinux,
    required this.isMacOS,
    required this.home,
    required this.exePath,
    this.readFile,
    this.writeFile,
    this.deleteFile,
    this.run,
  });

  /// Production deps (real `dart:io`). Never throws on construction.
  factory LoginItemDeps.platform({String? exePathOverride}) {
    final home = Platform.environment['HOME'] ??
        Platform.environment['USERPROFILE'] ??
        '';
    return LoginItemDeps(
      isWindows: Platform.isWindows,
      isLinux: Platform.isLinux,
      isMacOS: Platform.isMacOS,
      home: home,
      exePath: exePathOverride ?? Platform.resolvedExecutable,
      readFile: (path) async {
        try {
          final f = File(path);
          if (!f.existsSync()) return null;
          return f.readAsStringSync();
        } catch (_) {
          return null;
        }
      },
      writeFile: (path, contents) async {
        final f = File(path);
        f.parent.createSync(recursive: true);
        f.writeAsStringSync(contents);
      },
      deleteFile: (path) async {
        try {
          final f = File(path);
          if (f.existsSync()) f.deleteSync();
        } catch (_) {}
      },
      run: (exe, args) async {
        try {
          final r = await Process.run(exe, args);
          return (
            exitCode: r.exitCode,
            stdout: (r.stdout ?? '').toString(),
          );
        } catch (_) {
          return (exitCode: 1, stdout: '');
        }
      },
    );
  }
}

/// Per-user launch-at-login item (follows shared consent, no own pref).
class LoginItemManager {
  final LoginItemDeps deps;

  const LoginItemManager(this.deps);

  /// Windows Run value name (per-user hive — never HKLM).
  static const windowsRunKey =
      r'HKCU\Software\Microsoft\Windows\CurrentVersion\Run';
  static const windowsValueName = 'MyControlPanel';

  /// Linux freedesktop autostart entry.
  static const linuxFileName = 'mycontrolpanel.desktop';

  /// macOS per-user login agent (distinct from the poll plist
  /// `com.mycontrolpanel.poll` — login boots the app, the scheduler
  /// invokes the headless tick).
  static const macosLabel = 'com.mycontrolpanel.login';
  static const macosFileName = 'com.mycontrolpanel.login.plist';

  static String _join(String a, String b, String c, String sep) =>
      '$a$sep$b$sep$c';

  /// Separator for the *target* platform (tests fake other-OS homes on the
  /// CI host — never use the host separator here).
  String get _sep => deps.isWindows ? '\\' : '/';

  String get _linuxPath =>
      _join(deps.home, '.config/autostart', linuxFileName, _sep);

  String get _macosPath =>
      _join(deps.home, 'Library/LaunchAgents', macosFileName, _sep);

  /// Minimal XML escaping for plist string values (& < >).
  static String escapeXml(String s) => s
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;');

  /// Escape backslashes and double-quotes for the freedesktop Exec value
  /// (rendered inside double quotes).
  static String escapeDesktopExec(String s) =>
      s.replaceAll('\\', '\\\\').replaceAll('"', '\\"');

  /// Render the freedesktop autostart entry (pure).
  static String renderDesktopFile({required String exePath}) =>
      '[Desktop Entry]\n'
      'Type=Application\n'
      'Name=MyControlPanel\n'
      'Comment=Stay notified when the app is closed\n'
      'Exec="${escapeDesktopExec(exePath)}"\n'
      'Hidden=false\n'
      'X-GNOME-Autostart-enabled=true\n';

  /// Render the macOS login LaunchAgent (pure, per-user scope only).
  static String renderLaunchAgentPlist({required String exePath}) =>
      '<?xml version="1.0" encoding="UTF-8"?>\n'
      '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" '
      '"http://www.apple.com/DTDs/PropertyList-1.0.dtd">\n'
      '<plist version="1.0">\n'
      '<dict>\n'
      '  <key>Label</key>\n'
      '  <string>$macosLabel</string>\n'
      '  <key>ProgramArguments</key>\n'
      '  <array>\n'
      '    <string>${escapeXml(exePath)}</string>\n'
      '  </array>\n'
      '  <key>RunAtLoad</key>\n'
      '  <true/>\n'
      '</dict>\n'
      '</plist>\n';

  /// True when this manager's item is currently installed.
  Future<bool> isOn() async {
    try {
      if (deps.isWindows) {
        if (deps.run == null) return false;
        final r = await deps.run!(
            'reg', ['query', windowsRunKey, '/v', windowsValueName]);
        // _install writes the value quoted ("<exePath>"); accept the
        // quoted form plus the legacy unquoted form.
        return r.exitCode == 0 &&
            (r.stdout.contains('"${deps.exePath}"') ||
                r.stdout.contains(deps.exePath));
      }
      if (deps.isLinux) {
        final cur =
            deps.readFile == null ? null : await deps.readFile!(_linuxPath);
        return cur != null &&
            cur.contains('Exec="${escapeDesktopExec(deps.exePath)}"');
      }
      if (deps.isMacOS) {
        final cur =
            deps.readFile == null ? null : await deps.readFile!(_macosPath);
        return cur != null &&
            cur.contains('<string>${escapeXml(deps.exePath)}</string>');
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  /// Install (true) or remove (false) the login item. Never throws.
  Future<void> setEnabled(bool enabled) async {
    try {
      if (enabled) {
        await _install();
      } else {
        await _remove();
      }
    } catch (_) {}
  }

  /// Follow the shared `background_alerts` consent: ON ⇒ installed,
  /// OFF ⇒ removed. Called by the tray shell on init + consent change.
  Future<void> syncWithConsent(bool consentOn) =>
      setEnabled(consentOn);

  Future<void> _install() async {
    if (deps.isWindows) {
      if (deps.run == null) return;
      await deps.run!('reg', [
        'add',
        windowsRunKey,
        '/v',
        windowsValueName,
        '/t',
        'REG_SZ',
        '/d',
        '"${deps.exePath}"',
        '/f',
      ]);
      return;
    }
    if (deps.isLinux) {
      if (deps.writeFile == null) return;
      await deps.writeFile!(
          _linuxPath, renderDesktopFile(exePath: deps.exePath));
      return;
    }
    if (deps.isMacOS) {
      if (deps.writeFile == null) return;
      await deps.writeFile!(
          _macosPath, renderLaunchAgentPlist(exePath: deps.exePath));
    }
  }

  Future<void> _remove() async {
    if (deps.isWindows) {
      if (deps.run == null) return;
      await deps.run!('reg', [
        'delete',
        windowsRunKey,
        '/v',
        windowsValueName,
        '/f',
      ]);
      return;
    }
    if (deps.isLinux) {
      if (deps.deleteFile == null) return;
      await deps.deleteFile!(_linuxPath);
      return;
    }
    if (deps.isMacOS) {
      if (deps.deleteFile == null) return;
      await deps.deleteFile!(_macosPath);
    }
  }
}
