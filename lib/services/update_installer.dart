import 'dart:io';

/// Platform install step. Windows/Linux: swap files + relaunch automatically.
/// macOS (sandboxed): reveal the new .app in Finder for drag-to-/Applications.
class UpdateInstaller {
  /// Apply an already-extracted update. Returns a human message for the UI.
  /// On Windows/Linux this function does not return — the app exits.
  static Future<String> apply(Directory extractedDir) async {
    if (Platform.isWindows) return _applyWindows(extractedDir);
    if (Platform.isLinux) return _applyLinux(extractedDir);
    if (Platform.isMacOS) return _applyMacos(extractedDir);
    return 'Auto-install is not supported on this platform — install from the downloaded file manually.';
  }

  static String _appDir() => File(Platform.resolvedExecutable).parent.path;
  static String _exeName() => File(Platform.resolvedExecutable).uri.pathSegments.last;

  static Future<String> _applyWindows(Directory src) async {
    final appDir = _appDir();
    final exe = _exeName();
    final bat = File('${Directory.systemTemp.path}/mcp-update-${DateTime.now().millisecondsSinceEpoch}.bat');
    await bat.writeAsString('@echo off\r\n'
        'timeout /t 2 /nobreak >nul\r\n'
        'xcopy "${src.path}" "$appDir" /E /Y /Q\r\n'
        'start "" "$appDir\\$exe"\r\n'
        'rmdir /S /Q "${src.path}"\r\n'
        'del "%~f0"\r\n');
    await Process.start('cmd', ['/c', 'start', '/min', '', bat.path], runInShell: true, mode: ProcessStartMode.detached);
    await Future.delayed(const Duration(seconds: 1));
    exit(0);
  }

  static Future<String> _applyLinux(Directory src) async {
    final appDir = _appDir();
    final exe = _exeName();
    final sh = File('${Directory.systemTemp.path}/mcp-update-${DateTime.now().millisecondsSinceEpoch}.sh');
    await sh.writeAsString('#!/bin/sh\n'
        'sleep 2\n'
        'cp -rf "${src.path}/." "$appDir/"\n'
        'chmod +x "$appDir/$exe"\n'
        'nohup "$appDir/$exe" >/dev/null 2>&1 &\n'
        'rm -rf "${src.path}"\n'
        'rm -- "\$0"\n');
    await Process.run('chmod', ['+x', sh.path]);
    await Process.start('sh', [sh.path], mode: ProcessStartMode.detached);
    await Future.delayed(const Duration(seconds: 1));
    exit(0);
  }

  static Future<String> _applyMacos(Directory src) async {
    // Find the .app bundle inside the extracted dir.
    String? appPath;
    await for (final e in src.list(recursive: true)) {
      if (e.path.endsWith('.app') && e is Directory) {
        appPath = e.path;
        break;
      }
    }
    if (appPath == null) {
      await Process.run('open', [src.path]);
      return 'Extracted — but no .app found. Open the folder and install manually.';
    }
    // Sandboxed apps cannot write /Applications: reveal + guided install.
    await Process.run('open', ['-R', appPath]);
    return 'New version revealed in Finder.\n\n'
        'To finish:\n'
        '1. Quit MyControlPanel (this app)\n'
        '2. Drag the new .app to /Applications (replace)\n'
        '3. Reopen it from /Applications or Spotlight';
  }
}
