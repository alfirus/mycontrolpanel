import 'dart:convert';
import 'package:http/http.dart' as http;

enum AiProvider { openai, openaiCompatible, anthropic, gemini, ollama, openRouter, lmStudio, openCodeZen, openCodeGo }

extension AiProviderMeta on AiProvider {
  String get label {
    switch (this) {
      case AiProvider.openai: return 'OpenAI';
      case AiProvider.openaiCompatible: return 'OpenAI-compatible (custom)';
      case AiProvider.anthropic: return 'Anthropic';
      case AiProvider.gemini: return 'Google Gemini';
      case AiProvider.ollama: return 'Ollama (local)';
      case AiProvider.openRouter: return 'OpenRouter';
      case AiProvider.lmStudio: return 'LM Studio (local)';
      case AiProvider.openCodeZen: return 'OpenCode Zen';
      case AiProvider.openCodeGo: return 'OpenCode Go';
    }
  }

  String get defaultBaseUrl {
    switch (this) {
      case AiProvider.openai: return 'https://api.openai.com/v1';
      case AiProvider.openaiCompatible: return 'https://your-host/v1';
      case AiProvider.anthropic: return 'https://api.anthropic.com';
      case AiProvider.gemini: return 'https://generativelanguage.googleapis.com';
      case AiProvider.ollama: return 'http://localhost:11434';
      case AiProvider.openRouter: return 'https://openrouter.ai/api/v1';
      // LM Studio: built-in OpenAI-compatible server (enable in app: Developer → Start Server, default port 1234)
      case AiProvider.lmStudio: return 'http://localhost:1234/v1';
      // OpenCode Zen: pay-per-use gateway, OpenAI-compatible. Model catalog: GET {base}/models
      case AiProvider.openCodeZen: return 'https://opencode.ai/zen/v1';
      // OpenCode Go: subscription gateway (same OPENCODE_API_KEY family). Catalog: GET {base}/models
      case AiProvider.openCodeGo: return 'https://opencode.ai/zen/go/v1';
    }
  }

  bool get needsKey {
    switch (this) {
      case AiProvider.ollama:
      case AiProvider.lmStudio:
        return false;
      case AiProvider.openai:
      case AiProvider.openaiCompatible:
      case AiProvider.anthropic:
      case AiProvider.gemini:
      case AiProvider.openRouter:
      case AiProvider.openCodeZen:
      case AiProvider.openCodeGo:
        return true;
    }
  }

  String get keyHint {
    switch (this) {
      case AiProvider.openai: return 'sk-…';
      case AiProvider.anthropic: return 'sk-ant-…';
      case AiProvider.gemini: return 'AIza… (API key)';
      case AiProvider.openRouter: return 'sk-or-…';
      case AiProvider.ollama: return 'No key needed (local)';
      case AiProvider.lmStudio: return 'No key needed (local)';
      case AiProvider.openCodeZen: return 'Zen API key (opencode.ai → /connect)';
      case AiProvider.openCodeGo: return 'Go API key (opencode.ai/auth)';
      case AiProvider.openaiCompatible: return 'Bearer token';
    }
  }
}

/// Lists chat models for a provider. OpenAI-compatible + OpenRouter use
/// GET {base}/models. Gemini uses GET {base}/v1beta/models?key=…. Ollama
/// uses GET {base}/api/tags. Anthropic has no list endpoint — curated list.
class AiService {
  static const List<String> anthropicModels = [
    'claude-opus-4-1-20250805',
    'claude-sonnet-4-20250514',
    'claude-3-7-sonnet-20250219',
    'claude-3-5-haiku-20241022',
    'claude-3-5-sonnet-20241022',
  ];

  Future<List<String>> listModels({
    required AiProvider provider,
    required String baseUrl,
    required String apiKey,
  }) async {
    final base = baseUrl.trim().replaceAll(RegExp(r'/+$'), '');
    switch (provider) {
      case AiProvider.anthropic:
        return List.of(anthropicModels);
      case AiProvider.ollama:
        return _ollamaModels(base);
      case AiProvider.gemini:
        return _geminiModels(base, apiKey);
      case AiProvider.openai:
      case AiProvider.openaiCompatible:
      case AiProvider.openRouter:
      case AiProvider.lmStudio:
      case AiProvider.openCodeZen:
      case AiProvider.openCodeGo:
        return _openAiModels(base, apiKey, provider);
    }
  }

  Future<List<String>> _openAiModels(String base, String key, AiProvider p) async {
    // Local providers (LM Studio) work keyless — omit auth instead of sending an empty bearer.
    // Zen also serves free `-free` models with the literal `Bearer public` token.
    final headers = <String, String>{if (key.isNotEmpty) 'Authorization': 'Bearer $key'};
    if (p == AiProvider.openRouter) {
      headers['HTTP-Referer'] = 'https://mycontrolpanel.local';
      headers['X-Title'] = 'MyControlPanel';
    }
    final r = await http.get(Uri.parse('$base/models'), headers: headers);
    if (r.statusCode != 200) throw Exception(_err(r, 'models'));
    final data = ((jsonDecode(r.body) as Map)['data'] as List?) ?? [];
    final ids = data.map((e) => ((e as Map)['id'] ?? '').toString()).where((s) => s.isNotEmpty).toList()..sort();
    if (ids.isEmpty) throw Exception('No models returned by $base/models');
    return ids;
  }

  Future<List<String>> _geminiModels(String base, String key) async {
    final r = await http.get(Uri.parse('$base/v1beta/models?key=$key'));
    if (r.statusCode != 200) throw Exception(_err(r, 'models'));
    final data = ((jsonDecode(r.body) as Map)['models'] as List?) ?? [];
    // names look like "models/gemini-2.0-flash" — strip prefix, keep chat-capable
    final ids = data
        .map((e) => ((e as Map)['name'] ?? '').toString().replaceFirst('models/', ''))
        .where((s) => s.isNotEmpty && !s.contains('embedding') && !s.contains('vision'))
        .toList()
      ..sort();
    if (ids.isEmpty) throw Exception('No models returned by Gemini API');
    return ids;
  }

  Future<List<String>> _ollamaModels(String base) async {
    final r = await http.get(Uri.parse('$base/api/tags'));
    if (r.statusCode != 200) throw Exception(_err(r, 'api/tags — is Ollama running? try `ollama serve`'));
    final data = ((jsonDecode(r.body) as Map)['models'] as List?) ?? [];
    final ids = data.map((e) => ((e as Map)['name'] ?? '').toString()).where((s) => s.isNotEmpty).toList()..sort();
    if (ids.isEmpty) throw Exception('Ollama has no models — `ollama pull llama3.1` first');
    return ids;
  }

  /// Chat completion. `messages` = [{role, content}]. Returns assistant text.
  /// OpenAI-compatible (OpenAI/custom/OpenRouter/LM Studio/Zen/Go): POST {base}/chat/completions
  /// Ollama: POST {base}/api/chat (non-stream). Anthropic: POST {base}/v1/messages.
  /// Gemini: POST {base}/v1beta/models/{model}:generateContent.
  static const String clientAgent = 'MyControlPanel/1.0';

  /// Whether this provider+model speaks OpenAI chat-completions (hence tools).
  /// Responses/Anthropic/Gemini-routed models (some Zen/Go) use plain chat.
  static bool usesChatCompletions(AiProvider provider, String model) {
    switch (provider) {
      case AiProvider.openai:
      case AiProvider.openaiCompatible:
      case AiProvider.openRouter:
      case AiProvider.lmStudio:
        return true;
      case AiProvider.ollama:
      case AiProvider.anthropic:
      case AiProvider.gemini:
        return false;
      case AiProvider.openCodeGo:
        return _goChatFamily(model);
      case AiProvider.openCodeZen:
        return _zenChatFamily(model);
    }
  }

  static bool _goChatFamily(String model) {
    final m = model.toLowerCase();
    const nonChat = {
      'grok-4.7', 'gpt-6-luna', 'gpt-5.6-luna',
      'muse-spark-1.3-contributor', 'muse-spark-1.2-contributor',
      'claude-haiku-5.5', 'minimax-m3',
      'qwen3.8-max', 'qwen3.8-flash', 'qwen3.7-plus',
      'gemini-4-argon',
    };
    return !nonChat.contains(m);
  }

  static bool _zenChatFamily(String model) {
    final m = model.toLowerCase();
    if (m.startsWith('gpt-') || m.startsWith('grok-') || m.startsWith('muse-spark-')) return false;
    if (m.startsWith('claude-') ||
        {'qwen3.8-flash', 'qwen3.7-max', 'qwen3.7-plus', 'qwen3.6-plus', 'qwen3.5-plus'}.contains(m)) return false;
    if (m.startsWith('gemini-')) return false;
    return true;
  }

  /// Inference base for chatTurn (Go chat-family lives under inference root).
  static String chatBase(AiProvider provider, String configuredBase) {
    if (provider == AiProvider.openCodeGo) return 'https://opencode.ai/inference/go/openai/v1';
    return configuredBase;
  }

  /// A tool call requested by the model (OpenAI-compatible format).
  static ToolCall parseToolCall(Map<String, dynamic> j) {
    final fn = (j['function'] as Map?) ?? const {};
    Map<String, dynamic> args = {};
    try {
      final raw = fn['arguments'];
      if (raw is Map) {
        args = Map<String, dynamic>.from(raw);
      } else if (raw is String && raw.trim().isNotEmpty) {
        args = Map<String, dynamic>.from(jsonDecode(raw) as Map);
      }
    } catch (_) {}
    return ToolCall(
      id: (j['id'] ?? '').toString(),
      name: (fn['name'] ?? '').toString(),
      arguments: args,
    );
  }

  /// One chat-completions turn WITH tools. Used by OpenAI-compatible
  /// providers (OpenAI, custom, OpenRouter, LM Studio, Ollama, Zen/Go chat family).
  /// Returns text and/or tool calls for the caller loop to handle.
  Future<ChatTurn> chatTurn({
    required String baseUrl,
    required Map<String, String> headers,
    required String model,
    required String system,
    required List<Map<String, String>> messages,
    required List<Map<String, dynamic>> tools,
  }) async {
    final body = {
      'model': model,
      'messages': [
        {'role': 'system', 'content': system},
        ...messages,
      ],
      'temperature': 0.3,
      if (tools.isNotEmpty) 'tools': tools,
      if (tools.isNotEmpty) 'tool_choice': 'auto',
    };
    final r = await http.post(Uri.parse('$baseUrl/chat/completions'),
        headers: {'Content-Type': 'application/json', ...headers}, body: jsonEncode(body))
        .timeout(const Duration(seconds: 90));
    if (r.statusCode != 200) throw Exception(_err(r, 'chat'));
    final j = jsonDecode(r.body) as Map;
    final choices = (j['choices'] as List?) ?? [];
    if (choices.isEmpty) throw Exception('Empty reply from $model');
    final msg = (choices.first as Map)['message'] as Map? ?? {};
    final text = (msg['content'] ?? '').toString().trim();
    final calls = (((msg['tool_calls'] as List?) ?? [])
            .map((c) => parseToolCall(c as Map<String, dynamic>))
            .where((c) => c.name.isNotEmpty))
        .toList();
    return ChatTurn(text: text.isEmpty ? null : text, calls: calls);
  }

  Map<String, String> openAiHeaders(AiProvider p, String key, String? sessionId) {
    final headers = <String, String>{
      'User-Agent': clientAgent,
      if (key.isNotEmpty) 'Authorization': 'Bearer $key',
      if (sessionId != null && sessionId.isNotEmpty) 'x-opencode-session': sessionId,
    };
    if (p == AiProvider.openRouter) {
      headers['HTTP-Referer'] = 'https://mycontrolpanel.local';
      headers['X-Title'] = 'MyControlPanel';
    }
    return headers;
  }

  Future<String> chat({
    required AiProvider provider,
    required String baseUrl,
    required String apiKey,
    required String model,
    required String system,
    required List<Map<String, String>> messages,
    String? sessionId,
  }) async {
    final base = baseUrl.trim().replaceAll(RegExp(r'/+$'), '');
    switch (provider) {
      case AiProvider.anthropic:
        return _anthropicChat(base, apiKey, model, system, messages);
      case AiProvider.gemini:
        return _geminiChat(base, apiKey, model, system, messages);
      case AiProvider.ollama:
        return _ollamaChat(base, model, system, messages);
      case AiProvider.openCodeGo:
        return _goChat(base, apiKey, model, system, messages, sessionId);
      case AiProvider.openCodeZen:
        return _zenChat(base, apiKey, model, system, messages, sessionId);
      case AiProvider.openai:
      case AiProvider.openaiCompatible:
      case AiProvider.openRouter:
      case AiProvider.lmStudio:
        return _openAiChat(base, apiKey, model, system, messages, provider);
    }
  }

  // --- OpenCode Go: multi-protocol gateway. Requires stable
  // x-opencode-session per conversation + identifying User-Agent.
  // NOTE: the catalog base (…/zen/go/v1, used for GET /models) is NOT the
  // inference root. Inference endpoints are documented at
  // https://opencode.ai/docs/go/#endpoints under
  // https://opencode.ai/inference/go/… — using those verbatim.
  Future<String> _goChat(String base, String key, String model, String system,
      List<Map<String, String>> messages, String? sessionId) async {
    const root = 'https://opencode.ai/inference/go';
    const responsesModels = {
      'grok-4.7', 'gpt-6-luna', 'gpt-5.6-luna',
      'muse-spark-1.3-contributor', 'muse-spark-1.2-contributor',
    };
    const anthropicModels = {
      'claude-haiku-5.5', 'minimax-m3',
      'qwen3.8-max', 'qwen3.8-flash', 'qwen3.7-plus',
    };
    final m = model.toLowerCase();
    if (responsesModels.contains(m)) {
      return _responsesChat('$root/openai/v1/responses', key, model, system, messages, sessionId);
    }
    if (anthropicModels.contains(m)) {
      return _anthropicViaGateway('$root/anthropic/v1/messages', key, model, system, messages, sessionId);
    }
    if (m == 'gemini-4-argon') {
      return _geminiViaGateway('$root/google/v1beta/models/gemini-4-argon:generateContent', key, model, system, messages, sessionId);
    }
    // default: OpenAI chat completions family (GLM, Kimi, DeepSeek, MiMo, Hy, …)
    return _openAiChat('$root/openai/v1', key, model, system, messages, AiProvider.openCodeGo, sessionId: sessionId);
  }

  // --- OpenCode Zen: same multi-protocol shape under /zen/v1.
  Future<String> _zenChat(String base, String key, String model, String system,
      List<Map<String, String>> messages, String? sessionId) async {
    final m = model.toLowerCase();
    final isResponses = m.startsWith('gpt-') || m.startsWith('grok-') || m.startsWith('muse-spark-');
    final isAnthropic = m.startsWith('claude-') ||
        {'qwen3.8-flash', 'qwen3.7-max', 'qwen3.7-plus', 'qwen3.6-plus', 'qwen3.5-plus'}.contains(m);
    final isGemini = m.startsWith('gemini-');
    if (isResponses) {
      return _responsesChat('$base/responses', key, model, system, messages, sessionId);
    }
    if (isAnthropic) {
      return _anthropicViaGateway('$base/messages', key, model, system, messages, sessionId);
    }
    if (isGemini) {
      return _geminiViaGateway('$base/models/$m', key, model, system, messages, sessionId);
    }
    return _openAiChat('$base/chat/completions', key, model, system, messages, AiProvider.openCodeZen,
        sessionId: sessionId, fullUrl: true);
  }

  Map<String, String> _gwHeaders(String key, String? sessionId) => {
        'Content-Type': 'application/json',
        'User-Agent': clientAgent,
        if (key.isNotEmpty) 'Authorization': 'Bearer $key',
        if (sessionId != null && sessionId.isNotEmpty) 'x-opencode-session': sessionId,
      };

  /// OpenAI Responses API: {model, input} -> output[].message.content[].text
  Future<String> _responsesChat(String url, String key, String model, String system,
      List<Map<String, String>> messages, String? sessionId) async {
    final transcript = StringBuffer('$system\n\n');
    for (final m in messages) {
      transcript.writeln('${m['role'] == 'assistant' ? 'Assistant' : 'User'}: ${m['content']}');
    }
    final r = await http.post(Uri.parse(url), headers: _gwHeaders(key, sessionId),
        body: jsonEncode({'model': model, 'input': transcript.toString()})).timeout(const Duration(seconds: 90));
    if (r.statusCode != 200) throw Exception(_err(r, 'responses'));
    final j = jsonDecode(r.body) as Map;
    final out = StringBuffer();
    for (final item in ((j['output'] as List?) ?? [])) {
      final im = item as Map;
      if (im['type'] == 'message') {
        for (final c in ((im['content'] as List?) ?? [])) {
          final cm = c as Map;
          if (cm['type'] == 'output_text' || cm['type'] == 'text') {
            out.writeln((cm['text'] ?? '').toString());
          }
        }
      }
    }
    final text = out.toString().trim();
    if (text.isEmpty) throw Exception('Empty reply from $model (responses API)');
    return text;
  }

  /// Anthropic Messages via Go/Zen gateway (same wire format, gateway auth).
  Future<String> _anthropicViaGateway(String url, String key, String model, String system,
      List<Map<String, String>> messages, String? sessionId) async {
    final convo = messages.where((m) => m['role'] != 'system').toList();
    final headers = _gwHeaders(key, sessionId)..['anthropic-version'] = '2023-06-01';
    final r = await http.post(Uri.parse(url), headers: headers,
        body: jsonEncode({'model': model, 'max_tokens': 1024, 'system': system, 'messages': convo}))
        .timeout(const Duration(seconds: 90));
    if (r.statusCode != 200) throw Exception(_err(r, 'messages'));
    final j = jsonDecode(r.body) as Map;
    final content = (j['content'] as List?) ?? [];
    final text = content.map((b) => ((b as Map)['text'] ?? '').toString()).join('\n').trim();
    if (text.isEmpty) throw Exception('Empty reply from $model');
    return text;
  }

  /// Gemini generateContent via Go/Zen gateway.
  Future<String> _geminiViaGateway(String url, String key, String model, String system,
      List<Map<String, String>> messages, String? sessionId) async {
    final contents = [
      for (final m in messages)
        {
          'role': m['role'] == 'assistant' ? 'model' : 'user',
          'parts': [
            {'text': m['content']}
          ],
        },
    ];
    final r = await http.post(Uri.parse(url), headers: _gwHeaders(key, sessionId),
        body: jsonEncode({
          'system_instruction': {'parts': [{'text': system}]},
          'contents': contents,
          'generationConfig': {'temperature': 0.3, 'maxOutputTokens': 1024},
        })).timeout(const Duration(seconds: 90));
    if (r.statusCode != 200) throw Exception(_err(r, 'generateContent'));
    final j = jsonDecode(r.body) as Map;
    final cands = (j['candidates'] as List?) ?? [];
    final parts = ((cands.isEmpty ? null : cands.first as Map?)?['content']?['parts'] as List?) ?? [];
    final text = parts.map((p) => ((p as Map)['text'] ?? '').toString()).join('\n').trim();
    if (text.isEmpty) throw Exception('Empty reply from $model');
    return text;
  }

  Future<String> _openAiChat(String base, String key, String model, String system,
      List<Map<String, String>> messages, AiProvider p, {String? sessionId, bool fullUrl = false}) async {
    final headers = <String, String>{
      'Content-Type': 'application/json',
      'User-Agent': clientAgent,
      if (key.isNotEmpty) 'Authorization': 'Bearer $key',
      if (sessionId != null && sessionId.isNotEmpty) 'x-opencode-session': sessionId,
    };
    if (p == AiProvider.openRouter) {
      headers['HTTP-Referer'] = 'https://mycontrolpanel.local';
      headers['X-Title'] = 'MyControlPanel';
    }
    final body = {
      'model': model,
      'messages': [
        {'role': 'system', 'content': system},
        ...messages,
      ],
      'temperature': 0.3,
    };
    final url = fullUrl ? base : '$base/chat/completions';
    final r = await http.post(Uri.parse(url), headers: headers, body: jsonEncode(body))
        .timeout(const Duration(seconds: 90));
    if (r.statusCode != 200) throw Exception(_err(r, 'chat'));
    final j = jsonDecode(r.body) as Map;
    final choices = (j['choices'] as List?) ?? [];
    final text = ((choices.isEmpty ? null : choices.first as Map?)?['message']?['content'] ?? '').toString().trim();
    if (text.isEmpty) throw Exception('Empty reply from $model');
    return text;
  }

  Future<String> _ollamaChat(String base, String model, String system, List<Map<String, String>> messages) async {
    final r = await http.post(
      Uri.parse('$base/api/chat'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'model': model,
        'stream': false,
        'messages': [
          {'role': 'system', 'content': system},
          ...messages,
        ],
      }),
    ).timeout(const Duration(seconds: 120));
    if (r.statusCode != 200) throw Exception(_err(r, 'chat — is the model pulled? `ollama pull $model`'));
    final text = ((jsonDecode(r.body) as Map)['message']?['content'] ?? '').toString().trim();
    if (text.isEmpty) throw Exception('Empty reply from $model');
    return text;
  }

  Future<String> _anthropicChat(String base, String key, String model, String system,
      List<Map<String, String>> messages) async {
    // Anthropic messages API: system is top-level, messages are user/assistant only.
    final convo = messages.where((m) => m['role'] != 'system').toList();
    final r = await http.post(
      Uri.parse('$base/v1/messages'),
      headers: {
        'Content-Type': 'application/json',
        'x-api-key': key,
        'anthropic-version': '2023-06-01',
      },
      body: jsonEncode({'model': model, 'max_tokens': 1024, 'system': system, 'messages': convo}),
    ).timeout(const Duration(seconds: 60));
    if (r.statusCode != 200) throw Exception(_err(r, 'messages'));
    final j = jsonDecode(r.body) as Map;
    final content = (j['content'] as List?) ?? [];
    final text = content.map((b) => ((b as Map)['text'] ?? '').toString()).join('\n').trim();
    if (text.isEmpty) throw Exception('Empty reply from $model');
    return text;
  }

  Future<String> _geminiChat(String base, String key, String model, String system,
      List<Map<String, String>> messages) async {
    // Gemini: system via system_instruction, roles user/model.
    final contents = [
      for (final m in messages)
        {
          'role': m['role'] == 'assistant' ? 'model' : 'user',
          'parts': [
            {'text': m['content']}
          ],
        },
    ];
    final r = await http.post(
      Uri.parse('$base/v1beta/models/$model:generateContent?key=$key'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'system_instruction': {'parts': [{'text': system}]},
        'contents': contents,
        'generationConfig': {'temperature': 0.3, 'maxOutputTokens': 1024},
      }),
    ).timeout(const Duration(seconds: 60));
    if (r.statusCode != 200) throw Exception(_err(r, 'generateContent'));
    final j = jsonDecode(r.body) as Map;
    final cands = (j['candidates'] as List?) ?? [];
    final parts = ((cands.isEmpty ? null : cands.first as Map?)?['content']?['parts'] as List?) ?? [];
    final text = parts.map((p) => ((p as Map)['text'] ?? '').toString()).join('\n').trim();
    if (text.isEmpty) throw Exception('Empty reply from $model');
    return text;
  }

  String _err(http.Response r, String what) {
    return _errStatic(r, what);
  }

  static String _errStatic(http.Response r, String what) {
    try {
      final j = jsonDecode(r.body) as Map;
      final msg = j['error'] is Map ? j['error']['message'] : j['error'];
      return '${r.statusCode}: ${msg ?? what}';
    } catch (_) {
      return '${r.statusCode} fetching $what';
    }
  }
}

/// A function call requested by the model.
class ToolCall {
  final String id;
  final String name;
  final Map<String, dynamic> arguments;
  const ToolCall({required this.id, required this.name, required this.arguments});
}

/// One assistant turn: final text and/or requested tool calls.
class ChatTurn {
  final String? text;
  final List<ToolCall> calls;
  const ChatTurn({this.text, required this.calls});
}
