/// Grounded AI Chatbox pipeline — server-context builder + lightweight
/// retrieval over status/logs/alerts + offline eval set.
///
/// Dependency-light by design: `dart:math` only, no new pubspec entries.
/// The UI keeps calling the LLM provider via [AiService]; this module only
/// builds the *grounding input* (system context block + retrieved snippets)
/// so the model answers from live state instead of inventing servers.
///
/// Production wiring (for Nadia): the app already assembles a system prompt
/// in `control_center_screen.dart::_aiSystemPrompt`. Swap that inline builder
/// for [ChatContextBuilder.build] and prepend [ChatRetriever.retrieve] hits
/// for the user query. Nothing here touches the network.
library chat_context;

import 'dart:math';

/// One retrievable evidence snippet (log tail line, alert, metric note).
class ChatDoc {
  final String id;
  final String kind;
  final String server;
  final String text;

  const ChatDoc({
    required this.id,
    required this.kind,
    required this.server,
    required this.text,
  });
}

/// One scored retrieval hit.
class ChatHit {
  final ChatDoc doc;
  final double score;

  const ChatHit(this.doc, this.score);
}

/// Builds the grounded system-context block from live app state.
///
/// Inputs are plain maps so the screen can pass its existing `_servers`,
/// `_metrics`, alert/cron/app lists without new model classes:
/// - servers: [{name, ip, region, status}]
/// - metrics: {serverId: {cpu, ram, disk (0..1), uptime_days}}
/// - alerts/crons/apps/logs: pre-formatted one-line strings (cap applied).
class ChatContextBuilder {
  static const int maxServers = 25;
  static const int maxPerSection = 10;
  static const int maxChars = 6000;

  static String build({
    required List<Map<String, String>> servers,
    required Map<String, Map<String, double>> metrics,
    required List<String> alerts,
    required List<String> crons,
    required List<String> apps,
    required List<String> recentLogs,
    bool demoData = false,
  }) {
    final b = StringBuffer();
    b.writeln('You are the AI assistant inside MyControlPanel, an IT control center app.');
    b.writeln('Reply in GitHub-flavored Markdown: short headings, bullets, tables for comparisons, fenced code for commands. Keep it tight.');
    b.writeln('Use ONLY the live state below for facts about infrastructure. Never invent servers, metrics, or deployments. When evidence is missing, say so and name the tool/screen that would provide it.');
    b.writeln();
    b.writeln('SERVERS (${servers.length}${demoData ? ', DEMO data' : ', live'}):');
    for (final s in servers.take(maxServers)) {
      final id = s['id'] ?? s['name'] ?? '?';
      final m = metrics[id] ?? metrics[s['name'] ?? ''];
      final met = m == null
          ? 'no live metrics'
          : 'cpu=${((m['cpu'] ?? 0) * 100).toInt()}% '
              'ram=${((m['ram'] ?? 0) * 100).toInt()}% '
              'disk=${((m['disk'] ?? 0) * 100).toInt()}% '
              'up=${(m['uptime_days'] ?? 0).toInt()}d';
      b.writeln('- ${s['name'] ?? id} (${s['ip'] ?? 'n/a'}, ${s['region'] ?? 'n/a'}) status=${s['status'] ?? 'unknown'} $met');
    }
    b.writeln();
    _section(b, 'ALERTS', alerts);
    _section(b, 'CRONJOBS', crons);
    _section(b, 'APPS', apps);
    _section(b, 'RECENT LOGS', recentLogs);
    var out = b.toString();
    if (out.length > maxChars) {
      out = '${out.substring(0, maxChars)}…\n[truncated: ${out.length - maxChars} chars omitted]';
    }
    return out;
  }

  static void _section(StringBuffer b, String title, List<String> items) {
    b.writeln('$title (${items.length}):');
    for (final a in items.take(maxPerSection)) {
      b.writeln('- $a');
    }
    b.writeln();
  }
}

/// Keyword retrieval over status/logs/alerts evidence.
///
/// Scores = matched query-term fraction (IDF-lite via 1/log(1+df)) with a
/// small exact-phrase bonus. No embeddings, no deps — runs on-device and is
/// fully deterministic for the offline eval set below.
class ChatRetriever {
  /// Tokenize: lowercase alnum words, drop 1-char tokens + stopwords.
  static List<String> tokenize(String s) {
    const stop = {
      'the', 'a', 'an', 'is', 'are', 'was', 'were', 'on', 'in', 'of',
      'to', 'for', 'and', 'or', 'what', 'which', 'how', 'why', 'my',
      'with', 'show', 'list', 'tell', 'me', 'any', 'there', 'server',
    };
    return s
        .toLowerCase()
        .split(RegExp(r'[^a-z0-9]+'))
        .where((w) => w.length > 1 && !stop.contains(w))
        .toList();
  }

  /// Return top-[k] hits for [query] over [docs] (stable order on ties).
  static List<ChatHit> retrieve(String query, List<ChatDoc> docs, {int k = 5}) {
    final terms = tokenize(query).toSet();
    if (terms.isEmpty || docs.isEmpty) return const [];
    final df = <String, int>{};
    final docTerms = <List<String>>[];
    for (final d in docs) {
      final toks = tokenize('${d.server} ${d.kind} ${d.text}').toSet().toList();
      docTerms.add(toks);
      for (final t in toks.toSet()) {
        df[t] = (df[t] ?? 0) + 1;
      }
    }
    final q = query.toLowerCase();
    final scored = <ChatHit>[];
    for (var i = 0; i < docs.length; i++) {
      final set = docTerms[i].toSet();
      var s = 0.0;
      for (final t in terms) {
        if (set.contains(t)) {
          s += 1.0 / log(1 + (df[t] ?? 1));
        } else {
          // Prefix fallback: "auth" matches "authentication".
          for (final w in set) {
            if (w.startsWith(t) || t.startsWith(w)) {
              s += 0.5 / log(1 + (df[w] ?? 1));
              break;
            }
          }
        }
      }
      if (s > 0) {
        if (q.length > 4 && docs[i].text.toLowerCase().contains(q)) s += 0.5;
        scored.add(ChatHit(docs[i], s / terms.length));
      }
    }
    scored.sort((a, b) {
      final c = b.score.compareTo(a.score);
      return c != 0 ? c : a.doc.id.compareTo(b.doc.id);
    });
    return scored.take(k).toList();
  }
}

/// Offline eval case: a query plus the doc ids that MUST be retrieved.
class ChatEvalCase {
  final String query;
  final Set<String> mustInclude;
  final int k;

  const ChatEvalCase(this.query, this.mustInclude, {this.k = 5});
}

/// Offline eval set (no network, no LLM). The repo's `flutter test` gate
/// runs [ChatEvalSet.cases] through [ChatRetriever] against
/// [ChatEvalSet.docs] and asserts recall >= [ChatEvalSet.minRecall].
class ChatEvalSet {
  static const double minRecall = 0.8;

  static List<ChatDoc> get docs => const [
        ChatDoc(id: 'm1', kind: 'metrics', server: 'prod-core-01', text: 'cpu 91% ram 78% disk 62% load 4.2 — hot, over baseline'),
        ChatDoc(id: 'm2', kind: 'metrics', server: 'staging-02', text: 'cpu 12% ram 30% disk 41% load 0.4 — healthy idle'),
        ChatDoc(id: 'a1', kind: 'alert', server: 'prod-core-01', text: 'CRITICAL disk 82% on / — firing since 02:14'),
        ChatDoc(id: 'a2', kind: 'alert', server: 'prod-core-01', text: 'WARNING high CPU 15m — firing'),
        ChatDoc(id: 'l1', kind: 'log', server: 'prod-core-01', text: 'sshd Failed password for root from 45.9.8.7 port 512 — repeated 40x (possible brute force)'),
        ChatDoc(id: 'l2', kind: 'log', server: 'prod-core-01', text: 'kernel: Out of memory: Killed process 4242 (mcp-agent) score 900'),
        ChatDoc(id: 'l3', kind: 'log', server: 'staging-02', text: 'nginx started, listening on 0.0.0.0:80 — routine deploy reload'),
        ChatDoc(id: 'c1', kind: 'cron', server: 'prod-core-01', text: '0 * * * * /opt/mcp-agent/hourly.sh — last run ok'),
      ];

  static List<ChatEvalCase> get cases => const [
        ChatEvalCase('which server has high cpu?', {'m1', 'a2'}),
        ChatEvalCase('disk alert on prod?', {'a1'}),
        ChatEvalCase('brute force ssh attempts?', {'l1'}),
        ChatEvalCase('out of memory killed process?', {'l2'}),
        ChatEvalCase('is staging healthy?', {'m2', 'l3'}),
        ChatEvalCase('hourly cron status?', {'c1'}),
      ];

  /// Recall over [cases]: fraction of `mustInclude` ids present in top-k.
  static double recall() {
    var need = 0;
    var got = 0;
    for (final c in cases) {
      final hits = ChatRetriever.retrieve(c.query, docs, k: c.k).map((h) => h.doc.id).toSet();
      for (final id in c.mustInclude) {
        need++;
        if (hits.contains(id)) got++;
      }
    }
    return need == 0 ? 1.0 : got / need;
  }
}
