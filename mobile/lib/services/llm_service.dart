import 'dart:convert';
import 'package:dio/dio.dart';
import '../models/app_config.dart';
import '../models/scene.dart';

class LlmService {
  final Dio _dio = Dio();

  // ── Script generation ──────────────────────────────────────────────────────

  Future<VideoScript> generateScript(String topic, AppConfig cfg) async {
    final n = cfg.sceneCount;

    final system = '''
You are a short-form video scriptwriter. Write an engaging $n-scene narration
and craft a vivid image-generation prompt for each scene.
Return ONLY valid JSON — no markdown, no extra keys.
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
      "image_prompt": "<detailed visual prompt for an AI image generator, photorealistic, cinematic>"
    }
  ]
}

Rules:
- Each narration is natural spoken prose, no stage directions.
- Each image_prompt is vivid, specific, ~20 words, appended with "cinematic 4K 9:16 portrait".
- No special characters in narration that break TTS.
''';

    final data = <String, dynamic>{
      'model': cfg.llmModel,
      'messages': [
        {'role': 'system', 'content': system},
        {'role': 'user', 'content': user},
      ],
      'temperature': 0.75,
      'max_tokens': 2048,
    };
    // DeepSeek and OpenAI-compatible providers all support response_format,
    // but OpenRouter forwards it selectively — safest to send when known.
    if (cfg.llmProvider != LlmProvider.deepseek) {
      data['response_format'] = {'type': 'json_object'};
    }

    final resp = await _dio.post(
      '${cfg.llmBaseUrl}/chat/completions',
      options: Options(
        headers: _headers(cfg),
        receiveTimeout: const Duration(seconds: 90),
        sendTimeout: const Duration(seconds: 30),
      ),
      data: data,
    );

    var content = resp.data['choices'][0]['message']['content'] as String;
    // Some providers wrap JSON in ```json fences — strip if present.
    content = content.trim();
    if (content.startsWith('```')) {
      content = content.replaceAll(RegExp(r'^```(?:json)?\s*|\s*```$'), '');
    }

    final Map<String, dynamic> parsed = jsonDecode(content);

    final title = parsed['title'] as String? ?? topic;
    final rawScenes = parsed['scenes'] as List?;
    if (rawScenes == null || rawScenes.isEmpty) {
      throw Exception('LLM returned no scenes.');
    }

    final scenes = rawScenes.asMap().entries.map((e) {
      final s = e.value as Map<String, dynamic>;
      return Scene(
        index: e.key,
        narration: s['narration'] as String? ?? '',
        imagePrompt: s['image_prompt'] as String? ?? '',
      );
    }).toList();

    return VideoScript(title: title, scenes: scenes);
  }

  // ── Model listing ──────────────────────────────────────────────────────────

  /// GET /models — returns model IDs available to this API key.
  /// Works on any OpenAI-compatible provider (OpenRouter, OpenAI, DeepSeek).
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

    // Filter out non-chat models (embeddings, tts, whisper) heuristically.
    final chatOnly = ids.where((id) {
      final lower = id.toLowerCase();
      return !lower.contains('embed') &&
          !lower.contains('whisper') &&
          !lower.contains('tts') &&
          !lower.contains('dall-e') &&
          !lower.contains('audio');
    }).toList();

    chatOnly.sort();
    return chatOnly;
  }

  // ── Key validation ─────────────────────────────────────────────────────────

  /// Quick auth check: try GET /models. Returns null on success, error message on failure.
  Future<String?> testKey(AppConfig cfg) async {
    try {
      await _dio.get(
        '${cfg.llmBaseUrl}/models',
        options: Options(
          headers: _headers(cfg),
          receiveTimeout: const Duration(seconds: 15),
          validateStatus: (_) => true,
        ),
      ).then((r) {
        if (r.statusCode == null || r.statusCode! < 200 || r.statusCode! >= 300) {
          throw Exception('HTTP ${r.statusCode}: ${_extractError(r.data)}');
        }
      });
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
