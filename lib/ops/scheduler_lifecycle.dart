// SPDX-License-Identifier: MIT
/// Managed scheduler lifecycle for the headless poll (TM-2, Zara owns).
///
/// Installs, verifies, and removes the OS scheduler artifacts that fire
/// the headless tick through `mycontrolpanel-check`, and reports fleet
/// health (`status`) with stale-run / missed-heartbeat detection.
///
/// Layering (ADR-005: on top of Lina's templates, never re-templated):
/// - Windows: starts from `scripts/headless/windows/mcp-poll-task.xml`
///   (same triggers / principals / settings); only the `<Exec>` action
///   routes through the wrapper so every firing appends a run-ledger
///   record. The embedded poll argv stays exactly `--poll-headless`.
/// - Linux: starts from `scripts/headless/linux/mcp-poll.{service,timer}`
///   (timer copied verbatim); only the service `ExecStart` routes
///   through the wrapper. Units stay per-user (`systemd --user`),
///   mode 0600, no `Environment=` secrets.
/// - macOS: Elizabeth's rail (LaunchAgent scope decision) — `install`
///   refuses with guidance; `status` reports unmanaged.
///
/// `verify` reuses [HeadlessSecurity.validateSchedulerArtifact] verbatim
/// for the final verdict, and additionally pins template fidelity: the
/// installed artifact must match the template outside the Exec action,
/// so template drift or tampering fails loudly instead of silently
/// forking the schedule.
///
/// Consent gate: `install` runs one supervised preflight tick first; a
/// consent-OFF skip (or any preflight failure) aborts the install unless
/// `--force` — a scheduler that can never fire is worse than none.
///
/// Pure `dart:io` / `dart:convert` only (see `run_ledger.dart`).
library;

import 'dart:convert';
import 'dart:io';

import 'package:my_control_panel/background/headless_state.dart';
import 'package:my_control_panel/services/headless_security.dart';

import 'check_runner.dart';
import 'run_ledger.dart';

/// Target OS for lifecycle operations (injectable for tests).
enum OpsOs { windows, linux, macos, other }

/// How `install` finds the wrapper binary.
enum WrapperSource { explicit, compiled }

OpsOs currentOpsOs() {
  if (Platform.isWindows) return OpsOs.windows;
  if (Platform.isLinux) return OpsOs.linux;
  if (Platform.isMacOS) return OpsOs.macos;
  return OpsOs.other;
}

/// Default per-user task path (Task Scheduler).
const defaultTaskPath = r'\MyControlPanel\poll-headless';

/// Default systemd user unit names.
const defaultUnitName = 'mcp-poll';

/// Stale-run threshold default: 2x the 15-minute poll interval.
const defaultStaleAfter = Duration(minutes: 30);

/// Install options. Paths [sandbox] / [unitDirOverride] redirect artifact
/// writes for CI smoke (no live scheduler touched).
class InstallOptions {
  const InstallOptions({
    required this.installDir,
    required this.wrapperPath,
    this.taskPath = defaultTaskPath,
    this.unitName = defaultUnitName,
    this.unitDirOverride,
    this.sandbox,
    this.noReload = false,
    this.force = false,
    this.preflightTimeout = const Duration(seconds: 120),
    this.os,
    this.templateDir,
    this.preflight,
    this.runCmd,
  });

  final String installDir;
  final String wrapperPath;
  final String taskPath;
  final String unitName;
  final String? unitDirOverride;
  final String? sandbox;
  final bool noReload;
  final bool force;
  final Duration preflightTimeout;
  final OpsOs? os;
  final String? templateDir;
  final Future<ProviderResult> Function()? preflight;
  final Future<ProcessResult> Function(String exe, List<String> args)? runCmd;
}

/// Outcome of one lifecycle operation.
class LifecycleResult {
  const LifecycleResult({
    required this.ok,
    required this.action,
    this.detail = '',
    this.artifactPath,
  });

  final bool ok;
  final String action;
  final String detail;
  final String? artifactPath;

  Map<String, dynamic> toJson() => {
        'version': 1,
        'tool': 'mycontrolpanel-check',
        'action': action,
        'ok': ok,
        if (detail.isNotEmpty) 'detail': detail,
        if (artifactPath != null) 'artifact': artifactPath,
      };
}

/// Scheduler + ledger health report (`status`).
class SchedulerStatus {
  const SchedulerStatus({
    required this.os,
    required this.installed,
    this.artifactDetail = '',
    this.lastRunAtMs,
    this.lastCheckMs = 0,
    required this.verdict,
    required this.missedHeartbeat,
    this.consentHint = false,
  });

  final String os;
  final bool installed;
  final String artifactDetail;
  final int? lastRunAtMs;
  final int lastCheckMs;
  final String verdict;
  final bool missedHeartbeat;
  final bool consentHint;

  Map<String, dynamic> toJson() => {
        'version': 1,
        'tool': 'mycontrolpanel-check',
        'action': 'status',
        'os': os,
        'installed': installed,
        if (artifactDetail.isNotEmpty) 'artifact': artifactDetail,
        if (lastRunAtMs != null) 'lastRunAtMs': lastRunAtMs,
        'lastCheckMs': lastCheckMs,
        'verdict': verdict,
        'missedHeartbeat': missedHeartbeat,
        'consentHint': consentHint,
      };
}

/// Managed scheduler lifecycle.
abstract class SchedulerLifecycle {
  // -- template loading -------------------------------------------------

  /// Locate the headless template dir: explicit flag → `$MCP_TEMPLATE_DIR`
  /// → `scripts/headless` under the repo root (CWD or discovery).
  static Directory resolveTemplateDir({String? override}) {
    if (override != null && override.isNotEmpty) {
      return Directory(override);
    }
    final fromEnv = Platform.environment['MCP_TEMPLATE_DIR'];
    if (fromEnv != null && fromEnv.isNotEmpty) return Directory(fromEnv);
    var dir = Directory.current;
    for (var i = 0; i < 6; i++) {
      final candidate = Directory(
          '${dir.path}${Platform.pathSeparator}scripts'
          '${Platform.pathSeparator}headless');
      if (candidate.existsSync()) return candidate;
      dir = dir.parent;
    }
    return Directory('scripts${Platform.pathSeparator}headless');
  }

  static String windowsTemplate(Directory templateDir) => File(
      '${templateDir.path}${Platform.pathSeparator}windows'
      '${Platform.pathSeparator}mcp-poll-task.xml').readAsStringSync();

  static String linuxServiceTemplate(Directory templateDir) => File(
      '${templateDir.path}${Platform.pathSeparator}linux'
      '${Platform.pathSeparator}mcp-poll.service').readAsStringSync();

  static String linuxTimerTemplate(Directory templateDir) => File(
      '${templateDir.path}${Platform.pathSeparator}linux'
      '${Platform.pathSeparator}mcp-poll.timer').readAsStringSync();

  // -- managed argv -----------------------------------------------------

  /// Managed tick argv supervised by the wrapper: the installed app
  /// binary with exactly `--poll-headless` (never extended).
  static List<String> managedTickArgs(String tickBinary) =>
      [tickBinary, headlessFlag];

  /// Managed wrapper argv embedded in the scheduler artifact.
  static List<String> managedWrapperArgs(String tickBinary) => [
        'check',
        '--tick-cmd',
        tickBinary,
        '--tick-arg',
        headlessFlag,
      ];

  // -- artifact fill ----------------------------------------------------

  static const _windowsCommandAnchor =
      '<Command>INSTALL_DIR\\mycontrolpanel.exe</Command>';
  static const _windowsArgsAnchor =
      '<Arguments>--poll-headless</Arguments>';

  /// Fill the Windows task XML: template triggers/principals/settings
  /// preserved, Exec action routed through the wrapper. Throws
  /// [StateError] when the template anchors move (fail loud on drift).
  ///
  /// The template's header comment is dropped in the managed artifact:
  /// it names `--poll-headless`, and a double hyphen is illegal inside
  /// an XML comment — schtasks rejects the pristine template with
  /// `(11,63): incorrect comment syntax` (reproducible with
  /// `schtasks /Create` on the unmodified template; Lina's manual
  /// path via install-windows.ps1 hits the same wall — follow-up
  /// filed on her card). Comments carry no schedule semantics, so the
  /// managed artifact stays a faithful copy otherwise.
  static String fillWindowsTask({
    required String template,
    required String wrapperExe,
    required String tickBinary,
  }) {
    final uncommented = _stripXmlComments(template);
    if (!uncommented.contains(_windowsCommandAnchor) ||
        !uncommented.contains(_windowsArgsAnchor)) {
      throw StateError(
          'windows task template drifted (Exec anchors not found) — '
          'refusing to fork the schedule; sync with Lina\'s template');
    }
    final args =
        managedWrapperArgs(tickBinary).map(_xmlEscape).join(' ');
    final filled = uncommented
        .replaceFirst(
            _windowsCommandAnchor, '<Command>${_xmlEscape(wrapperExe)}</Command>')
        .replaceFirst(
            _windowsArgsAnchor, '<Arguments>$args</Arguments>');
    // schtasks on current Windows images rejects <AllowDemandStart>
    // inside <Settings> outright (bisected on CI: identical artifacts
    // register without it, fail with it in any position). The element
    // defaults to true when omitted, so demand-start (`schtasks /Run`)
    // keeps working; only the explicit line is dropped.
    return _dropAllowDemandStart(filled);
  }

  static String _dropAllowDemandStart(String xml) =>
      const LineSplitter()
          .convert(xml)
          .where((l) => !l.contains('<AllowDemandStart>'))
          .join('\n');

  static const _linuxExecAnchorPrefix = 'ExecStart=';

  /// Fill the systemd service: timer is copied verbatim by the caller;
  /// only ExecStart routes through the wrapper. Throws on drift.
  static String fillLinuxService({
    required String template,
    required String wrapperExe,
    required String tickBinary,
  }) {
    final lines = const LineSplitter().convert(template);
    final idx = lines.indexWhere(
        (l) => l.startsWith(_linuxExecAnchorPrefix));
    if (idx < 0) {
      throw StateError(
          'linux service template drifted (ExecStart not found) — '
          'refusing to fork the schedule; sync with Lina\'s template');
    }
    final exec =
        'ExecStart=$wrapperExe ${managedWrapperArgs(tickBinary).join(' ')}';
    final out = List<String>.of(lines);
    out[idx] = exec;
    return '${out.join('\n')}\n';
  }

  // -- install ----------------------------------------------------------

  static String defaultTickBinary(String installDir, OpsOs os) {
    if (os == OpsOs.windows) return '$installDir\\mycontrolpanel.exe';
    return '$installDir/mycontrolpanel';
  }

  static Directory defaultUnitDir() {
    final home = Platform.environment['HOME'] ?? '';
    return Directory('$home/.config/systemd/user');
  }

  /// Consent-gated install. Runs a preflight supervised tick; aborts on
  /// consent-OFF or preflight failure unless [options.force].
  static Future<LifecycleResult> install(InstallOptions options) async {
    final os = options.os ?? currentOpsOs();
    if (os == OpsOs.macos) {
      return const LifecycleResult(
        ok: false,
        action: 'install',
        detail: 'macOS LaunchAgent scope is Elizabeth\'s rail '
            '(t_a0fe4895); use docs/runbooks/headless-manual-install.md '
            'until the menu-bar helper lands',
      );
    }
    if (os == OpsOs.other) {
      return const LifecycleResult(
          ok: false, action: 'install', detail: 'unsupported OS');
    }

    final run = options.runCmd ?? _defaultRunCmd;
    final templateDir =
        resolveTemplateDir(override: options.templateDir);
    final tickBinary = defaultTickBinary(options.installDir, os);

    // Consent gate: one supervised preflight tick with the exact argv
    // the scheduler would fire.
    ProviderResult preflight;
    try {
      preflight = options.preflight != null
          ? await options.preflight!()
          : await CheckRunner.spawnProvider(
              tickBinary,
              [headlessFlag],
              options.preflightTimeout,
            );
    } catch (e) {
      preflight = ProviderResult(
          exitCode: 1,
          stdout: '',
          stderr: '$e',
          durationMs: 0);
    }
    if (!options.force && _preflightBlocks(preflight)) {
      return LifecycleResult(
        ok: false,
        action: 'install',
        detail: 'preflight tick refused install: ${_preflightWhy(preflight)} '
            '(enable Settings → background alerts first, or re-run with --force)',
      );
    }

    try {
      if (os == OpsOs.windows) {
        final template = windowsTemplate(templateDir);
        final filled = fillWindowsTask(
          template: template,
          wrapperExe: options.wrapperPath,
          tickBinary: tickBinary,
        );
        final artifact = await _installWindows(
            options, filled, runCmd: run);
        return LifecycleResult(
            ok: true,
            action: 'install',
            detail: 'per-user task ${options.taskPath} '
                'fires wrapper → $tickBinary $headlessFlag',
            artifactPath: artifact);
      } else {
        final serviceTpl = linuxServiceTemplate(templateDir);
        final timerTpl = linuxTimerTemplate(templateDir);
        final filled = fillLinuxService(
          template: serviceTpl,
          wrapperExe: options.wrapperPath,
          tickBinary: tickBinary,
        );
        final artifact = await _installLinux(
            options, filled, timerTpl,
            runCmd: run);
        return LifecycleResult(
            ok: true,
            action: 'install',
            detail: 'user timer ${options.unitName}.timer '
                'fires wrapper → $tickBinary $headlessFlag',
            artifactPath: artifact);
      }
    } catch (e) {
      return LifecycleResult(
          ok: false, action: 'install', detail: 'install failed: $e');
    }
  }

  static bool _preflightBlocks(ProviderResult preflight) {
    if (preflight.exitCode == 0) return false;
    return true;
  }

  static String _preflightWhy(ProviderResult preflight) {
    final tick = CheckRunner.parseTickJson(preflight.stdout);
    final reason = tick?.reason ?? preflight.stderr;
    if (reason.trim().isEmpty) {
      return 'provider exit ${preflight.exitCode} with no reason';
    }
    final preview = reason.replaceAll(RegExp(r'\s+'), ' ').trim();
    return preview.length <= 200
        ? preview
        : preview.substring(0, 200);
  }

  static Future<String> _installWindows(
    InstallOptions options,
    String filled, {
    required Future<ProcessResult> Function(String exe, List<String> args)
        runCmd,
  }) async {
    if (options.sandbox != null) {
      final file = File(
          '${options.sandbox}${Platform.pathSeparator}mcp-poll-task.xml');
      writeTaskXml(file, filled);
      return file.path;
    }
    final tmp = File(
        '${Directory.systemTemp.path}${Platform.pathSeparator}'
        'mcp-poll-task-${DateTime.now().millisecondsSinceEpoch}.xml');
    writeTaskXml(tmp, filled);
    try {
      final result = await runCmd(
          'schtasks', ['/Create', '/TN', options.taskPath, '/XML', tmp.path, '/F']);
      if (result.exitCode != 0) {
        throw StateError(
            'schtasks /Create failed: ${result.stderr.toString().trim()}');
      }
    } finally {
      try {
        tmp.deleteSync();
      } catch (_) {}
    }
    return 'schtasks:${options.taskPath}';
  }

  static Future<String> _installLinux(
    InstallOptions options,
    String filledService,
    String timerTemplate, {
    required Future<ProcessResult> Function(String exe, List<String> args)
        runCmd,
  }) async {
    final unitDir = options.sandbox != null
        ? Directory(options.sandbox!)
        : (options.unitDirOverride != null
            ? Directory(options.unitDirOverride!)
            : defaultUnitDir());
    unitDir.createSync(recursive: true);
    final sep = Platform.pathSeparator;
    final service = File('${unitDir.path}${sep}${options.unitName}.service');
    final timer = File('${unitDir.path}${sep}${options.unitName}.timer');
    service.writeAsStringSync(filledService);
    timer.writeAsStringSync(timerTemplate);
    if (!Platform.isWindows) {
      try {
        Process.runSync('chmod', ['0600', service.path]);
        Process.runSync('chmod', ['0600', timer.path]);
      } catch (_) {}
    }
    if (options.sandbox == null && !options.noReload) {
      final reload = await runCmd(
          'systemctl', ['--user', 'daemon-reload']);
      if (reload.exitCode != 0) {
        throw StateError(
            'systemctl --user daemon-reload failed: ${reload.stderr.toString().trim()}');
      }
      final enable = await runCmd(
          'systemctl', ['--user', 'enable', '--now', '${options.unitName}.timer']);
      if (enable.exitCode != 0) {
        throw StateError(
            'systemctl enable failed: ${enable.stderr.toString().trim()}');
      }
    }
    return service.path;
  }

  // -- uninstall --------------------------------------------------------

  static Future<LifecycleResult> uninstall({
    String taskPath = defaultTaskPath,
    String unitName = defaultUnitName,
    String? unitDirOverride,
    String? sandbox,
    bool noReload = false,
    OpsOs? os,
    Future<ProcessResult> Function(String exe, List<String> args)? runCmd,
  }) async {
    final thisOs = os ?? currentOpsOs();
    final run = runCmd ?? _defaultRunCmd;
    try {
      if (thisOs == OpsOs.windows) {
        if (sandbox != null) {
          final file = File(
              '$sandbox${Platform.pathSeparator}mcp-poll-task.xml');
          if (file.existsSync()) file.deleteSync();
          return LifecycleResult(
              ok: true,
              action: 'uninstall',
              detail: 'sandbox artifact removed',
              artifactPath: file.path);
        }
        final result = await run(
            'schtasks', ['/Delete', '/TN', taskPath, '/F']);
        if (result.exitCode != 0) {
          return LifecycleResult(
              ok: false,
              action: 'uninstall',
              detail:
                  'schtasks /Delete failed: ${result.stderr.toString().trim()}');
        }
        return const LifecycleResult(
            ok: true, action: 'uninstall', detail: 'task deleted');
      } else if (thisOs == OpsOs.linux) {
        final unitDir = sandbox != null
            ? Directory(sandbox)
            : (unitDirOverride != null
                ? Directory(unitDirOverride)
                : defaultUnitDir());
        final sep = Platform.pathSeparator;
        if (sandbox == null && !noReload) {
          await run('systemctl', [
            '--user',
            'disable',
            '--now',
            '$unitName.timer'
          ]);
        }
        for (final name in ['$unitName.service', '$unitName.timer']) {
          final file = File('${unitDir.path}$sep$name');
          if (file.existsSync()) file.deleteSync();
        }
        if (sandbox == null && !noReload) {
          await run('systemctl', ['--user', 'daemon-reload']);
        }
        return const LifecycleResult(
            ok: true, action: 'uninstall', detail: 'user units removed');
      }
      return const LifecycleResult(
          ok: false, action: 'uninstall', detail: 'unsupported OS');
    } catch (e) {
      return LifecycleResult(
          ok: false, action: 'uninstall', detail: 'uninstall failed: $e');
    }
  }

  // -- verify -----------------------------------------------------------

  /// Verify a filled/installed Windows task XML string.
  /// Returns violations (empty = clean), reusing Lina's validator.
  static List<String> verifyWindowsXml({
    required String xml,
    required String taskPath,
  }) {
    final violations = <String>[];
    final command = _extractTag(xml, 'Command');
    final argsText = _extractTag(xml, 'Arguments');
    if (command == null || argsText == null) {
      return ['windowsTaskScheduler: task XML has no Exec Command/Arguments'];
    }
    final tokens = _splitArgs(argsText);
    final invokesFlag = tokens.contains(headlessFlag);
    final perUser =
        taskPath.startsWith(r'\MyControlPanel\');
    final elevated = xml.contains('HighestAvailable');
    violations.addAll(HeadlessSecurity.validateSchedulerArtifact(
      kind: SchedulerKind.windowsTaskScheduler,
      perUserScope: perUser,
      runsElevated: elevated,
      args: [command, ...tokens],
      invokesHeadlessFlag: invokesFlag,
    ));
    if (!xml.contains('InteractiveToken')) {
      violations.add('windowsTaskScheduler: principal must use '
          'InteractiveToken logon (per-user, no stored password)');
    }
    if (!xml.contains('LeastPrivilege')) {
      violations.add('windowsTaskScheduler: principal must use '
          'LeastPrivilege run level (no elevation)');
    }
    return violations;
  }

  /// Verify a filled/installed systemd service string (+ timer fidelity).
  static List<String> verifyLinuxService({
    required String service,
    required String timer,
    required String timerTemplate,
    required String unitPath,
    bool sandbox = false,
  }) {
    final violations = <String>[];
    final execLine = const LineSplitter()
        .convert(service)
        .where((l) => l.startsWith(_linuxExecAnchorPrefix))
        .toList();
    if (execLine.length != 1) {
      return ['systemdUserTimer: service must carry exactly one ExecStart'];
    }
    final tokens = _splitArgs(
        execLine.single.substring(_linuxExecAnchorPrefix.length));
    violations.addAll(HeadlessSecurity.validateSchedulerArtifact(
      kind: SchedulerKind.systemdUserTimer,
      // Sandbox installs are CI test-doubles for the per-user unit dir.
      perUserScope:
          sandbox || unitPath.contains('.config/systemd/user'),
      runsElevated: service.contains('User=root') ||
          service.contains('User=0'),
      args: tokens,
      invokesHeadlessFlag: tokens.contains(headlessFlag),
    ));
    for (final line in const LineSplitter().convert(service)) {
      if (line.startsWith('Environment=')) {
        violations.add('systemdUserTimer: service must not carry '
            'Environment= secrets (vault-only reads inside the tick)');
      }
    }
    if (timer != timerTemplate) {
      violations.add('systemdUserTimer: timer unit drifted from '
          'scripts/headless/linux/mcp-poll.timer');
    }
    return violations;
  }

  /// Template fidelity for Windows: installed XML must equal the template
  /// outside the Exec Command/Arguments lines. Normalized away on both
  /// sides (see [fillWindowsTask]): the template's header comment (its
  /// `--poll-headless` text is illegal inside an XML comment) and the
  /// `<AllowDemandStart>` line (rejected by current schtasks parsers;
  /// defaults to true when omitted).
  static bool windowsMatchesTemplateExceptExec(
      String installed, String template) {
    String strip(String xml) => const LineSplitter()
        .convert(
            _dropAllowDemandStart(_stripXmlComments(xml)))
        .where((l) =>
            !l.contains('<Command>') && !l.contains('<Arguments>'))
        .join('\n');
    return strip(installed) == strip(template);
  }

  static String _stripXmlComments(String xml) =>
      xml.replaceAll(RegExp(r'<!--.*?-->', dotAll: true), '');

  // -- status -----------------------------------------------------------

  static Future<SchedulerStatus> status({
    String taskPath = defaultTaskPath,
    String unitName = defaultUnitName,
    String? unitDirOverride,
    String? sandbox,
    Directory? stateDir,
    Duration staleAfter = defaultStaleAfter,
    OpsOs? os,
    DateTime? now,
    Future<ProcessResult> Function(String exe, List<String> args)? runCmd,
  }) async {
    final thisOs = os ?? currentOpsOs();
    final run = runCmd ?? _defaultRunCmd;
    final at = now ?? DateTime.now();
    final dir = stateDir ?? HeadlessPaths.stateDir();
    final ledgerFile = RunLedger.ledgerFile(dir);
    final stateFile = HeadlessPaths.stateFile(dir);

    var installed = false;
    var artifact = '';
    if (thisOs == OpsOs.windows) {
      if (sandbox != null) {
        final file = File(
            '$sandbox${Platform.pathSeparator}mcp-poll-task.xml');
        installed = file.existsSync();
        artifact = installed ? file.path : '';
      } else {
        try {
          final result = await run(
              'schtasks', ['/Query', '/TN', taskPath]);
          installed = result.exitCode == 0;
          artifact = installed ? 'schtasks:$taskPath' : '';
        } catch (_) {
          installed = false;
        }
      }
    } else if (thisOs == OpsOs.linux) {
      final unitDir = sandbox != null
          ? Directory(sandbox)
          : (unitDirOverride != null
              ? Directory(unitDirOverride)
              : defaultUnitDir());
      final sep = Platform.pathSeparator;
      final svc =
          File('${unitDir.path}$sep$unitName.service').existsSync();
      final tmr = File('${unitDir.path}$sep$unitName.timer').existsSync();
      installed = svc && tmr;
      artifact = installed ? unitDir.path : '';
    } else {
      artifact = 'unmanaged on this OS rail';
    }

    final latest = RunLedger.latest(ledgerFile);
    final lastRunAtMs = (latest?['atMs'] as int?);
    final stored = HeadlessState.load(stateFile);

    final verdict = _verdict(
        lastRunAtMs: lastRunAtMs, nowMs: at.millisecondsSinceEpoch, staleAfter: staleAfter);
    final missed = installed &&
        (verdict == 'stale' || verdict == 'never-ran');
    final reason = latest?['reason']?.toString() ?? '';
    final consentHint = reason.toLowerCase().contains('consent');

    return SchedulerStatus(
      os: thisOs.name,
      installed: installed,
      artifactDetail: artifact,
      lastRunAtMs: lastRunAtMs,
      lastCheckMs: stored.lastCheckMs,
      verdict: verdict,
      missedHeartbeat: missed,
      consentHint: consentHint,
    );
  }

  static String _verdict({
    required int? lastRunAtMs,
    required int nowMs,
    required Duration staleAfter,
  }) {
    if (lastRunAtMs == null || lastRunAtMs <= 0) return 'never-ran';
    if (nowMs - lastRunAtMs > staleAfter.inMilliseconds) return 'stale';
    return 'fresh';
  }

  // -- helpers ----------------------------------------------------------

  /// Write a Task Scheduler XML file in the encoding its declaration
  /// demands (Lina's template declares UTF-16; schtasks rejects a
  /// UTF-8 body under that declaration). Sandbox artifacts use the
  /// same encoding so smoke verifies the real bytes.
  static void writeTaskXml(File file, String content) {
    final bytes = <int>[0xFF, 0xFE];
    for (final unit in content.codeUnits) {
      bytes.add(unit & 0xFF);
      bytes.add((unit >> 8) & 0xFF);
    }
    file.parent.createSync(recursive: true);
    file.writeAsBytesSync(bytes);
  }

  /// Read a Task Scheduler XML file, honoring a UTF-16 BOM when present
  /// (what [writeTaskXml] and `schtasks /Query /XML` produce).
  static String readTaskXml(File file) {
    final bytes = file.readAsBytesSync();
    if (bytes.length >= 2 && bytes[0] == 0xFF && bytes[1] == 0xFE) {
      final units = <int>[];
      for (var i = 2; i + 1 < bytes.length; i += 2) {
        units.add(bytes[i] | (bytes[i + 1] << 8));
      }
      return String.fromCharCodes(units);
    }
    return const Utf8Decoder().convert(bytes);
  }

  static Future<ProcessResult> _defaultRunCmd(
      String exe, List<String> args) async {
    final result =
        await Process.run(exe, args, runInShell: Platform.isWindows);
    return result;
  }

  static String? _extractTag(String xml, String tag) {
    final match =
        RegExp('<$tag>(.*?)</$tag>', dotAll: true).firstMatch(xml);
    return match?.group(1)?.trim();
  }

  /// Minimal argv splitter honoring double quotes (scheduler XML and
  /// systemd ExecStart both quote paths with spaces).
  static List<String> _splitArgs(String text) {
    final out = <String>[];
    final buf = StringBuffer();
    var inQuotes = false;
    for (var i = 0; i < text.length; i++) {
      final ch = text[i];
      if (ch == '"') {
        inQuotes = !inQuotes;
        continue;
      }
      if ((ch == ' ' || ch == '\t') && !inQuotes) {
        if (buf.isNotEmpty) {
          out.add(buf.toString());
          buf.clear();
        }
        continue;
      }
      buf.write(ch);
    }
    if (buf.isNotEmpty) out.add(buf.toString());
    return out;
  }

  static String _xmlEscape(String s) => s
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;');
}
