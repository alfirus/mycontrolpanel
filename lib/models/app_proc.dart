/// APM-lite: top process + per-port connection snapshot from agent v2 (/procstats).
class AppProc {
  final int pid;
  final String name;
  final double cpu; // 0-1
  final int memMb;
  const AppProc({required this.pid, required this.name, required this.cpu, required this.memMb});

  factory AppProc.fromJson(Map<String, dynamic> j) => AppProc(
        pid: (j['pid'] as num? ?? 0).toInt(),
        name: ((j['name'] ?? '?')).toString(),
        cpu: ((j['cpu'] as num?) ?? 0).toDouble(),
        memMb: (j['mem_mb'] as num? ?? 0).toInt(),
      );
}

class AppPortStat {
  final String port;
  final bool listening;
  final int established;
  const AppPortStat({required this.port, required this.listening, required this.established});
}

class AppStats {
  final List<AppProc> top;
  final Map<String, AppPortStat> ports;
  const AppStats({required this.top, required this.ports});

  factory AppStats.fromJson(Map<String, dynamic> j) {
    final top = ((j['top'] as List?) ?? [])
        .map((e) => AppProc.fromJson((e as Map).cast<String, dynamic>()))
        .toList();
    final ports = <String, AppPortStat>{};
    ((j['ports'] as Map?) ?? {}).forEach((k, v) {
      final m = (v as Map).cast<String, dynamic>();
      ports[k.toString()] = AppPortStat(
        port: k.toString(),
        listening: m['listening'] == true,
        established: (m['established'] as num? ?? 0).toInt(),
      );
    });
    return AppStats(top: top, ports: ports);
  }

  /// Best-effort match: systemd unit / container / process name vs live procs.
  AppProc? matchForApp(String appName) {
    final q = appName.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
    if (q.isEmpty) return null;
    for (final p in top) {
      final n = p.name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
      if (n.isNotEmpty && (n.contains(q) || q.contains(n))) return p;
    }
    return null;
  }
}
