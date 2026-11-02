// SPDX-License-Identifier: MIT
/// mcpoll CLI configuration (Lisa, TM-1 follow-up).
///
/// Pure Dart (`dart:core`/`dart:io`/`dart:convert` only) so both the
/// shipped `bin/mcpoll.dart` entry-point and `flutter test` share this
/// file verbatim. No vault, no prefs plugins, no secrets on argv: per-host
/// agent tokens are resolved from the environment at fetch time (see
/// `snapshot_fetch.dart`), never from flags or the servers file.
library;

import 'dart:convert';
import 'dart:io';

/// One polled host: routable facts only — never credentials.
class McpollHost {
  const McpollHost({
    required this.id,
    required this.name,
    required this.host,
    this.port = 9108,
    this.tokenEnv,
  });

  final String id;
  final String name;
  final String host;
  final int port;

  /// Environment variable holding this host's agent token (optional).
  /// Falls back to `defaultTokenEnv` when null.
  final String? tokenEnv;

  static McpollHost fromJson(Map json) {
    final host = (json['host'] ?? '').toString().trim();
    if (host.isEmpty) {
      throw McpollArgError('servers file: every entry needs a "host"');
    }
    final id = (json['id'] ?? host).toString().trim();
    final name = (json['name'] ?? id).toString().trim();
    var port = 9108;
    final rawPort = json['port'];
    if (rawPort is num && rawPort.toInt() > 0 && rawPort.toInt() <= 65535) {
      port = rawPort.toInt();
    }
    final tokenEnv = json['tokenEnv']?.toString().trim();
    return McpollHost(
      id: id.isEmpty ? host : id,
      name: name.isEmpty ? host : name,
      host: host,
      port: port,
      tokenEnv: (tokenEnv == null || tokenEnv.isEmpty) ? null : tokenEnv,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'host': host,
        'port': port,
        if (tokenEnv != null) 'tokenEnv': tokenEnv,
      };
}

/// Parsed `mcpoll` invocation.
class McpollConfig {
  const McpollConfig({
    required this.consent,
    required this.hosts,
    this.stateDirOverride,
    this.timeout = const Duration(seconds: 15),
    this.maxHosts = 10,
    this.noSnapshot = false,
  });

  /// Explicit operator consent (`--consent`). Absent → exit 2, no polling.
  final bool consent;
  final List<McpollHost> hosts;
  final String? stateDirOverride;
  final Duration timeout;
  final int maxHosts;
  final bool noSnapshot;

  static const defaultTokenEnv = 'MCP_AGENT_TOKEN';
}

/// Usage-line error (exit 1, never a JSON tick).
class McpollArgError implements Exception {
  McpollArgError(this.message);
  final String message;

  @override
  String toString() => 'mcpoll: $message';
}

/// Usage text printed for `--help` and on arg errors.
String mcpollUsage() => '''
mcpoll — headless agent poller CLI (Lisa, TM-1 follow-up).

Polls agent :9108 endpoints (snapshot-first, metrics/sysstats fallback),
evaluates with the frozen headless pipeline, prints one JSON line, exits.
No UI, no vault, no prefs: consent is the explicit --consent flag and
agent tokens come from the environment, never argv.

Usage:
  dart run my_control_panel:mcpoll --consent (--host H | --servers FILE)
    [--name NAME] [--port 9108] [--id ID] [--token-env VAR]
    [--state-dir DIR] [--timeout-secs 15] [--max-hosts 10]
    [--no-snapshot] [--help]

Flags:
  --consent            Operator consent for this tick (required to poll).
  --host H             Single-host mode: poll one agent host.
  --servers FILE       JSON array of {id, name, host, port?, tokenEnv?}.
  --name NAME          Display name (single-host mode, default: host).
  --port P             Agent port (single-host mode, default 9108).
  --id ID              Stable host id (single-host mode, default: host).
  --token-env VAR      Env var holding the agent token
                       (default MCP_AGENT_TOKEN; per-host tokenEnv in FILE
                       overrides this for that host).
  --state-dir DIR      State dir override (default: MCP_STATE_DIR or the
                       per-user HeadlessPaths default).
  --timeout-secs S     Per-host fetch timeout, 1..60 (default 15).
  --max-hosts N        Host cap per tick, 1..10 (default 10).
  --no-snapshot        Skip /alerts/snapshot, use the legacy
                       /metrics + /sysstats pair (compat check).
  --help, -h           This text (exit 0).

Exit codes (TM-1 frozen table): 0 tick ok, 2 skipped (no --consent or no
host answered on a skipped path), 1 error. Stdout is the versioned JSON
tick line (titles only, never credentials).
''';

/// Parse argv into a config. Throws [McpollArgError] on misuse.
McpollConfig parseMcpollArgs(List<String> args) {
  var consent = false;
  String? serversPath;
  String? singleHost;
  String? name;
  String? id;
  int port = 9108;
  String? tokenEnv;
  String? stateDir;
  var timeoutSecs = 15;
  var maxHosts = 10;
  var noSnapshot = false;

  String flagValue(String flag, List<String> argv) {
    final i = argv.indexOf(flag);
    if (i == -1 || i + 1 >= argv.length) {
      throw McpollArgError('flag $flag needs a value');
    }
    return argv[i + 1];
  }

  int flagInt(String flag, String raw, int min, int max, int fallback) {
    final v = int.tryParse(raw);
    if (v == null || v < min || v > max) {
      throw McpollArgError(
          'flag $flag needs an integer $min..$max (got "$raw")');
    }
    return v;
  }

  for (final a in args) {
    if (a == '--consent') {
      consent = true;
    } else if (a == '--no-snapshot') {
      noSnapshot = true;
    } else if (a == '--help' || a == '-h') {
      throw McpollHelp();
    }
  }
  if (args.contains('--servers')) {
    serversPath =
        flagValue('--servers', args);
  }
  if (args.contains('--host')) {
    singleHost = flagValue('--host', args).trim();
    if (singleHost.isEmpty) throw McpollArgError('--host needs a hostname');
  }
  if (args.contains('--name')) name = flagValue('--name', args);
  if (args.contains('--id')) id = flagValue('--id', args);
  if (args.contains('--port')) {
    port = flagInt('--port', flagValue('--port', args), 1, 65535, 9108);
  }
  if (args.contains('--token-env')) {
    tokenEnv = flagValue('--token-env', args).trim();
    if (tokenEnv.isEmpty) throw McpollArgError('--token-env needs a name');
  }
  if (args.contains('--state-dir')) {
    stateDir = flagValue('--state-dir', args);
    if (stateDir.trim().isEmpty) {
      throw McpollArgError('--state-dir needs a path');
    }
  }
  if (args.contains('--timeout-secs')) {
    timeoutSecs = flagInt(
        '--timeout-secs', flagValue('--timeout-secs', args), 1, 60, 15);
  }
  if (args.contains('--max-hosts')) {
    maxHosts =
        flagInt('--max-hosts', flagValue('--max-hosts', args), 1, 10, 10);
  }

  final hosts = <McpollHost>[];
  if (serversPath != null) hosts.addAll(loadServersFile(serversPath));
  if (singleHost != null) {
    hosts.add(McpollHost(
      id: (id ?? singleHost).trim(),
      name: (name ?? id ?? singleHost).trim(),
      host: singleHost,
      port: port,
      tokenEnv: tokenEnv,
    ));
  }
  if (hosts.isEmpty) {
    throw McpollArgError('pass --host H or --servers FILE (nothing to poll)');
  }
  return McpollConfig(
    consent: consent,
    hosts: hosts,
    stateDirOverride: stateDir,
    timeout: Duration(seconds: timeoutSecs),
    maxHosts: maxHosts,
    noSnapshot: noSnapshot,
  );
}

/// `--help` is not an error: prints usage, exits 0.
class McpollHelp implements Exception {}

/// Load and validate a servers JSON file (array of host objects).
List<McpollHost> loadServersFile(String path) {
  late final String raw;
  try {
    raw = File(path).readAsStringSync();
  } catch (e) {
    throw McpollArgError('cannot read --servers file "$path": $e');
  }
  late final dynamic decoded;
  try {
    decoded = jsonDecode(raw);
  } catch (e) {
    throw McpollArgError('--servers file "$path" is not JSON: $e');
  }
  if (decoded is! List) {
    throw McpollArgError('--servers file "$path" must be a JSON array');
  }
  final out = <McpollHost>[];
  for (var i = 0; i < decoded.length; i++) {
    final e = decoded[i];
    if (e is! Map) {
      throw McpollArgError('--servers file "$path": entry $i is not an object');
    }
    try {
      out.add(McpollHost.fromJson(e));
    } on McpollArgError catch (e) {
      throw McpollArgError('--servers file "$path": entry $i: ${e.message}');
    }
  }
  if (out.isEmpty) {
    throw McpollArgError('--servers file "$path" has no hosts');
  }
  return out;
}
