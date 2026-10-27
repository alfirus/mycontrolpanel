import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/mock_data.dart';

/// Minimal GitHub REST client (classic PAT or fine-grained token).
/// Needs `repo` scope (or Contents/Issues/Pull requests read for fine-grained).
class GithubService {
  final String token;
  GithubService(this.token);

  Map<String, String> get _headers => {
        'Accept': 'application/vnd.github+json',
        'Authorization': 'Bearer $token',
        'X-GitHub-Api-Version': '2022-11-28',
      };

  Future<String> validate() async {
    final r = await http.get(Uri.parse('https://api.github.com/user'), headers: _headers);
    if (r.statusCode != 200) {
      throw Exception(_apiError(r, 'Token rejected (need `repo` scope)'));
    }
    final j = jsonDecode(r.body) as Map<String, dynamic>;
    return (j['login'] ?? 'unknown').toString();
  }

  Future<List<GithubItem>> repoIssues(String repo) async {
    final r = await http.get(
      Uri.parse('https://api.github.com/repos/$repo/issues?state=open&per_page=30&sort=updated'),
      headers: _headers,
    );
    if (r.statusCode != 200) throw Exception(_apiError(r, 'issues'));
    final list = jsonDecode(r.body) as List;
    return list
        .where((e) => (e as Map<String, dynamic>)['pull_request'] == null)
        .map((e) => _toIssue(e as Map<String, dynamic>, repo))
        .toList();
  }

  Future<List<GithubItem>> repoPRs(String repo) async {
    final r = await http.get(
      Uri.parse('https://api.github.com/repos/$repo/pulls?state=open&per_page=30&sort=updated&direction=desc'),
      headers: _headers,
    );
    if (r.statusCode != 200) throw Exception(_apiError(r, 'pulls'));
    final list = jsonDecode(r.body) as List;
    return list.map((e) {
      final j = e as Map<String, dynamic>;
      return GithubItem(
        title: (j['title'] ?? '').toString(),
        repo: repo,
        author: ((j['user'] as Map?)?['login'] ?? '').toString(),
        number: (j['number'] as num).toInt(),
        state: 'open',
        labels: ((j['labels'] as List?) ?? []).map((l) => ((l as Map)['name'] ?? '').toString()).toList(),
        updatedAt: DateTime.tryParse((j['updated_at'] ?? '').toString()) ?? DateTime.now(),
        comments: ((j['comments'] as num?) ?? 0).toInt() + ((j['review_comments'] as num?) ?? 0).toInt(),
      );
    }).toList();
  }

  /// Projects v2 owned by the viewer: id, title, open item count.
  /// Returns [] when the token lacks Projects access (falls back silently).
  Future<List<Map<String, dynamic>>> projectsV2() async {
    const q = 'query { viewer { login projectsV2(first: 10, orderBy: {field: UPDATED_AT, direction: DESC}) { nodes { id title url updatedAt items(first: 1) { totalCount } } } } }';
    final r = await http.post(
      Uri.parse('https://api.github.com/graphql'),
      headers: {..._headers, 'Content-Type': 'application/json'},
      body: jsonEncode({'query': q}),
    );
    if (r.statusCode != 200) throw Exception(_apiError(r, 'projects'));
    final j = jsonDecode(r.body) as Map;
    if (j.containsKey('errors')) {
      final errs = (j['errors'] as List).map((e) => ((e as Map)['message'] ?? '').toString()).join('; ');
      throw Exception('GitHub Projects: $errs');
    }
    final nodes = ((((j['data'] as Map?)?['viewer'] as Map?)?['projectsV2'] as Map?)?['nodes'] as List?) ?? [];
    return nodes.map((n) {
      final m = n as Map;
      return {
        'id': (m['id'] ?? '').toString(),
        'title': ((m['title'] ?? 'Untitled')).toString(),
        'url': ((m['url'] ?? '')).toString(),
        'items': ((((m['items'] as Map?))?['totalCount'] as num?) ?? 0).toInt(),
      };
    }).toList();
  }

  /// Tasks from Projects v2: items across the viewer's recent projects,
  /// skipping Done/Closed/Complete statuses. Throws when Projects is
  /// unreachable (caller keeps the assigned-issue fallback).
  Future<List<GithubItem>> projectTasks() async {
    const q = 'query { viewer { login projectsV2(first: 5, orderBy: {field: UPDATED_AT, direction: DESC}) { nodes { title items(first: 30) { nodes { content { __typename ... on Issue { number title url updatedAt state author { login } labels(first: 5) { nodes { name } } comments { totalCount } assignees(first: 5) { nodes { login } } } ... on PullRequest { number title url updatedAt state author { login } labels(first: 5) { nodes { name } } comments { totalCount } assignees(first: 5) { nodes { login } } } ... on DraftIssue { title body updatedAt } } fieldValues(first: 8) { nodes { ... on ProjectV2ItemFieldSingleSelectValue { name } } } } } } } }';
    final r = await http.post(
      Uri.parse('https://api.github.com/graphql'),
      headers: {..._headers, 'Content-Type': 'application/json'},
      body: jsonEncode({'query': q}),
    );
    if (r.statusCode != 200) throw Exception(_apiError(r, 'project items'));
    final j = jsonDecode(r.body) as Map;
    if (j.containsKey('errors')) {
      final errs = (j['errors'] as List).map((e) => ((e as Map)['message'] ?? '').toString()).join('; ');
      throw Exception('GitHub Projects: $errs');
    }
    final out = <GithubItem>[];
    final viewer = ((j['data'] as Map?)?['viewer'] as Map?);
    final me = ((viewer?['login'] ?? '') as String);
    final nodes = (((viewer?['projectsV2'] as Map?)?['nodes'] as List?) ?? []);
    for (final pn in nodes) {
      final pm = pn as Map;
      final projectTitle = ((pm['title'] ?? 'Project')).toString();
      final items = ((((pm['items'] as Map?))?['nodes'] as List?) ?? []);
      for (final it in items) {
        final im = it as Map;
        final content = (im['content'] as Map?);
        if (content == null) continue;
        final statusNames = ((((im['fieldValues'] as Map?)?['nodes'] as List?) ?? [])
                .whereType<Map>()
                .map((f) => ((f['name'] ?? '') as String).toLowerCase()))
            .toList();
        if (statusNames.any((s) => s.contains('done') || s == 'closed' || s.contains('complete') || s.contains('archived'))) {
          continue;
        }
        final type = (content['__typename'] ?? '').toString();
        if (type == 'DraftIssue') {
          out.add(GithubItem(
            title: ((content['title'] ?? '(draft)')).toString(),
            repo: projectTitle,
            author: me,
            number: 0,
            state: 'open',
            labels: const ['draft'],
            updatedAt: DateTime.tryParse((content['updatedAt'] ?? '').toString()) ?? DateTime.now(),
            comments: 0,
          ));
        } else {
          final labels = ((((content['labels'] as Map?)?['nodes'] as List?) ?? []).map((l) => (((l as Map)['name']) ?? '').toString())).toList();
          final assignees = ((((content['assignees'] as Map?)?['nodes'] as List?) ?? []).map((a) => (((a as Map)['login']) ?? '').toString())).toList();
          final st = ((content['state'] ?? 'OPEN')).toString().toUpperCase();
          out.add(GithubItem(
            title: ((content['title'] ?? '')).toString(),
            repo: projectTitle,
            author: (((content['author'] as Map?)?['login']) ?? me).toString(),
            number: (content['number'] as num? ?? 0).toInt(),
            state: st == 'OPEN' ? 'open' : 'closed',
            labels: labels,
            updatedAt: DateTime.tryParse((content['updatedAt'] ?? '').toString()) ?? DateTime.now(),
            comments: ((((content['comments'] as Map?)?['totalCount']) as num?) ?? 0).toInt(),
            assignees: assignees,
          ));
        }
      }
    }
    out.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return out;
  }

  /// "Tasks" = open issues assigned to the token owner across all configured repos.
  Future<List<GithubItem>> myTasks(List<String> repos) async {
    final out = <GithubItem>[];
    for (final repo in repos) {
      try {
        final issues = await repoIssues(repo);
        final me = await _login();
        out.addAll(issues.where((i) => i.author == me || i.assignees.contains(me)));
      } catch (_) {}
    }
    // Fallback: if assignee data unavailable, show recently updated issues as tasks.
    if (out.isEmpty) {
      for (final repo in repos) {
        try {
          out.addAll((await repoIssues(repo)).take(5));
        } catch (_) {}
      }
    }
    out.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return out;
  }

  /// Recent workflow runs across one repo (Actions API).
  /// Maps to DeployItem: app=repo, version=#run+short SHA, env=branch.
  Future<List<DeployItem>> repoRuns(String repo, {int limit = 8}) async {
    final r = await http.get(
      Uri.parse('https://api.github.com/repos/$repo/actions/runs?per_page=$limit'),
      headers: _headers,
    );
    if (r.statusCode != 200) throw Exception(_apiError(r, 'actions runs'));
    final runs = ((jsonDecode(r.body) as Map)['workflow_runs'] as List?) ?? [];
    return runs.map((e) {
      final j = e as Map<String, dynamic>;
      final status = (j['status'] ?? '').toString(); // queued, in_progress, completed
      final conclusion = (j['conclusion'] ?? '').toString(); // success, failure, cancelled, skipped
      final mapped = status != 'completed'
          ? 'running'
          : conclusion == 'success'
              ? 'success'
              : 'failed';
      final created = DateTime.tryParse((j['created_at'] ?? '').toString()) ?? DateTime.now();
      final updated = DateTime.tryParse((j['updated_at'] ?? '').toString()) ?? created;
      final secs = updated.difference(created).inSeconds;
      final dur = secs < 60
          ? '${secs}s'
          : secs < 3600
              ? '${secs ~/ 60}m ${secs % 60}s'
              : '${secs ~/ 3600}h ${(secs % 3600) ~/ 60}m';
      final sha = (j['head_sha'] ?? '').toString();
      return DeployItem(
        app: repo.split('/').last,
        version: '#${j['run_number']} • ${sha.length >= 7 ? sha.substring(0, 7) : sha}',
        env: ((j['head_branch'] ?? '').toString().isEmpty ? '—' : (j['head_branch'] as String)),
        actor: (((j['actor'] as Map?) ?? const {})['login'] ?? ((j['head_commit'] as Map?)?['author']?['name'] ?? 'github-actions')).toString(),
        time: created,
        status: mapped,
        duration: mapped == 'running' ? '…' : dur,
        runId: (j['id'] as num?)?.toInt(),
      );
    }).toList();
  }

  /// Re-run a workflow run. Returns true on accepted (201/204).
  Future<bool> rerunRun(String repo, int runId) async {
    final r = await http.post(
      Uri.parse('https://api.github.com/repos/$repo/actions/runs/$runId/rerun'),
      headers: _headers,
    );
    if (r.statusCode == 201 || r.statusCode == 204) return true;
    throw Exception(_apiError(r, 'rerun $runId'));
  }

  /// Create an issue. Returns the new issue number.
  Future<int> createIssue(String repo, String title, {String body = '', List<String> labels = const []}) async {
    final r = await http.post(
      Uri.parse('https://api.github.com/repos/$repo/issues'),
      headers: _headers,
      body: jsonEncode({'title': title, 'body': body, 'labels': labels}),
    );
    if (r.statusCode != 201) throw Exception(_apiError(r, 'create issue'));
    return (((jsonDecode(r.body) as Map)['number'] as num?) ?? 0).toInt();
  }

  String? _loginCache;
  Future<String> _login() async {
    if (_loginCache != null) return _loginCache!;
    final r = await http.get(Uri.parse('https://api.github.com/user'), headers: _headers);
    if (r.statusCode == 200) {
      _loginCache = ((jsonDecode(r.body) as Map)['login'] ?? '').toString();
    }
    return _loginCache ?? '';
  }

  GithubItem _toIssue(Map<String, dynamic> j, String repo) {
    final assignees = ((j['assignees'] as List?) ?? [])
        .map((a) => ((a as Map)['login'] ?? '').toString())
        .toList();
    return GithubItem(
      title: (j['title'] ?? '').toString(),
      repo: repo,
      author: ((j['user'] as Map?)?['login'] ?? '').toString(),
      number: (j['number'] as num).toInt(),
      state: ((j['state'] ?? 'open')).toString(),
      labels: ((j['labels'] as List?) ?? []).map((l) => ((l as Map)['name'] ?? '').toString()).toList(),
      updatedAt: DateTime.tryParse((j['updated_at'] ?? '').toString()) ?? DateTime.now(),
      comments: ((j['comments'] as num?) ?? 0).toInt(),
      assignees: assignees,
    );
  }

  String _apiError(http.Response r, String what) {
    try {
      final j = jsonDecode(r.body) as Map;
      return 'GitHub $what failed (${r.statusCode}): ${j['message']}';
    } catch (_) {
      return 'GitHub $what failed (${r.statusCode})';
    }
  }
}
