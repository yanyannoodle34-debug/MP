import 'dart:convert';
import 'package:dio/dio.dart';
import '../models/app_config.dart';
import '../models/scene.dart';

class LlmService {
  final Dio _dio = Dio();

  // ── Script generation ──────────────────────────────────────────────────────

  Future<VideoScript> generateScript(String topic, AppConfig cfg) async {
    final n = cfg.sceneCount;

    // NOTE: the word "json" must appear in the prompt for DeepSeek's JSON mode
    // (their API rejects json_object without it).
    final system = '''
You are a short-form video scriptwriter. Write an engaging $n-scene narration
and craft a vivid image-generation prompt for each scene.
Return ONLY valid JSON — no markdown fences, no prose before or after.
''';

    final user = '''
Topic: "$topic"
Number of scenes: $n

Return JSON with exactly this structure:
{
  "title": "<short video title>",
  "scenes": [
    {
      "narration": "<10–30 words of spoken narration for this scene>",
      "image_prompt": "<detailed visual prompt for AI image generation, cinematic, ~20 words>",
      "search_terms": "<2–4 concrete visual keywords for stock-video search, e.g. 'sunset ocean waves'>"
    }
  ]
}

Rules:
- Each narration is natural spoken prose, no stage directions.
- image_prompt is vivid, specific, ~20 words (used if the app is set to AI images).
- search_terms is short, concrete, searchable stock-video keywords (used for Pexels/Pixabay/Coverr).
- No special characters in narration that break TTS.
- Output valid JSON only.
''';

    Map<String, dynamic> buildBody({required bool withJsonMode}) => {
          'model': cfg.llmModel,
          'messages': [
            {'role': 'system', 'content': system},
            {'role': 'user', 'content': user},
          ],
          'temperature': 0.75,
          'max_tokens': 2048,
          if (withJsonMode) 'response_format': {'type': 'json_object'},
        };

    // First attempt: with JSON mode (works on OpenAI, DeepSeek, OpenRouter most models)
    String content;
    try {
      content = await _chat(cfg, buildBody(withJsonMode: true));
    } on DioException catch (e) {
      // If the model rejects response_format (e.g. some OpenRouter models don't
      // support it), retry without.
      final msg = _extractError(e.response?.data).toLowerCase();
      final looksLikeJsonModeReject = msg.contains('response_format') ||
          msg.contains('json_object') ||
          e.response?.statusCode == 400;
      if (looksLikeJsonModeReject) {
        content = await _chat(cfg, buildBody(withJsonMode: false));
      } else {
        rethrow;
      }
    }

    final parsed = _extractJson(content);
    final title = (parsed['title'] as String?)?.trim();
    final rawScenes = parsed['scenes'] as List?;
    if (rawScenes == null || rawScenes.isEmpty) {
      throw Exception(
        'LLM returned no scenes. Try a different model or shorter topic.',
      );
    }

    final scenes = rawScenes.asMap().entries.map((e) {
      final s = e.value as Map<String, dynamic>;
      return Scene(
        index: e.key,
        narration: (s['narration'] as String? ?? '').trim(),
        imagePrompt: (s['image_prompt'] as String? ?? '').trim(),
        searchQuery: (s['search_terms'] as String? ?? '').trim(),
      );
    }).where((s) => s.narration.isNotEmpty).toList();

    if (scenes.isEmpty) {
      throw Exception('LLM returned empty scenes.');
    }

    return VideoScript(
      title: (title == null || title.isEmpty) ? topic : title,
      scenes: scenes,
    );
  }

  Future<String> _chat(AppConfig cfg, Map<String, dynamic> body) async {
    final resp = await _dio.post(
      '${cfg.llmBaseUrl}/chat/completions',
      options: Options(
        headers: _headers(cfg),
        receiveTimeout: const Duration(seconds: 90),
        sendTimeout: const Duration(seconds: 30),
      ),
      data: body,
    );
    return resp.data['choices'][0]['message']['content'] as String;
  }

  /// Robust JSON extraction — handles markdown fences, prose padding, and
  /// leading BOM/whitespace.
  Map<String, dynamic> _extractJson(String raw) {
    var text = raw.trim();

    // Strip ```json … ``` fences if present.
    if (text.startsWith('```')) {
      text = text.replaceAll(RegExp(r'^```(?:json)?\s*', multiLine: false), '');
      text = text.replaceAll(RegExp(r'\s*```\s*$', multiLine: false), '');
    }

    // Try direct parse first.
    try {
      final v = jsonDecode(text);
      if (v is Map<String, dynamic>) return v;
    } catch (_) {}

    // Fallback: extract the outermost {...} block.
    final start = text.indexOf('{');
    final end = text.lastIndexOf('}');
    if (start >= 0 && end > start) {
      final slice = text.substring(start, end + 1);
      try {
        final v = jsonDecode(slice);
        if (v is Map<String, dynamic>) return v;
      } catch (_) {}
    }

    throw Exception(
      'LLM did not return valid JSON. First 200 chars:\n${text.substring(0, text.length.clamp(0, 200))}',
    );
  }

  // ── Model listing ──────────────────────────────────────────────────────────

  Future<List<String>> fetchModels(AppConfig cfg) async {
    final resp = await _dio.get(
      '${cfg.llmBaseUrl}/models',
      options: Options(
        headers: _headers(cfg),
        receiveTimeout: const Duration(seconds: 20),
      ),
    );

    final data = resp.data['data'] as List?;
    if (data == null) return [];

    final ids = data
        .map((m) => (m['id'] as String?) ?? '')
        .where((s) => s.isNotEmpty)
        .toList();

    // Filter out non-chat models heuristically.
    final chatOnly = ids.where((id) {
      final lower = id.toLowerCase();
      return !lower.contains('embed') &&
          !lower.contains('whisper') &&
          !lower.contains('tts') &&
          !lower.contains('dall-e') &&
          !lower.contains('audio') &&
          !lower.contains('moderation');
    }).toList();

    chatOnly.sort();
    return chatOnly;
  }

  // ── Key validation ─────────────────────────────────────────────────────────

  Future<String?> testKey(AppConfig cfg) async {
    try {
      final r = await _dio.get(
        '${cfg.llmBaseUrl}/models',
        options: Options(
          headers: _headers(cfg),
          receiveTimeout: const Duration(seconds: 15),
          validateStatus: (_) => true,
        ),
      );
      if (r.statusCode == null || r.statusCode! < 200 || r.statusCode! >= 300) {
        return 'HTTP ${r.statusCode}: ${_extractError(r.data)}';
      }
      return null;
    } catch (e) {
      return _friendlyError(e);
    }
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  Map<String, dynamic> _headers(AppConfig cfg) {
    final h = <String, dynamic>{
      'Authorization': 'Bearer ${cfg.llmApiKey}',
      'Content-Type': 'application/json',
    };
    if (cfg.llmProvider == LlmProvider.openrouter) {
      h['HTTP-Referer'] = 'https://github.com/yanyannoodle34-debug/MP';
      h['X-Title'] = 'CloudAI Creator';
    }
    return h;
  }

  String _extractError(dynamic body) {
    if (body is Map) {
      final err = body['error'];
      if (err is Map) return (err['message'] as String?) ?? body.toString();
      if (err is String) return err;
      return (body['message'] as String?) ?? body.toString();
    }
    return body?.toString() ?? 'unknown error';
  }

  String _friendlyError(Object e) {
    if (e is DioException) {
      if (e.response != null) {
        return 'HTTP ${e.response!.statusCode}: ${_extractError(e.response!.data)}';
      }
      return e.message ?? 'Network error';
    }
    return e.toString();
  }
}
