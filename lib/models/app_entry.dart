/// An app/service discovered on a real server via SSH.
class AppEntry {
  final String name;
  final String detail; // version, port, or image
  final String source; // systemd, docker, port
  final String serverId;
  final String serverName;
  final bool running;

  const AppEntry({
    required this.name,
    required this.detail,
    required this.source,
    required this.serverId,
    required this.serverName,
    this.running = true,
  });
}
