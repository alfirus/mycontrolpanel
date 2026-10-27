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

  /// Tool route for a provider+model: chat-completions tools (OpenAI-family,
  /// Zen/Go chat family, Ollama), Responses function tools, native Anthropic /
  /// Gemini tools, or plain chat (streamed, no tools).
  static ToolRoute toolRoute(AiProvider provider, String model) {
    switch (provider) {
      case AiProvider.openai:
      case AiProvider.openaiCompatible:
      case AiProvider.openRouter:
      case AiProvider.lmStudio:
      case AiProvider.ollama:
        return ToolRoute.chat;
      case AiProvider.openCodeGo:
        if (_goAnthropicFamily(model)) return ToolRoute.anthropic;
        if (model.toLowerCase() == 'gemini-4-argon') return ToolRoute.gemini;
        if (!_goChatFamily(model)) {
          if (_goResponsesFamily(model)) return ToolRoute.responses;
          return ToolRoute.plain;
        }
        return ToolRoute.chat;
      case AiProvider.openCodeZen:
        if (_zenResponsesFamily(model)) return ToolRoute.responses;
        if (_zenAnthropicFamily(model)) return ToolRoute.anthropic;
        if (_zenGeminiFamily(model)) return ToolRoute.gemini;
        if (_zenChatFamily(model)) return ToolRoute.chat;
        return ToolRoute.plain;
      case AiProvider.anthropic:
        return ToolRoute.anthropic;
      case AiProvider.gemini:
        return ToolRoute.gemini;
    }
  }

  static bool _goResponsesFamily(String model) {
    const s = {
      'grok-4.7', 'gpt-6-luna', 'gpt-5.6-luna',
      'muse-spark-1.3-contributor', 'muse-spark-1.2-contributor',
    };
    return s.contains(model.toLowerCase());
  }

  static bool _zenResponsesFamily(String model) {
    final m = model.toLowerCase();
    return m.startsWith('gpt-') || m.startsWith('grok-') || m.startsWith('muse-spark-');
  }

  static const _goAnthropicModels = {
    'claude-haiku-5-5', 'minimax-m3',
    'qwen3.8-max', 'qwen3.8-flash', 'qwen3.7-plus',
  };
  static bool _goAnthropicFamily(String model) => _goAnthropicModels.contains(model.toLowerCase());

  static bool _zenAnthropicFamily(String model) {
    final m = model.toLowerCase();
    return m.startsWith('claude-') ||
        const {'qwen3.8-flash', 'qwen3.7-max', 'qwen3.7-plus', 'qwen3.6-plus', 'qwen3.5-plus'}
            .contains(m);
  }

  static bool _zenGeminiFamily(String model) => model.toLowerCase().startsWith('gemini-');

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
    String path = '/chat/completions',
  }) async {
    Map<String, dynamic> bodyFor(List<Map<String, dynamic>> tls) => {
          'model': model,
          'messages': [
            {'role': 'system', 'content': system},
            ...messages,
          ],
          'temperature': 0.3,
          if (tls.isNotEmpty) 'tools': tls,
          if (tls.isNotEmpty) 'tool_choice': 'auto',
        };
    Future<http.Response> post(Map<String, dynamic> b) => http.post(Uri.parse('$baseUrl$path'),
        headers: {'Content-Type': 'application/json', ...headers}, body: jsonEncode(b))
        .timeout(const Duration(seconds: 90));
    var r = await post(bodyFor(tools));
    if (r.statusCode == 400 && tools.isNotEmpty) {
      r = await post(bodyFor(const []));
    }
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

  /// Anthropic Messages turn with native tools. [messages] are native
  /// Anthropic message blocks ({role, content}). Returns text + calls plus the
  /// raw assistant blocks the caller must echo back before tool results.
  Future<ChatTurn> anthropicTurn({
    required String baseUrl,
    required String key,
    required String model,
    required String system,
    required List<Map<String, dynamic>> messages,
    required List<Map<String, dynamic>> tools,
    String? endpoint,
    bool gateway = false,
  }) async {
    final base = baseUrl.trim().replaceAll(RegExp(r'/+$'), '');
    final url = endpoint ?? '$base/v1/messages';
    final fnTools = [
      for (final t in tools)
        {
          'name': (((t['function'] as Map?))?['name'] ?? '').toString(),
          'description': ((((t['function'] as Map?))?['description'] ?? '')).toString(),
          'input_schema': (((t['function'] as Map?))?['parameters'] ?? {'type': 'object'}),
        },
    ];
    final body = {
      'model': model,
      'max_tokens': 2048,
      if (system.isNotEmpty) 'system': system,
      'messages': messages,
      if (fnTools.isNotEmpty) 'tools': fnTools,
      if (fnTools.isNotEmpty) 'tool_choice': {'type': 'auto'},
    };
    final r = await http.post(Uri.parse(url),
        headers: {
          'Content-Type': 'application/json',
          'x-api-key': key,
          if (gateway && key.isNotEmpty) 'Authorization': 'Bearer $key',
          'anthropic-version': '2023-06-01',
          'User-Agent': clientAgent,
        },
        body: jsonEncode(body)).timeout(const Duration(seconds: 90));
    if (r.statusCode != 200) throw Exception(_err(r, 'messages'));
    final j = jsonDecode(r.body) as Map;
    final content = ((j['content'] as List?) ?? []).cast<Map<String, dynamic>>();
    final text = StringBuffer();
    final calls = <ToolCall>[];
    for (final b in content) {
      if (b['type'] == 'text') {
        text.writeln((b['text'] ?? '').toString());
      } else if (b['type'] == 'tool_use') {
        var args = <String, dynamic>{};
        final raw = b['input'];
        if (raw is Map) args = Map<String, dynamic>.from(raw);
        calls.add(ToolCall(id: (b['id'] ?? '').toString(), name: (b['name'] ?? '').toString(), arguments: args));
      }
    }
    final t = text.toString().trim();
    return ChatTurn(
      text: t.isEmpty ? null : t,
      calls: calls.where((c) => c.name.isNotEmpty).toList(),
      native: content,
    );
  }

  /// Gemini generateContent turn with native function declarations.
  Future<ChatTurn> geminiTurn({
    required String baseUrl,
    required String key,
    required String model,
    required String system,
    required List<Map<String, dynamic>> contents,
    required List<Map<String, dynamic>> tools,
    String? fullUrl,
    bool gateway = false,
  }) async {
    final base = baseUrl.trim().replaceAll(RegExp(r'/+$'), '');
    final url = fullUrl ?? '$base/v1beta/models/$model:generateContent?key=$key';
    final decls = [
      for (final t in tools)
        {
          'name': (((t['function'] as Map?))?['name'] ?? '').toString(),
          'description': ((((t['function'] as Map?))?['description'] ?? '')).toString(),
          'parameters': (((t['function'] as Map?))?['parameters'] ?? {'type': 'object'}),
        },
    ];
    final body = {
      'system_instruction': {'parts': [{'text': system}]},
      'contents': contents,
      'generationConfig': {'temperature': 0.3, 'maxOutputTokens': 2048},
      if (decls.isNotEmpty) 'tools': [{'functionDeclarations': decls}],
    };
    final r = await http.post(Uri.parse(url),
        headers: {
          'Content-Type': 'application/json',
          'User-Agent': clientAgent,
          if (gateway && key.isNotEmpty) 'Authorization': 'Bearer $key',
        },
        body: jsonEncode(body)).timeout(const Duration(seconds: 90));
    if (r.statusCode != 200) throw Exception(_err(r, 'generateContent'));
    final j = jsonDecode(r.body) as Map;
    final cands = (j['candidates'] as List?) ?? [];
    final parts = (((cands.isEmpty ? null : cands.first as Map?)?['content']?['parts'] as List?) ?? [])
        .cast<Map<String, dynamic>>();
    final text = StringBuffer();
    final calls = <ToolCall>[];
    for (final p in parts) {
      if (p['text'] != null) text.writeln(p['text'].toString());
      final fc = p['functionCall'] as Map?;
      if (fc != null) {
        var args = <String, dynamic>{};
        final raw = fc['args'];
        if (raw is Map) args = Map<String, dynamic>.from(raw);
        calls.add(ToolCall(id: '${fc['name']}_${DateTime.now().millisecondsSinceEpoch}', name: (fc['name'] ?? '').toString(), arguments: args));
      }
    }
    final t = text.toString().trim();
    return ChatTurn(
      text: t.isEmpty ? null : t,
      calls: calls.where((c) => c.name.isNotEmpty).toList(),
      native: parts,
    );
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
  // Keyless Zen serves free `-free` models as literal `Bearer public`.
  Future<String> _zenChat(String base, String key, String model, String system,
      List<Map<String, String>> messages, String? sessionId) async {
    if (key.isEmpty) key = 'public';
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

  /// One Responses-API turn WITH function tools.
  /// [input] is the Responses input-item list (persist across turns).
  Future<ResponsesTurn> responsesTurn({
    required String url,
    required Map<String, String> headers,
    required String model,
    required String instructions,
    required List<Map<String, dynamic>> input,
    required List<Map<String, dynamic>> tools,
  }) async {
    final fnTools = [
      for (final t in tools)
        {
          'type': 'function',
          'name': ((t['function'] as Map?)?['name'] ?? '').toString(),
          'description': (((t['function'] as Map?)?['description'] ?? '')).toString(),
          'parameters': ((t['function'] as Map?)?['parameters'] ?? {'type': 'object', 'properties': {}}),
        },
    ];
    Map<String, dynamic> bodyFor(List<Map<String, dynamic>> tls) => {
          'model': model,
          'instructions': instructions,
          'input': input,
          if (tls.isNotEmpty) 'tools': tls,
        };
    var r = await http.post(Uri.parse(url), headers: headers, body: jsonEncode(bodyFor(fnTools)))
        .timeout(const Duration(seconds: 90));
    // Fallback: model rejects function tools (400) — retry as plain chat.
    if (r.statusCode == 400 && fnTools.isNotEmpty) {
      r = await http.post(Uri.parse(url), headers: headers, body: jsonEncode(bodyFor(const [])))
          .timeout(const Duration(seconds: 90));
    }
    if (r.statusCode != 200) throw Exception(_errStatic(r, 'responses'));
    final j = jsonDecode(r.body) as Map;
    final output = ((j['output'] as List?) ?? []).cast<Map<String, dynamic>>();
    final text = StringBuffer();
    final calls = <ToolCall>[];
    for (final item in output) {
      if (item['type'] == 'message') {
        for (final c in ((item['content'] as List?) ?? [])) {
          final cm = c as Map;
          if (cm['type'] == 'output_text' || cm['type'] == 'text') {
            text.writeln((cm['text'] ?? '').toString());
          }
        }
      } else if (item['type'] == 'function_call') {
        Map<String, dynamic> args = {};
        try {
          final raw = item['arguments'];
          if (raw is Map) {
            args = Map<String, dynamic>.from(raw);
          } else if (raw is String && raw.trim().isNotEmpty) {
            args = Map<String, dynamic>.from(jsonDecode(raw) as Map);
          }
        } catch (_) {}
        calls.add(ToolCall(
          id: (item['call_id'] ?? item['id'] ?? '').toString(),
          name: (item['name'] ?? '').toString(),
          arguments: args,
        ));
      }
    }
    final t = text.toString().trim();
    return ResponsesTurn(text: t.isEmpty ? null : t, calls: calls.where((c) => c.name.isNotEmpty).toList(), outputItems: output);
  }

  /// Streaming plain reply (no tools). Routes per provider, calls onToken
  /// per chunk, returns the full text. Sessions/keys handled like chat().
  Future<String> streamChat({
    required AiProvider provider,
    required String baseUrl,
    required String apiKey,
    required String model,
    required String system,
    required List<Map<String, String>> messages,
    String? sessionId,
    required void Function(String token) onToken,
  }) async {
    final base = baseUrl.trim().replaceAll(RegExp(r'/+$'), '');
    switch (provider) {
      case AiProvider.anthropic:
        return _anthropicStream(base, apiKey, model, system, messages, onToken);
      case AiProvider.gemini:
        return _geminiStream(base, apiKey, model, system, messages, onToken);
      case AiProvider.ollama:
        return _ollamaStream(base, model, system, messages, onToken);
      case AiProvider.openCodeGo:
        if (_goResponsesFamily(model)) {
          return _responsesStream('https://opencode.ai/inference/go/openai/v1/responses', apiKey, model, system, messages, sessionId, onToken);
        }
        if (model.toLowerCase() == 'gemini-4-argon') {
          return _geminiStream('https://opencode.ai/inference/go/google', apiKey, 'gemini-4-argon', system, messages, onToken);
        }
        return _openAiStream('$base/openai/v1', apiKey, model, system, messages, sessionId, p: provider, onToken: onToken);
      case AiProvider.openCodeZen:
        return _zenStreamChat(base, apiKey, model, system, messages, sessionId, onToken: onToken);
      case AiProvider.openai:
      case AiProvider.openaiCompatible:
      case AiProvider.openRouter:
      case AiProvider.lmStudio:
        return _openAiStream(base, apiKey, model, system, messages, sessionId, p: provider, onToken: onToken);
    }
  }

  Future<String> _zenStreamChat(String base, String key, String model, String system,
      List<Map<String, String>> messages, String? sessionId, {required void Function(String) onToken}) async {
    final m = model.toLowerCase();
    final isResponses = m.startsWith('gpt-') || m.startsWith('grok-') || m.startsWith('muse-spark-');
    if (isResponses) {
      return _responsesStream('$base/responses', key.isEmpty ? 'public' : key, model, system, messages, sessionId, onToken);
    }
    if (m.startsWith('claude-')) {
      return _anthropicStream('$base/messages', key, model, system, messages, onToken);
    }
    if (m.startsWith('gemini-')) {
      return _geminiStream('$base/models', key, m, system, messages, onToken, pathSuffix: ':streamGenerateContent?alt=sse');
    }
    return _openAiStream('$base/chat/completions', key, model, system, messages, sessionId, p: AiProvider.openCodeZen, fullUrl: true, onToken: onToken);
  }

  Stream<String> _sseDataLines(http.StreamedResponse resp) async* {
    await for (final chunk in resp.stream.transform(utf8.decoder).transform(const LineSplitter())) {
      final line = chunk.trim();
      if (line.startsWith('data:')) yield line.substring(5).trim();
    }
  }

  /// POST and return the live stream + its client. Caller MUST drain the
  /// stream, then close the client.
  Future<({http.StreamedResponse resp, http.Client client})> _postStream(
      String url, Map<String, String> headers, Map<String, dynamic> body) async {
    final req = http.Request('POST', Uri.parse(url))
      ..headers.addAll({'Content-Type': 'application/json', ...headers})
      ..body = jsonEncode(body);
    final client = http.Client();
    http.StreamedResponse resp;
    try {
      resp = await client.send(req).timeout(const Duration(seconds: 30));
    } catch (e) {
      client.close();
      rethrow;
    }
    if (resp.statusCode != 200) {
      final errBody = await resp.stream.transform(utf8.decoder).join();
      client.close();
      String msg = 'HTTP ${resp.statusCode}';
      try {
        final j = jsonDecode(errBody) as Map;
        final e = j['error'];
        msg = e is Map ? (e['message'] ?? msg).toString() : e.toString();
      } catch (_) {}
      throw Exception(msg);
    }
    return (resp: resp, client: client);
  }

  Future<String> _openAiStream(String base, String key, String model, String system,
      List<Map<String, String>> messages, String? sessionId,
      {required AiProvider p, bool fullUrl = false, required void Function(String) onToken}) async {
    final headers = openAiHeaders(p, key, sessionId);
    final url = fullUrl ? base : '$base/chat/completions';
    final body = {
      'model': model,
      'stream': true,
      'messages': [
        {'role': 'system', 'content': system},
        ...messages,
      ],
      'temperature': 0.3,
    };
    final out = StringBuffer();
    final (:resp, :client) = await _postStream(url, headers, body);
    try {
      await for (final data in _sseDataLines(resp)) {
        if (data == '[DONE]') break;
        try {
          final j = jsonDecode(data) as Map;
          final delta = (((j['choices'] as List?)?.isEmpty ?? true) ? null : (j['choices'] as List).first as Map?)?['delta']?['content'];
          if (delta is String && delta.isNotEmpty) {
            out.write(delta);
            onToken(delta);
          }
        } catch (_) {}
      }
    } finally {
      client.close();
    }
    final text = out.toString().trim();
    if (text.isEmpty) throw Exception('Empty reply from $model');
    return text;
  }

  Future<String> _responsesStream(String url, String key, String model, String system,
      List<Map<String, String>> messages, String? sessionId, void Function(String) onToken) async {
    final transcript = StringBuffer('$system\n\n');
    for (final m in messages) {
      transcript.writeln('${m['role'] == 'assistant' ? 'Assistant' : 'User'}: ${m['content']}');
    }
    final out = StringBuffer();
    final (:resp, :client) = await _postStream(url, _gwHeaders(key, sessionId), {'model': model, 'stream': true, 'input': transcript.toString()});
    try {
      await for (final data in _sseDataLines(resp)) {
        if (data == '[DONE]') break;
        try {
          final j = jsonDecode(data) as Map;
          if (j['type'] == 'response.output_text.delta' && j['delta'] is String) {
            out.write(j['delta'] as String);
            onToken(j['delta'] as String);
          }
        } catch (_) {}
      }
    } finally {
      client.close();
    }
    final text = out.toString().trim();
    if (text.isEmpty) throw Exception('Empty reply from $model');
    return text;
  }

  Future<String> _anthropicStream(String base, String key, String model, String system,
      List<Map<String, String>> messages, void Function(String) onToken) async {
    // base is either the API root (append /v1/messages) or a full messages URL (Zen per-model path).
    final url = base.endsWith('/messages') ? base : '$base/v1/messages';
    final convo = messages.where((m) => m['role'] != 'system').toList();
    final out = StringBuffer();
    final req = http.Request('POST', Uri.parse(url))
      ..headers.addAll({
        'Content-Type': 'application/json',
        'x-api-key': key,
        'anthropic-version': '2023-06-01',
        'Accept': 'text/event-stream',
        'User-Agent': clientAgent,
      })
      ..body = jsonEncode({'model': model, 'max_tokens': 2048, 'system': system, 'messages': convo, 'stream': true});
    final client = http.Client();
    http.StreamedResponse resp;
    try {
      resp = await client.send(req).timeout(const Duration(seconds: 30));
    } catch (e) {
      client.close();
      rethrow;
    }
    if (resp.statusCode != 200) {
      final errBody = await resp.stream.transform(utf8.decoder).join();
      client.close();
      throw Exception(_errStatic(http.Response(errBody, resp.statusCode), 'messages'));
    }
    try {
      String event = '';
      await for (final chunk in resp.stream.transform(utf8.decoder).transform(const LineSplitter())) {
        final line = chunk.trim();
        if (line.startsWith('event:')) {
          event = line.substring(6).trim();
        } else if (line.startsWith('data:')) {
          final data = line.substring(5).trim();
          if (event == 'content_block_delta') {
            try {
              final j = jsonDecode(data) as Map;
              final t = ((j['delta'] as Map?)?['text'] ?? '').toString();
              if (t.isNotEmpty) {
                out.write(t);
                onToken(t);
              }
            } catch (_) {}
          }
        }
      }
    } finally {
      client.close();
    }
    final text = out.toString().trim();
    if (text.isEmpty) throw Exception('Empty reply from $model');
    return text;
  }

  Future<String> _geminiStream(String base, String key, String model, String system,
      List<Map<String, String>> messages, void Function(String) onToken,
      {String pathSuffix = ':streamGenerateContent?alt=sse'}) async {
    // base is normally the API root; Zen passes a per-model path — detect it.
    final isZenModelPath = base.contains('/models/');
    final url = isZenModelPath
        ? '$base$pathSuffix&key=$key'
        : '$base/v1beta/models/$model:streamGenerateContent?alt=sse&key=$key';
    final contents = [
      for (final m in messages)
        {
          'role': m['role'] == 'assistant' ? 'model' : 'user',
          'parts': [
            {'text': m['content']}
          ],
        },
    ];
    final out = StringBuffer();
    final (:resp, :client) = await _postStream(url, {'User-Agent': clientAgent}, {
      'system_instruction': {'parts': [{'text': system}]},
      'contents': contents,
      'generationConfig': {'temperature': 0.3, 'maxOutputTokens': 2048},
    });
    try {
      await for (final data in _sseDataLines(resp)) {
        if (data == '[DONE]') break;
        try {
          final j = jsonDecode(data) as Map;
          final cands = (j['candidates'] as List?) ?? [];
          if (cands.isEmpty) continue;
          final parts = (((cands.first as Map)['content'] as Map?)?['parts'] as List?) ?? [];
          for (final p in parts) {
            final t = (((p as Map)['text']) ?? '').toString();
            if (t.isNotEmpty) {
              out.write(t);
              onToken(t);
            }
          }
        } catch (_) {}
      }
    } finally {
      client.close();
    }
    final text = out.toString().trim();
    if (text.isEmpty) throw Exception('Empty reply from $model');
    return text;
  }

  Future<String> _ollamaStream(String base, String model, String system,
      List<Map<String, String>> messages, void Function(String) onToken) async {
    final out = StringBuffer();
    final req = http.Request('POST', Uri.parse('$base/api/chat'))
      ..headers.addAll({'Content-Type': 'application/json', 'User-Agent': clientAgent})
      ..body = jsonEncode({
        'model': model,
        'stream': true,
        'messages': [
          {'role': 'system', 'content': system},
          ...messages,
        ],
      });
    final client = http.Client();
    http.StreamedResponse resp;
    try {
      resp = await client.send(req).timeout(const Duration(seconds: 30));
    } catch (e) {
      client.close();
      rethrow;
    }
    if (resp.statusCode != 200) {
      final errBody = await resp.stream.transform(utf8.decoder).join();
      client.close();
      String msg = 'HTTP ${resp.statusCode}';
      try {
        msg = ((jsonDecode(errBody) as Map)['error'] ?? msg).toString();
      } catch (_) {}
      throw Exception('$msg — is the model pulled? `ollama pull $model`');
    }
    try {
      await for (final chunk in resp.stream.transform(utf8.decoder).transform(const LineSplitter())) {
        final line = chunk.trim();
        if (line.isEmpty) continue;
        try {
          final j = jsonDecode(line) as Map;
          final t = (((j['message'] as Map?)?['content']) ?? '').toString();
          if (t.isNotEmpty) {
            out.write(t);
            onToken(t);
          }
          if (j['done'] == true) break;
        } catch (_) {}
      }
    } finally {
      client.close();
    }
    final text = out.toString().trim();
    if (text.isEmpty) throw Exception('Empty reply from $model');
    return text;
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

/// How tools are delivered for a provider+model.
enum ToolRoute { chat, responses, anthropic, gemini, plain }

/// A function call requested by the model.
class ToolCall {
  final String id;
  final String name;
  final Map<String, dynamic> arguments;
  const ToolCall({required this.id, required this.name, required this.arguments});
}

/// One assistant turn: final text and/or requested tool calls.
/// [native] carries provider-native assistant blocks the caller must echo
/// back before tool results (Anthropic tool_use blocks, Gemini parts).
class ChatTurn {
  final String? text;
  final List<ToolCall> calls;
  final List<Map<String, dynamic>> native;
  const ChatTurn({this.text, required this.calls, this.native = const []});
}

/// One Responses-API turn: text, function calls, and raw output items
/// (which must be echoed back with function_call_output items).
class ResponsesTurn {
  final String? text;
  final List<ToolCall> calls;
  final List<Map<String, dynamic>> outputItems;
  const ResponsesTurn({this.text, required this.calls, required this.outputItems});
}
