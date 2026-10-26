import 'dart:convert';
import 'package:http/http.dart' as http;

enum AiProvider { openai, openaiCompatible, anthropic, gemini, ollama, openRouter }

extension AiProviderMeta on AiProvider {
  String get label {
    switch (this) {
      case AiProvider.openai: return 'OpenAI';
      case AiProvider.openaiCompatible: return 'OpenAI-compatible (custom)';
      case AiProvider.anthropic: return 'Anthropic';
      case AiProvider.gemini: return 'Google Gemini';
      case AiProvider.ollama: return 'Ollama (local)';
      case AiProvider.openRouter: return 'OpenRouter';
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
    }
  }

  bool get needsKey {
    switch (this) {
      case AiProvider.ollama: return false;
      default: return true;
    }
  }

  String get keyHint {
    switch (this) {
      case AiProvider.openai: return 'sk-…';
      case AiProvider.anthropic: return 'sk-ant-…';
      case AiProvider.gemini: return 'AIza… (API key)';
      case AiProvider.openRouter: return 'sk-or-…';
      case AiProvider.ollama: return 'No key needed';
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
        return _openAiModels(base, apiKey, provider);
    }
  }

  Future<List<String>> _openAiModels(String base, String key, AiProvider p) async {
    final headers = <String, String>{'Authorization': 'Bearer $key'};
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

  String _err(http.Response r, String what) {
    try {
      final j = jsonDecode(r.body) as Map;
      final msg = j['error'] is Map ? j['error']['message'] : j['error'];
      return '${r.statusCode}: ${msg ?? what}';
    } catch (_) {
      return '${r.statusCode} fetching $what';
    }
  }
}
