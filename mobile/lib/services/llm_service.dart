import 'dart:convert';
import 'package:dio/dio.dart';
import '../models/app_config.dart';
import '../models/scene.dart';

class LlmService {
  final Dio _dio = Dio();

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

    final resp = await _dio.post(
      '${cfg.llmBaseUrl}/chat/completions',
      options: Options(
        headers: {
          'Authorization': 'Bearer ${cfg.llmApiKey}',
          'Content-Type': 'application/json',
          if (cfg.llmProvider == LlmProvider.openrouter) ...{
            'HTTP-Referer': 'https://github.com/yanyannoodle34-debug/MP',
            'X-Title': 'CloudAI Creator',
          },
        },
        receiveTimeout: const Duration(seconds: 90),
        sendTimeout: const Duration(seconds: 30),
      ),
      data: {
        'model': cfg.llmModel,
        'messages': [
          {'role': 'system', 'content': system},
          {'role': 'user', 'content': user},
        ],
        'temperature': 0.75,
        'max_tokens': 2048,
        'response_format': {'type': 'json_object'},
      },
    );

    final content = resp.data['choices'][0]['message']['content'] as String;
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
}
