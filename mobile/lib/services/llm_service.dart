import 'dart:convert';
import 'package:dio/dio.dart';
import '../models/app_config.dart';
import '../models/video_task.dart';

class LlmService {
  final Dio _dio = Dio();

  Future<ScriptResult> generateScript(String topic, AppConfig cfg) async {
    final wordTarget = (cfg.videoDurationSec * 2.2).round(); // ~2.2 words/sec

    final systemPrompt = '''
You are a short-form video scriptwriter. Write an engaging narration script and
pick relevant stock-video search terms. Return ONLY valid JSON — no markdown.
''';

    final userPrompt = '''
Topic: "$topic"
Target duration: ${cfg.videoDurationSec} seconds (~$wordTarget words at normal pace)

Return JSON with exactly these keys:
{
  "script": "<narration — plain sentences, no stage directions>",
  "terms":  ["<keyword1>", "<keyword2>", "<keyword3>", "<keyword4>", "<keyword5>"]
}

Rules:
- Script must be natural spoken-word prose.
- Terms must be specific, visual, and searchable as stock-video queries.
''';

    final response = await _dio.post(
      '${cfg.llmBaseUrl}/chat/completions',
      options: Options(
        headers: {
          'Authorization': 'Bearer ${cfg.llmApiKey}',
          'Content-Type': 'application/json',
          'HTTP-Referer': 'https://github.com/yanyannoodle34-debug/MP',
          'X-Title': 'MoneyPrinterMobile',
        },
        receiveTimeout: const Duration(seconds: 60),
      ),
      data: {
        'model': cfg.llmModel,
        'messages': [
          {'role': 'system', 'content': systemPrompt},
          {'role': 'user', 'content': userPrompt},
        ],
        'temperature': 0.7,
        'max_tokens': 1024,
        'response_format': {'type': 'json_object'},
      },
    );

    final content =
        response.data['choices'][0]['message']['content'] as String;

    final Map<String, dynamic> parsed = jsonDecode(content);
    final script = parsed['script'] as String? ?? '';
    final rawTerms = parsed['terms'];
    final terms = rawTerms is List
        ? rawTerms.map((e) => e.toString()).toList()
        : <String>[];

    if (script.isEmpty) throw Exception('LLM returned empty script.');
    if (terms.isEmpty) throw Exception('LLM returned no search terms.');

    return ScriptResult(script: script, searchTerms: terms);
  }
}
