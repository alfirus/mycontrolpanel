// SPDX-License-Identifier: MIT
/// mcpoll per-host fetch (Lisa, TM-1 follow-up).
///
/// Pure Dart (`dart:io` HTTP + pure lib modules only — never the
/// plugin-backed `AgentService`, so `bin/mcpoll.dart` stays runnable under
/// plain `dart run`). One short-lived agent-HTTP sweep per host:
///
/// 1. `GET /alerts/snapshot` first (pre-computed trigger inputs);
/// 2. legacy `GET /metrics` + `GET /sysstats` pair on 404/bad shape
///    (pre-snapshot agents), which additionally carries cpu/ram gauges
///    evaluated with the frozen [HeadlessCheck.thresholds].
///
/// Tokens come from the environment (never argv): [resolveToken] reads
/// the host's `tokenEnv` var, falling back to `MCP_AGENT_TOKEN`.
///
/// Mapping rule (Lina's boundary): results become [HeadlessSignal]s via
/// the shared `HeadlessCheck.rules` / `signalsFromAlerts` — this file
/// never redefines the payload or the verdict table.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../background/headless_check.dart';
import '../background/headless_state.dart';
import '../services/agent_protocol.dart';
import '../services/alert_rules.dart';
import '../services/polling_alerts.dart';
import 'config.dart';

/// Resolve this host's agent token from the environment. Null = open agent.
String? resolveToken(McpollHost host, [Map<String, String>? env]) {
  final e = env ?? Platform.environment;
  final name = (host.tokenEnv?.isNotEmpty ?? false)
      ? host.tokenEnv!
      : McpollConfig.defaultTokenEnv;
  final v = (e[name] ?? '').trim();
  return v.isEmpty ? null : v;
}

/// Pure mapping: validated snapshot map → headless signals (no I/O).
List<HeadlessSignal> signalsFromSnapshot(
    String id, String name, Map<String, dynamic> snapshot) {
  final alerts = HeadlessCheck.rules.evaluate(
    id,
    name,
    HostSignals.fromSnapshot(snapshot),
  );
  return HeadlessCheck.signalsFromAlerts(alerts);
}

/// Pure mapping: legacy metrics + sysstats maps → headless signals.
///
/// Mirrors `buildAgentHostSignals` (which lives next to the transport in
/// the plugin-backed `alert_poller.dart`) and additionally evaluates the
/// cpu/ram gauges the snapshot leg cannot see (no 0.5s CPU sample there)
/// with the frozen [HeadlessCheck.thresholds]. Never throws.
List<HeadlessSignal> signalsFromMetricsSysstats(
    String id, String name, Map? metrics, Map? sysstats) {
  final out = <HeadlessSignal>[];
  try {
    var diskByMount = const <String, double>{};
    double? cpu;
    double? ram;
    if (metrics is Map) {
      final disk = metrics['disk'];
      if (disk is num && disk.isFinite) {
        diskByMount = {'/': disk.toDouble().clamp(0.0, 1.0).toDouble()};
      }
      final c = metrics['cpu'];
      if (c is num && c.isFinite) cpu = c.toDouble().clamp(0.0, 1.0);
      final r = metrics['ram'];
      if (r is num && r.isFinite) ram = r.toDouble().clamp(0.0, 1.0);
    }
    var load1 = 0.0;
    var nproc = 0;
    if (sysstats is Map) {
      final rawLoad = sysstats['load1'];
      if (rawLoad is num && rawLoad.isFinite && rawLoad >= 0) {
        load1 = rawLoad.toDouble();
      }
      final rawNproc = sysstats['nproc'];
      if (rawNproc is num && rawNproc.toInt() > 0) nproc = rawNproc.toInt();
    }
    out.addAll(HeadlessCheck.signalsFromAlerts(HeadlessCheck.rules.evaluate(
      id,
      name,
      HostSignals(diskByMount: diskByMount, load1: load1, nproc: nproc),
    )));
    // Gauges only the metrics leg can see (snapshot has no cpu/ram).
    final gauges = {'CPU': cpu, 'RAM': ram};
    gauges.forEach((label, value) {
      if (value == null) return;
      final severity = HeadlessCheck.thresholds.evaluate(value);
      if (severity == AlertSeverity.ok) return;
      final pct = (value * 100).round();
      out.add(HeadlessSignal(
          kind: 'gauge', title: '$label $pct%', owner: name));
    });
  } catch (_) {
    // Hostile maps stay silent, never fatal (parity: unionAlerts).
  }
  return out;
}

Future<Map<String, dynamic>?> _getJson(
  String host,
  int port,
  String path, {
  String? token,
  required Duration timeout,
}) async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 5);
  try {
    final req = await client.get(host, port, path);
    for (final e in agentAuthHeaders(token).entries) {
      req.headers.set(e.key, e.value);
    }
    final resp = await req.close().timeout(timeout);
    if (resp.statusCode != 200) return null;
    final body = await resp.transform(utf8.decoder).join().timeout(timeout);
    final decoded = jsonDecode(body);
    if (decoded is! Map<String, dynamic>) return null;
    return decoded;
  } catch (_) {
    return null;
  } finally {
    try {
      client.close();
    } catch (_) {}
  }
}

/// Poll one host: snapshot-first, legacy pair on fallback.
///
/// Returns the host's signals (possibly empty — an answered host with
/// nothing firing). Throws only when the host did not answer at all, so
/// the caller can distinguish "quiet host" from "dead host" exactly like
/// `pollHostAlerts` (per-host failures swallowed, total failure fatal).
Future<List<HeadlessSignal>> fetchHostSignals(
  McpollHost host, {
  required Duration timeout,
  String? token,
  bool noSnapshot = false,
}) async {
  if (!noSnapshot) {
    try {
      final body = await _getJson(host.host, host.port, kAlertSnapshotPath,
          token: token, timeout: timeout);
      if (body != null) {
        parseAlertSnapshot(body);
        final snap = (body['snapshot'] as Map).cast<String, dynamic>();
        return signalsFromSnapshot(host.id, host.name, snap);
      }
    } catch (_) {
      // Fall through to the legacy pair.
    }
  }
  final metrics = await _getJson(host.host, host.port, '/metrics',
      token: token, timeout: timeout);
  if (metrics == null) {
    throw Exception('agent :$host did not answer (snapshot + metrics down)');
  }
  Map<String, dynamic>? sysstats;
  try {
    sysstats = await _getJson(host.host, host.port, '/sysstats',
        token: token, timeout: timeout);
  } catch (_) {
    sysstats = null;
  }
  return signalsFromMetricsSysstats(host.id, host.name, metrics, sysstats);
}
