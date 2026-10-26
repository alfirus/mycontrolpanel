import 'dart:convert';

enum AuthMethod { password, sshKey, apiToken }
enum ServerEnv { prod, staging, dev }

class ServerConnection {
  final String id;
  final String name;
  final String host;
  final int port;
  final String username;
  final AuthMethod authMethod;
  final String credential; // password / key path / token
  final String region;
  final String os;
  final ServerEnv env;
  final String? tags;
  final DateTime createdAt;
  final bool enabled;

  const ServerConnection({
    required this.id,
    required this.name,
    required this.host,
    required this.port,
    required this.username,
    required this.authMethod,
    required this.credential,
    required this.region,
    required this.os,
    required this.env,
    this.tags,
    required this.createdAt,
    this.enabled = true,
  });

  Map<String, dynamic> toJson() => {
    'id': id, 'name': name, 'host': host, 'port': port, 'username': username,
    'authMethod': authMethod.name, 'credential': credential, 'region': region, 'os': os, 'env': env.name,
    'tags': tags, 'createdAt': createdAt.toIso8601String(), 'enabled': enabled,
  };

  factory ServerConnection.fromJson(Map<String, dynamic> j) => ServerConnection(
    id: j['id'], name: j['name'], host: j['host'], port: j['port'], username: j['username'],
    authMethod: AuthMethod.values.firstWhere((e)=> e.name==j['authMethod'], orElse: ()=> AuthMethod.password),
    credential: j['credential'] ?? '', region: j['region'] ?? 'us-east-1', os: j['os'] ?? 'Ubuntu 24.04',
    env: ServerEnv.values.firstWhere((e)=> e.name==j['env'], orElse: ()=> ServerEnv.prod),
    tags: j['tags'], createdAt: DateTime.parse(j['createdAt']), enabled: j['enabled'] ?? true,
  );

  ServerConnection copyWith({String? name, String? host, int? port, String? username, AuthMethod? authMethod, String? credential, String? region, String? os, ServerEnv? env, String? tags, bool? enabled}) =>
    ServerConnection(id: id, name: name ?? this.name, host: host ?? this.host, port: port ?? this.port, username: username ?? this.username, authMethod: authMethod ?? this.authMethod, credential: credential ?? this.credential, region: region ?? this.region, os: os ?? this.os, env: env ?? this.env, tags: tags ?? this.tags, createdAt: createdAt, enabled: enabled ?? this.enabled);

  static String encodeList(List<ServerConnection> list) => jsonEncode(list.map((e)=> e.toJson()).toList());
  static List<ServerConnection> decodeList(String s) {
    try {
      final l = jsonDecode(s) as List;
      return l.map((e)=> ServerConnection.fromJson(e as Map<String,dynamic>)).toList();
    } catch (_) { return []; }
  }
}
