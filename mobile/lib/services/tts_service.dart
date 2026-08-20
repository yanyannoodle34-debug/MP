import 'dart:async';
import 'dart:io';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:path_provider/path_provider.dart';
import '../models/app_config.dart';

class TtsService {
  final FlutterTts _tts = FlutterTts();

  Future<void> _configure(AppConfig cfg) async {
    await _tts.setLanguage(cfg.ttsLanguage);
    await _tts.setSpeechRate(cfg.ttsSpeechRate);
    await _tts.setVolume(1.0);
    await _tts.setPitch(1.0);
    await _tts.setSharedInstance(true);
  }

  /// Synthesizes [text] to a WAV file on-device and returns its path.
  /// Requires Android TTS engine supporting the configured language.
  Future<String> synthesizeToFile(String text, AppConfig cfg) async {
    await _configure(cfg);

    final tmpDir = await getTemporaryDirectory();
    final audioPath = '${tmpDir.path}/mpt_tts_output.wav';

    final f = File(audioPath);
    if (await f.exists()) await f.delete();

    final completer = Completer<void>();

    _tts.setCompletionHandler(() {
      if (!completer.isCompleted) completer.complete();
    });
    _tts.setErrorHandler((msg) {
      if (!completer.isCompleted) {
        completer.completeError(Exception('TTS error: $msg'));
      }
    });

    await _tts.synthesizeToFile(text, audioPath);

    await completer.future.timeout(
      const Duration(minutes: 3),
      onTimeout: () =>
          throw TimeoutException('TTS synthesis timed out after 3 minutes.'),
    );

    if (!await f.exists() || await f.length() < 100) {
      throw Exception(
        'TTS produced no audio. Ensure your device TTS engine supports '
        '"${cfg.ttsLanguage}" (Settings → Accessibility → Text-to-Speech).',
      );
    }

    return audioPath;
  }

  Future<void> dispose() => _tts.stop();
}
