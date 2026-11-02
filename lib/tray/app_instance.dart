// SPDX-License-Identifier: MIT
/// Single-instance guard for the desktop app (Elizabeth, TM-3/TM-4).
///
/// Kira's `docs/design/06-alert-tray-ux.md` §7.4: tray `Open` / toast tap
/// restores the *existing* window — never a second window. This guard runs
/// in `main()` AFTER the `--poll-headless` gate (scheduled ticks must never
/// be blocked by it) and BEFORE any window shows:
///
/// - First launch: acquires the guard → caller proceeds, and arms a
///   loopback listener so a later launch can ask it to restore the window.
/// - Second launch: the guard is held → caller signals the running
///   instance over loopback, then exits (outcome [AppInstanceOutcome
///   .secondarySignaled]) — exactly one window, ever.
///
/// Pure `dart:io` (no plugins): an exclusive file lock proves liveness
/// (OS releases it on crash — no stale-lock wedge), a loopback TCP
/// handshake carries the restore signal, and an in-process held-set closes
/// the same-process double-acquire hole (same pattern as `HeadlessLock`).
/// [directory] + timeouts are injectable so tests drive two guards in one
/// process with zero real I/O outside a temp dir.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Outcome of [AppInstanceGuard.tryAcquire].
enum AppInstanceOutcome {
  /// This launch owns the instance — proceed and serve restore signals.
  primary,

  /// Another instance holds the guard; it was asked to restore its
  /// window — the caller must exit.
  secondarySignaled,
}

/// Single-instance guard (one live owner per user state dir).
class AppInstanceGuard {
  AppInstanceGuard._(this._server, this._lockRaf, this._key);

  final ServerSocket _server;
  final RandomAccessFile _lockRaf;
  final String _key;
  bool _released = false;

  static const _lockFileName = 'app_instance.lock';
  static const _portFileName = 'app_instance.port';
  static const _restoreLine = 'show\n';

  static final Set<String> _held = {};

  /// Callback the primary serves when a second launch asks for restore.
  void Function()? onRestoreRequested;

  /// Try to become the primary instance.
  ///
  /// - [directory]: per-user state dir (same resolution as
  ///   `HeadlessPaths.stateDir` — caller passes it in).
  /// - [acquireTimeout]: how long to wait on a contended OS lock before
  ///   concluding another *live* instance holds it.
  /// - [signalTimeout]: how long a secondary waits for the restore
  ///   handshake before exiting anyway (never blocks the caller).
  static Future<(AppInstanceOutcome, AppInstanceGuard?)> tryAcquire({
    required Directory directory,
    void Function()? onRestoreRequested,
    Duration acquireTimeout = const Duration(seconds: 5),
    Duration signalTimeout = const Duration(seconds: 3),
  }) async {
    final key = directory.absolute.path;
    if (_held.contains(key)) {
      // Same-process double-run: this process already owns the guard, so
      // ask the live primary (us) to restore and behave as a secondary.
      // Signaling still goes over loopback so the restore path is
      // exercised identically — and covered by tests in one process.
      await _signalPrimary(directory, signalTimeout);
      return (AppInstanceOutcome.secondarySignaled, null);
    }
    RandomAccessFile? raf;
    try {
      directory.createSync(recursive: true);
      final lockFile =
          File('${directory.path}${Platform.pathSeparator}$_lockFileName');
      raf = lockFile.openSync(mode: FileMode.write);
      try {
        await raf.lock(FileLock.exclusive).timeout(acquireTimeout);
      } on TimeoutException {
        try {
          raf.closeSync();
        } catch (_) {}
        await _signalPrimary(directory, signalTimeout);
        return (AppInstanceOutcome.secondarySignaled, null);
      }
      if (_held.contains(key)) {
        try {
          await raf.unlock();
        } catch (_) {}
        try {
          raf.closeSync();
        } catch (_) {}
        await _signalPrimary(directory, signalTimeout);
        return (AppInstanceOutcome.secondarySignaled, null);
      }
      // Primary: serve restore signals on an ephemeral loopback port.
      final server =
          await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final guard = AppInstanceGuard._(server, raf, key);
      guard.onRestoreRequested = onRestoreRequested;
      _held.add(key);
      try {
        final portFile =
            File('${directory.path}${Platform.pathSeparator}$_portFileName');
        portFile.writeAsStringSync('${server.port}');
      } catch (_) {}
      server.listen((socket) {
        socket
            .cast<List<int>>()
            .transform(utf8.decoder)
            .listen((_) {}, onDone: () {
          try {
            guard.onRestoreRequested?.call();
          } catch (_) {}
          try {
            socket.destroy();
          } catch (_) {}
        });
      });
      return (AppInstanceOutcome.primary, guard);
    } catch (_) {
      try {
        raf?.closeSync();
      } catch (_) {}
      // Fail closed: an unprovable state must not spawn a second window.
      return (AppInstanceOutcome.secondarySignaled, null);
    }
  }

  /// Ask the live primary to restore its window (best-effort, timeout).
  static Future<void> _signalPrimary(
    Directory directory,
    Duration timeout,
  ) async {
    try {
      final portFile =
          File('${directory.path}${Platform.pathSeparator}$_portFileName');
      if (!portFile.existsSync()) return;
      final port = int.tryParse(portFile.readAsStringSync().trim());
      if (port == null) return;
      final socket = await Socket.connect(
        InternetAddress.loopbackIPv4,
        port,
        timeout: timeout,
      );
      try {
        socket.write(_restoreLine);
        await socket.flush().timeout(timeout);
      } catch (_) {}
      try {
        await socket.close().timeout(timeout);
      } catch (_) {}
    } catch (_) {}
  }

  /// Release the guard (app shutdown). Never throws.
  Future<void> release() async {
    if (_released) return;
    _released = true;
    _held.remove(_key);
    try {
      await _server.close();
    } catch (_) {}
    try {
      await _lockRaf.unlock();
    } catch (_) {}
    try {
      _lockRaf.closeSync();
    } catch (_) {}
  }
}
