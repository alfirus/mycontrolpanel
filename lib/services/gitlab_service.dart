import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/mock_data.dart';

/// Minimal GitLab REST client (personal access token with `api` scope).
/// Works against gitlab.com or a self-hosted base URL.
class GitlabService {
  final String baseUrl;
  final String token;
  GitlabService({required this.baseUrl, required this.token});

  String get _base => baseUrl.trim().replaceAll(RegExp(r'/+$'), '');

  Map<String, String> get _headers => {
        'PRIVATE-TOKEN': token,
        'Content-Type': 'application/json',
      };

  /// Project ref: numeric id or `group/project` path (URL-encoded).
  static String projectRef(String project) {
    project = project.trim();
    if (int.tryParse(project) != null) return project;
    return Uri.encodeComponent(project);
  }

  Future<String> validate() async {
    final r = await http.get(Uri.parse('$_base/api/v4/user'), headers: _headers);
    if (r.statusCode != 200) {
      throw Exception(_apiError(r, 'Token rejected (needs `api` scope) — ${_base}/-/user_settings/personal_access_tokens'));
    }
    final j = jsonDecode(r.body) as Map;
    return (j['username'] ?? 'unknown').toString();
  }

  Future<List<GithubItem>> projectIssues(String project) async {
    final ref = projectRef(project);
    final r = await http.get(
      Uri.parse('$_base/api/v4/projects/$ref/issues?state=opened&per_page=30&order_by=updated_at&sort=desc'),
      headers: _headers,
    );
    if (r.statusCode != 200) throw Exception(_apiError(r, 'issues'));
    final list = jsonDecode(r.body) as List;
    return list.map((e) => _toItem(e as Map<String, dynamic>, project, 'issue')).toList();
  }

  Future<List<GithubItem>> projectMRs(String project) async {
    final ref = projectRef(project);
    final r = await http.get(
      Uri.parse('$_base/api/v4/projects/$ref/merge_requests?state=opened&per_page=30&order_by=updated_at&sort=desc'),
      headers: _headers,
    );
    if (r.statusCode != 200) throw Exception(_apiError(r, 'merge requests'));
    final list = jsonDecode(r.body) as List;
    return list.map((e) {
      final j = e as Map<String, dynamic>;
      return GithubItem(
        title: (j['title'] ?? '').toString(),
        repo: project,
        author: (((j['author'] as Map?))?['username'] ?? '').toString(),
        number: (j['iid'] as num? ?? j['id'] as num? ?? 0).toInt(),
        state: 'open',
        labels: ((j['labels'] as List?) ?? []).map((l) => l.toString()).toList(),
        updatedAt: DateTime.tryParse((j['updated_at'] ?? '').toString()) ?? DateTime.now(),
        comments: ((j['user_notes_count'] as num?) ?? 0).toInt(),
        assignees: ((j['assignees'] as List?) ?? [])
            .map((a) => (((a as Map)['username']) ?? '').toString())
            .where((s) => s.isNotEmpty)
            .toList(),
      );
    }).toList();
  }

  /// "Tasks" = issues assigned to me across tracked projects.
  Future<List<GithubItem>> myTasks(List<String> projects) async {
    final me = await _me();
    final out = <GithubItem>[];
    for (final p in projects) {
      try {
        final issues = await projectIssues(p);
        out.addAll(issues.where((i) => i.assignees.contains(me) || i.author == me));
      } catch (_) {}
    }
    if (out.isEmpty) {
      for (final p in projects) {
        try {
          out.addAll((await projectIssues(p)).take(5));
        } catch (_) {}
      }
    }
    out.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return out;
  }

  /// Recent pipelines for one project (newest first).
  Future<List<DeployItem>> projectPipelines(String project, {int limit = 8}) async {
    final ref = projectRef(project);
    final r = await http.get(
      Uri.parse('$_base/api/v4/projects/$ref/pipelines?per_page=$limit&order_by=updated_at&sort=desc'),
      headers: _headers,
    );
    if (r.statusCode != 200) throw Exception(_apiError(r, 'pipelines'));
    final runs = (jsonDecode(r.body) as List?) ?? [];
    return runs.map((e) {
      final j = e as Map<String, dynamic>;
      final st = ((j['status'] ?? '') as String).toLowerCase();
      final mapped = st == 'success'
          ? 'success'
          : (st == 'running' || st == 'pending')
              ? 'running'
              : 'failed';
      final created = DateTime.tryParse((j['created_at'] ?? '').toString()) ?? DateTime.now();
      final updated = DateTime.tryParse((j['updated_at'] ?? '').toString()) ?? created;
      final secs = updated.difference(created).inSeconds;
      final dur = secs < 60
          ? '${secs}s'
          : secs < 3600
              ? '${secs ~/ 60}m ${secs % 60}s'
              : '${secs ~/ 3600}h ${(secs ~/ 3600) ~/ 60}m';
      final sha = (j['sha'] ?? '').toString();
      return DeployItem(
        app: project.split('/').last,
        version: '#${j['id']} • ${sha.length >= 8 ? sha.substring(0, 8) : sha}',
        env: (((j['ref'] ?? '') as String).isEmpty ? '—' : (j['ref'] as String)),
        actor: ((((j['user'] as Map?))?['username'] ?? '') as String).isEmpty
            ? 'gitlab-ci'
            : ((j['user'] as Map)['username'] as String),
        time: created,
        status: mapped,
        duration: mapped == 'running' ? '…' : dur,
        vcs: 'gitlab',
        glProject: project,
        pipelineId: (j['id'] as num?)?.toInt(),
      );
    }).toList();
  }

  /// Retry a pipeline. Returns true on accepted.
  Future<bool> retryPipeline(String project, int pipelineId) async {
    final ref = projectRef(project);
    final r = await http.post(
      Uri.parse('$_base/api/v4/projects/$ref/pipelines/$pipelineId/retry'),
      headers: _headers,
    );
    if (r.statusCode == 201 || r.statusCode == 200) return true;
    throw Exception(_apiError(r, 'retry pipeline $pipelineId'));
  }

  String? _meCache;
  Future<String> _me() async {
    if (_meCache != null) return _meCache!;
    final r = await http.get(Uri.parse('$_base/api/v4/user'), headers: _headers);
    if (r.statusCode == 200) {
      _meCache = ((jsonDecode(r.body) as Map)['username'] ?? '').toString();
    }
    return _meCache ?? '';
  }

  GithubItem _toItem(Map<String, dynamic> j, String project, String kind) {
    return GithubItem(
      title: (j['title'] ?? '').toString(),
      repo: project,
      author: (((j['author'] as Map?))?['username'] ?? '').toString(),
      number: (j['iid'] as num? ?? j['id'] as num? ?? 0).toInt(),
      state: ((j['state'] ?? 'opened')).toString() == 'opened' ? 'open' : (j['state'] ?? '').toString(),
      labels: ((j['labels'] as List?) ?? []).map((l) => l.toString()).toList(),
      updatedAt: DateTime.tryParse((j['updated_at'] ?? '').toString()) ?? DateTime.now(),
      comments: ((j['user_notes_count'] as num?) ?? 0).toInt(),
      assignees: ((j['assignees'] as List?) ?? [])
          .map((a) => (((a as Map)['username']) ?? '').toString())
          .where((s) => s.isNotEmpty)
          .toList(),
    );
  }

  String _apiError(http.Response r, String what) {
    try {
      final j = jsonDecode(r.body) as Map;
      final msg = j['message'];
      final detail = msg is List ? msg.join(', ') : msg;
      return 'GitLab $what failed (${r.statusCode}): $detail';
    } catch (_) {
      return 'GitLab $what failed (${r.statusCode})';
    }
  }
}
