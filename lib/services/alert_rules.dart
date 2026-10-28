/// Agent-output alert evaluation (no SSH).
///
/// [AlertRules.evaluate] maps one [HostSignals] snapshot — harvested from
/// the agent's HTTP endpoints (`/metrics`, `/sysstats`) plus the SSH
/// collectors — to [AlertEntry] hooks with severity + source attribution.
///
/// Threshold table (mirrors `AgentService.fetchAlerts` so the HTTP path
/// and the SSH path fire identically for Zara's polling job and the
/// foreground refresh):
///
/// | signal | warning | critical |
/// |---|---|---|
/// | disk usage per mount | ≥ 80% | ≥ 90% |
/// | failed systemd units | — | any unit |
/// | failed SSH logins / 24h | ≥ 5 | ≥ 20 (possible brute force) |
/// | load1 vs CPU count | > nproc | > 2 × nproc |
/// | kernel err/warn lines | any | OOM killer line |
/// | host uptime | < 1h (unexpected restart?) | — |
///
/// This is deliberately separate from `polling_alerts.Thresholds`
/// (warn 0.85 / crit 0.95): those guard live resource *gauges* for SLO
/// math, these guard harvested *collector* signals. Both are pure and
/// unit-tested; the background worker will feed this evaluator once per
/// poll tick.
library alert_rules;

import '../models/alert_entry.dart';

/// One evaluation snapshot for a host. All fields have safe defaults so
/// callers pass only what their transport observed; unknown signals are
/// skipped, never assumed healthy or firing.
class HostSignals {
  /// Disk usage per mount as 0..1 ratios (matches `/metrics.disk` units).
  final Map<String, double> diskByMount;

  /// Failed unit names (`nginx.service` or short `nginx`).
  final List<String> failedUnits;

  /// Failed SSH logins in the trailing 24h.
  final int failedLogins24h;

  /// 1-minute load average.
  final double load1;

  /// CPU count (`/sysstats.nproc` or `nproc`). ≤ 0 = unknown → the
  /// load rule is skipped rather than evaluated against a guess.
  final int nproc;

  /// Recent kernel err/warn lines (highest severity kept).
  final List<String> kernelLines;

  /// Host uptime in seconds (`/proc/uptime`). Null = unknown → the
  /// reboot rule is skipped.
  final int? uptimeSecs;

  const HostSignals({
    this.diskByMount = const {},
    this.failedUnits = const [],
    this.failedLogins24h = 0,
    this.load1 = 0,
    this.nproc = 0,
    this.kernelLines = const [],
    this.uptimeSecs,
  });
}

class AlertRules {
  /// Disk warn/crit lines (fractions, per mount).
  final double diskWarnAt;
  final double diskCritAt;

  /// Brute-force warn/crit counts per 24h.
  final int bruteWarnAt;
  final int bruteCritAt;

  /// Reboot tripwire: uptime below this fires a warning.
  final Duration rebootWithin;

  const AlertRules({
    this.diskWarnAt = 0.80,
    this.diskCritAt = 0.90,
    this.bruteWarnAt = 5,
    this.bruteCritAt = 20,
    this.rebootWithin = const Duration(hours: 1),
  });

  /// Evaluate one snapshot. Never throws on hostile input — out-of-range
  /// ratios clamp, blanks are ignored, unknown counts skip their rule.
  List<AlertEntry> evaluate(
    String serverId,
    String serverName,
    HostSignals s,
  ) {
    final out = <AlertEntry>[];
    AlertEntry mk(String title, String source, String severity) => AlertEntry(
        title: title,
        source: '$source • $serverName',
        severity: severity,
        serverId: serverId,
        serverName: serverName);

    // 1. failed systemd units — every unit is critical.
    for (final raw in s.failedUnits) {
      final u = raw.trim().replaceAll('.service', '');
      if (u.isEmpty) continue;
      out.add(mk('Service failed: $u', 'systemd', 'critical'));
    }

    // 2. disk usage per mount.
    s.diskByMount.forEach((mount, ratio) {
      final m = mount.trim().isEmpty ? '/' : mount.trim();
      final pct = (ratio.clamp(0.0, 1.0) * 100).round();
      if (ratio >= diskCritAt) {
        out.add(mk('Disk $pct% full on $m', 'disk', 'critical'));
      } else if (ratio >= diskWarnAt) {
        out.add(mk('Disk $pct% full on $m', 'disk', 'warning'));
      }
    });

    // 3. SSH brute force in the trailing 24h.
    if (s.failedLogins24h >= bruteCritAt) {
      out.add(mk(
          '${s.failedLogins24h} failed SSH logins in 24h'
          ' (possible brute force)',
          'auth',
          'critical'));
    } else if (s.failedLogins24h >= bruteWarnAt) {
      out.add(mk('${s.failedLogins24h} failed SSH logins in 24h', 'auth',
          'warning'));
    }

    // 4. load average vs CPU count.
    if (s.nproc > 0 && s.load1 > 0) {
      if (s.load1 > s.nproc * 2) {
        out.add(mk(
            'Load average ${s.load1} on ${s.nproc} CPUs (overloaded)',
            'load',
            'critical'));
      } else if (s.load1 > s.nproc) {
        out.add(mk('Load average ${s.load1} on ${s.nproc} CPUs (high)',
            'load', 'warning'));
      }
    }

    // 5. kernel errors: OOM is critical, anything else warning.
    final kern =
        s.kernelLines.map((l) => l.trim()).where((l) => l.isNotEmpty).toList();
    if (kern.isNotEmpty) {
      final oom = kern.any((l) {
        final x = l.toLowerCase();
        return x.contains('out of memory') || x.contains('oom-killer');
      });
      out.add(mk(
          oom
              ? 'Out-of-memory killer fired in last 24h'
              : '${kern.length} kernel warnings in last 24h',
          'kernel',
          oom ? 'critical' : 'warning'));
    }

    // 6. rebooted recently (uptime below the tripwire).
    final up = s.uptimeSecs;
    if (up != null && up >= 0 && up < rebootWithin.inSeconds) {
      out.add(mk(
          'Server rebooted ${up ~/ 60}m ago — unexpected restart?',
          'uptime',
          'warning'));
    }

    return out;
  }
}
