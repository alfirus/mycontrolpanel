/// Agent Protocol v1 — versioned contract for the MyControlPanel metrics
/// agent served by the Python systemd unit on TCP 9108.
///
/// This file owns every wire-level constant (paths, timeouts, version floor)
/// plus the typed error taxonomy and the strict response validators.
/// [AgentService] performs transport (SSH install, HttpClient GETs);
/// everything it sends or accepts MUST be expressed through this contract.
/// See docs/specs/agent-protocol.md for the human-readable spec.
library agent_protocol;

import 'dart:convert';

/// Protocol version implemented by THIS app release.
const int kAgentProtocolVersion = 1;

/// Minimum agent software `version` field the app accepts.
/// Agent v1 payloads (no `version` key) are treated as stale and rejected.
const int kMinAgentVersion = 2;

/// Fixed agent TCP port (systemd unit + firewall rule + manual script).
const int kAgentPort = 9108;

/// Wire paths.
const String kMetricsPath = '/metrics';
const String kProcStatsPath = '/procstats';

/// v3+ capacity signals (load, memory detail, GPU, CPU count, boot epoch).
/// The alert polling job reads this for load-vs-nproc evaluation.
const String kSysstatsPath = '/sysstats';

/// v4+ liveness probe. Cheap by design (no /proc scan): load balancers,
/// Zara's polling job, and the app install-verify all hit this first.
const String kHealthPath = '/health';

/// v4+ log sources for `GET /logs?source=`. Mirrors the agent's
/// `ALLOWED_LOG_SOURCES`; the server allowlists again, so this is a
/// client-side convenience for fail-fast validation + docs.
const List<String> kAgentLogSources = ['journal', 'syslog'];

/// v5+ cron run log (`GET /cronruns?lines=`). The agent tails
/// `/var/log/mcp-cronruns.log`; feeds Zara's last-run tracker.
const String kCronRunsPath = '/cronruns';

/// Client timeouts: connect 5s, /metrics read 6s, /procstats read 8s.
/// Install-verify polls reuse the /metrics budget per attempt.
const Duration kAgentConnectTimeout = Duration(seconds: 5);
const Duration kMetricsReadTimeout = Duration(seconds: 6);
const Duration kProcStatsReadTimeout = Duration(seconds: 8);

/// Reserved Authorization scheme for a future token-gated agent.
/// v2 agents ignore this header; clients MUST send it when a per-host
/// agent token is configured so rollout needs no app update.
const String kAgentAuthHeader = 'X-MCP-Agent-Token';

/// Headers to attach for v4 token auth. Returns {} when no token is
/// configured (open agent) — pure, so polling code and tests share it.
Map<String, String> agentAuthHeaders(String? token) {
  final t = (token ?? '').trim();
  if (t.isEmpty) return const {};
  return {kAgentAuthHeader: t};
}

/// Machine-readable failure codes surfaced to the UI / alert pipeline.
enum AgentErrorCode {
  /// TCP refused / host unreachable / DNS failure.
  unreachable,

  /// Connected but no response inside the read budget.
  timeout,

  /// Non-200 status, non-JSON body, or schema violation.
  badPayload,

  /// Agent `version` below [kMinAgentVersion] (stale agent, reinstall).
  staleAgent,

  /// Reserved: agent demanded a token we did not supply (HTTP 401).
  unauthorized,
}

/// Typed agent failure. [detail] is safe for logs; never contains secrets.
class AgentProtocolException implements Exception {
  final AgentErrorCode code;
  final String detail;
  const AgentProtocolException(this.code, this.detail);

  @override
  String toString() => 'AgentProtocolException($code): $detail';
}

/// Validated /metrics payload. All ratios are 0..1.
class AgentMetrics {
  final double cpu;
  final double ram;
  final double disk;
  final int uptimeDays;
  final int agentVersion;

  const AgentMetrics({
    required this.cpu,
    required this.ram,
    required this.disk,
    required this.uptimeDays,
    required this.agentVersion,
  });

  Map<String, dynamic> toJson() => {
        'cpu': cpu,
        'ram': ram,
        'disk': disk,
        'uptime_days': uptimeDays,
        'version': agentVersion,
      };
}

/// Validated /health payload (agent v4+).
class AgentHealth {
  final int agentVersion;
  final int agentUptimeS;

  const AgentHealth({
    required this.agentVersion,
    required this.agentUptimeS,
  });

  Map<String, dynamic> toJson() => {
        'status': 'ok',
        'version': agentVersion,
        'agent_uptime_s': agentUptimeS,
      };
}

/// Validates a decoded /health body. Throws [AgentProtocolException].
AgentHealth parseAgentHealth(Map<String, dynamic> json) {
  if (json['status'] != 'ok') {
    throw const AgentProtocolException(
        AgentErrorCode.badPayload, '"/health.status" is not "ok"');
  }
  final version = json['version'];
  if (version is! num || version.toInt() < kMinAgentVersion) {
    throw const AgentProtocolException(
        AgentErrorCode.staleAgent, '/health version missing or stale');
  }
  final uptime = json['agent_uptime_s'];
  if (uptime is! num || uptime.toInt() < 0) {
    throw const AgentProtocolException(
        AgentErrorCode.badPayload, '"/health.agent_uptime_s" invalid');
  }
  return AgentHealth(
    agentVersion: version.toInt(),
    agentUptimeS: uptime.toInt(),
  );
}

/// Validates a decoded /metrics body. Throws [AgentProtocolException].
AgentMetrics parseAgentMetrics(Map<String, dynamic> json) {
  double ratio(String key) {
    final v = json[key];
    if (v is! num) {
      throw AgentProtocolException(
          AgentErrorCode.badPayload, '"/metrics.$key" missing or not numeric');
    }
    return v.toDouble().clamp(0.0, 1.0);
  }

  final version = json['version'];
  if (version is! num) {
    // Agent v1 never sent `version` — unambiguous stale-agent signal.
    throw const AgentProtocolException(
        AgentErrorCode.staleAgent, 'agent reports no version (v1 payload)');
  }
  if (version.toInt() < kMinAgentVersion) {
    throw AgentProtocolException(AgentErrorCode.staleAgent,
        'agent v${version.toInt()} < minimum v$kMinAgentVersion — reinstall');
  }
  final uptime = json['uptime_days'];
  if (uptime is! num || uptime.toInt() < 0) {
    throw const AgentProtocolException(
        AgentErrorCode.badPayload, '"/metrics.uptime_days" invalid');
  }
  return AgentMetrics(
    cpu: ratio('cpu'),
    ram: ratio('ram'),
    disk: ratio('disk'),
    uptimeDays: uptime.toInt(),
    agentVersion: version.toInt(),
  );
}

/// Validates a decoded /procstats body. Throws [AgentProtocolException].
/// Shape check only — row mapping stays in `AppStats.fromJson`.
void checkProcStatsSchema(Map<String, dynamic> json) {
  final version = json['version'];
  if (version is! num || version.toInt() < kMinAgentVersion) {
    throw const AgentProtocolException(
        AgentErrorCode.staleAgent, '/procstats version missing or stale');
  }
  if (json['top'] is! List) {
    throw const AgentProtocolException(
        AgentErrorCode.badPayload, '"/procstats.top" missing or not a list');
  }
  if (json['ports'] is! Map) {
    throw const AgentProtocolException(
        AgentErrorCode.badPayload, '"/procstats.ports" missing or not a map');
  }
}

/// Maps an HTTP status from the agent to a typed failure.
AgentProtocolException agentHttpError(int statusCode, String path) {
  if (statusCode == 401) {
    return const AgentProtocolException(
        AgentErrorCode.unauthorized, 'agent requires a token (HTTP 401)');
  }
  if (statusCode == 400) {
    return AgentProtocolException(AgentErrorCode.badPayload,
        '"$path" bad request — check query parameters (HTTP 400)');
  }
  if (statusCode == 404) {
    return AgentProtocolException(AgentErrorCode.badPayload,
        '"$path" unknown — stale agent (HTTP 404)');
  }
  if (statusCode == 405) {
    return AgentProtocolException(AgentErrorCode.badPayload,
        '"$path" method not allowed — agent only serves GET (HTTP 405)');
  }
  return AgentProtocolException(
      AgentErrorCode.badPayload, '"$path" HTTP $statusCode');
}

/// Decodes a raw response body or throws [AgentErrorCode.badPayload].
Map<String, dynamic> decodeAgentBody(String body, String path) {
  try {
    final v = jsonDecode(body);
    if (v is Map<String, dynamic>) return v;
    throw const FormatException('top-level JSON is not an object');
  } on AgentProtocolException {
    rethrow;
  } catch (e) {
    throw AgentProtocolException(
        AgentErrorCode.badPayload, '"$path" body is not JSON: $e');
  }
}
