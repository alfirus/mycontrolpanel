/// A real alert harvested from a server via SSH.
class AlertEntry {
  final String title;
  final String source;
  final String severity; // critical, warning, info
  final String serverId;
  final String serverName;
  final String status; // firing, resolved

  const AlertEntry({
    required this.title,
    required this.source,
    required this.severity,
    required this.serverId,
    required this.serverName,
    this.status = 'firing',
  });
}
