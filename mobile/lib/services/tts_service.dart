import 'dart:io';
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import '../models/app_config.dart';

class TtsService {
  final Dio _dio = Dio();

  /// Synthesizes [text] to an audio file. Returns local path + duration (seconds).
  Future<({String path, double duration})> synthesize(
    String text,
    int sceneIndex,
    AppConfig cfg,
  ) async {
    switch (cfg.ttsProvider) {
      case TtsProvider.elevenLabs:
        return _elevenLabs(text, sceneIndex, cfg);
      case TtsProvider.openaiTts:
        return _openaiTts(text, sceneIndex, cfg);
    }
  }

  // ── ElevenLabs ────────────────────────────────────────────────────────────

  Future<({String path, double duration})> _elevenLabs(
    String text,
    int idx,
    AppConfig cfg,
  ) async {
    final voiceId = cfg.ttsVoiceId.isNotEmpty
        ? cfg.ttsVoiceId
        : 'EXAVITQu4vr4xnSDxMaL'; // Sarah

    final resp = await _dio.post(
      'https://api.elevenlabs.io/v1/text-to-speech/$voiceId',
      options: Options(
        headers: {
          'xi-api-key': cfg.ttsApiKey,
          'Content-Type': 'application/json',
          'Accept': 'audio/mpeg',
        },
        responseType: ResponseType.bytes,
        receiveTimeout: const Duration(minutes: 2),
      ),
      data: {
        'text': text,
        'model_id': 'eleven_turbo_v2',
        'voice_settings': {
          'stability': 0.5,
          'similarity_boost': 0.75,
        },
      },
    );

    return _saveAudio(resp.data as List<int>, idx, 'mp3');
  }

  // ── OpenAI TTS ────────────────────────────────────────────────────────────

  Future<({String path, double duration})> _openaiTts(
    String text,
    int idx,
    AppConfig cfg,
  ) async {
    final resp = await _dio.post(
      'https://api.openai.com/v1/audio/speech',
      options: Options(
        headers: {
          'Authorization': 'Bearer ${cfg.ttsApiKey}',
          'Content-Type': 'application/json',
        },
        responseType: ResponseType.bytes,
        receiveTimeout: const Duration(minutes: 2),
      ),
      data: {
        'model': 'tts-1',
        'input': text,
        'voice': cfg.ttsVoice.isNotEmpty ? cfg.ttsVoice : 'nova',
        'response_format': 'mp3',
      },
    );

    return _saveAudio(resp.data as List<int>, idx, 'mp3');
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  Future<({String path, double duration})> _saveAudio(
    List<int> bytes,
    int idx,
    String ext,
  ) async {
    final tmpDir = await getTemporaryDirectory();
    final path = '${tmpDir.path}/scene_${idx}_audio.$ext';
    await File(path).writeAsBytes(bytes);

    // Rough duration estimate: MP3 at ~128 kbps
    final sizeKb = bytes.length / 1024;
    final estimatedSec = (sizeKb * 8) / 128;
    return (path: path, duration: estimatedSec.clamp(1.0, 60.0));
  }

  Future<void> dispose() async {}

  // ── Key validation ────────────────────────────────────────────────────────
  /// Auth check. Returns null on success, error message on failure.
  Future<String?> testKey(AppConfig cfg) async {
    try {
      switch (cfg.ttsProvider) {
        case TtsProvider.elevenLabs:
          final r = await _dio.get(
            'https://api.elevenlabs.io/v1/user',
            options: Options(
              headers: {'xi-api-key': cfg.ttsApiKey},
              receiveTimeout: const Duration(seconds: 15),
              validateStatus: (_) => true,
            ),
          );
          if (r.statusCode != 200) return 'HTTP ${r.statusCode}: ${_err(r.data)}';
          return null;

        case TtsProvider.openaiTts:
          final r = await _dio.get(
            'https://api.openai.com/v1/models',
            options: Options(
              headers: {'Authorization': 'Bearer ${cfg.ttsApiKey}'},
              receiveTimeout: const Duration(seconds: 15),
              validateStatus: (_) => true,
            ),
          );
          if (r.statusCode != 200) return 'HTTP ${r.statusCode}: ${_err(r.data)}';
          return null;
      }
    } catch (e) {
      if (e is DioException && e.response != null) {
        return 'HTTP ${e.response!.statusCode}: ${_err(e.response!.data)}';
      }
      return e.toString();
    }
  }

  /// List ElevenLabs voices, or OpenAI TTS voice names.
  Future<List<({String id, String name})>> fetchVoices(AppConfig cfg) async {
    switch (cfg.ttsProvider) {
      case TtsProvider.elevenLabs:
        final r = await _dio.get(
          'https://api.elevenlabs.io/v1/voices',
          options: Options(
            headers: {'xi-api-key': cfg.ttsApiKey},
            receiveTimeout: const Duration(seconds: 20),
          ),
        );
        final voices = r.data['voices'] as List? ?? [];
        return voices
            .map((v) => (
                  id: (v['voice_id'] as String?) ?? '',
                  name: (v['name'] as String?) ?? '(unnamed)',
                ))
            .where((v) => v.id.isNotEmpty)
            .toList();

      case TtsProvider.openaiTts:
        // OpenAI TTS voices are a fixed list; no API endpoint to enumerate.
        const openaiVoices = ['alloy', 'echo', 'fable', 'onyx', 'nova', 'shimmer'];
        return openaiVoices.map((v) => (id: v, name: v)).toList();
    }
  }

  String _err(dynamic body) {
    if (body is Map) {
      final err = body['error'];
      if (err is Map) return (err['message'] as String?) ?? body.toString();
      if (err is String) return err;
      return (body['message'] as String?) ?? body.toString();
    }
    return body?.toString() ?? 'unknown error';
  }
}
