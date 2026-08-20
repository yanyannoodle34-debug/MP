import 'dart:async';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:path_provider/path_provider.dart';
import '../models/app_config.dart';

class TtsService {
  final Dio _dio = Dio();
  FlutterTts? _deviceTts;

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
      case TtsProvider.device:
        return _deviceSynth(text, sceneIndex, cfg);
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

  // ── Device TTS (fallback) ─────────────────────────────────────────────────

  Future<({String path, double duration})> _deviceSynth(
    String text,
    int idx,
    AppConfig cfg,
  ) async {
    _deviceTts ??= FlutterTts();
    final tts = _deviceTts!;
    await tts.setLanguage(cfg.ttsLanguage);
    await tts.setSpeechRate(cfg.ttsSpeechRate);
    await tts.setVolume(1.0);
    await tts.setPitch(1.0);
    await tts.setSharedInstance(true);

    final tmpDir = await getTemporaryDirectory();
    final path = '${tmpDir.path}/scene_${idx}_audio.wav';

    final f = File(path);
    if (await f.exists()) await f.delete();

    final completer = Completer<void>();
    tts.setCompletionHandler(() {
      if (!completer.isCompleted) completer.complete();
    });
    tts.setErrorHandler((msg) {
      if (!completer.isCompleted) {
        completer.completeError(Exception('TTS error: $msg'));
      }
    });

    await tts.synthesizeToFile(text, path);
    await completer.future.timeout(const Duration(minutes: 3));

    if (!await f.exists() || await f.length() < 100) {
      throw Exception(
        'Device TTS produced no audio. Check Settings → Accessibility → TTS.',
      );
    }

    // Estimate duration: ~2.5 words/sec at normal rate
    final wordCount = text.trim().split(RegExp(r'\s+')).length;
    final estimated = wordCount / (2.5 * cfg.ttsSpeechRate);
    return (path: path, duration: estimated);
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

    // Rough duration estimate from MP3 bitrate ~128kbps
    final sizeKb = bytes.length / 1024;
    final estimatedSec = (sizeKb * 8) / 128; // kbits / kbps
    return (path: path, duration: estimatedSec.clamp(1.0, 60.0));
  }

  Future<void> dispose() async {
    await _deviceTts?.stop();
    _deviceTts = null;
  }
}
