import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import '../models/app_config.dart';
import '../models/scene.dart';
import '../models/video_task.dart';
import '../services/llm_service.dart';
import '../services/image_service.dart';
import '../services/tts_service.dart';
import '../services/video_service.dart';

class AppProvider extends ChangeNotifier {
  AppConfig config = const AppConfig();
  VideoTask? currentTask;

  final _llm = LlmService();
  final _imageService = ImageService();
  final _ttsService = TtsService();
  final _videoService = VideoService();
  final _uuid = const Uuid();

  Future<void> loadConfig() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('app_config_v2');
    if (raw != null) {
      try {
        config = AppConfig.fromJson(jsonDecode(raw) as Map<String, dynamic>);
      } catch (_) {}
    }
    notifyListeners();
  }

  Future<void> saveConfig(AppConfig cfg) async {
    config = cfg;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('app_config_v2', jsonEncode(cfg.toJson()));
    notifyListeners();
  }

  void _update(VideoTask t) {
    currentTask = t;
    notifyListeners();
  }

  Future<void> generate(String topic) async {
    final task = VideoTask(id: _uuid.v4(), topic: topic);
    _update(task);

    try {
      // ── 1. Script ──────────────────────────────────────────────────────────
      _update(task
          .copyWith(step: TaskStep.generatingScript)
          .addLog('Calling LLM (${config.llmModel})…'));

      _validateKey('LLM API key', config.llmApiKey);

      final script = await _llm.generateScript(topic, config);
      _update(currentTask!
          .addLog('Script: "${script.title}" — ${script.scenes.length} scenes'));

      // ── 2. Images + Audio (parallel per scene) ─────────────────────────────
      _validateKey('Image API key', config.imageApiKey);
      _validateKey('TTS API key', config.ttsApiKey);

      _update(currentTask!
          .copyWith(step: TaskStep.generatingImages)
          .addLog('Generating ${script.scenes.length} images + audio in parallel…'));

      final readyScenes = await _generateSceneAssets(script.scenes);
      _update(currentTask!
          .addLog('${readyScenes.length} scene assets ready.'));

      // ── 3. Compose video ───────────────────────────────────────────────────
      _update(currentTask!
          .copyWith(step: TaskStep.composingVideo)
          .addLog('Starting FFmpeg composition…'));

      final outputPath = await _videoService.compose(
        scenes: readyScenes,
        cfg: config,
        onProgress: (p, log) =>
            _update(currentTask!.copyWith(stageProgress: p).addLog(log)),
      );

      _update(currentTask!
          .copyWith(step: TaskStep.done, outputPath: outputPath)
          .addLog('Done! Saved to $outputPath'));
    } catch (e, st) {
      _update(currentTask!.copyWith(
        step: TaskStep.error,
        errorMessage: e.toString(),
      ).addLog('Error: $e\n$st'));
    } finally {
      await _ttsService.dispose();
    }
  }

  Future<List<Scene>> _generateSceneAssets(List<Scene> scenes) async {
    final total = scenes.length;
    int done = 0;
    int failed = 0;

    // Concurrent workers with a bounded pool of 3.
    const maxConcurrent = 3;
    final pending = <Future<void>>[];

    for (final scene in scenes) {
      if (pending.length >= maxConcurrent) {
        await pending.removeAt(0);
      }

      final f = _generateOneScene(scene).then(
        (_) {
          done++;
          _update(currentTask!
              .copyWith(stageProgress: done / total)
              .addLog('Scene ${scene.index + 1}/$total ready.'));
        },
        onError: (e, _) {
          failed++;
          _update(currentTask!
              .copyWith(stageProgress: (done + failed) / total)
              .addLog('Scene ${scene.index + 1} failed: $e (skipping)'));
        },
      );
      pending.add(f);
    }

    await Future.wait(pending);

    // Keep only scenes that have both an image and an audio file.
    final ok = scenes
        .where((s) =>
            s.imagePath != null &&
            s.audioPath != null &&
            s.audioDuration > 0)
        .toList();

    if (ok.isEmpty) {
      throw Exception(
        'All $total scenes failed. Check your API keys with the Test button.',
      );
    }
    if (ok.length < total) {
      _update(currentTask!.addLog(
        'Continuing with ${ok.length}/$total scenes (${total - ok.length} dropped).',
      ));
    }
    return ok;
  }

  Future<void> _generateOneScene(Scene scene) async {
    final i = scene.index;
    _update(currentTask!.addLog('Scene ${i + 1}: requesting image + audio…'));

    final results = await Future.wait([
      _imageService.generate(scene.imagePrompt, i, config),
      _ttsService.synthesize(scene.narration, i, config),
    ]);

    scene.imagePath = results[0] as String;
    final audioResult = results[1] as ({String path, double duration});
    scene.audioPath = audioResult.path;

    // Use FFprobe for accurate audio duration if available
    try {
      final probed = await _videoService.probeDuration(audioResult.path);
      scene.audioDuration = probed > 0 ? probed : audioResult.duration;
    } catch (_) {
      scene.audioDuration = audioResult.duration;
    }
  }

  void _validateKey(String name, String key) {
    if (key.trim().isEmpty) {
      throw Exception('$name is not set. Open Settings ⚙');
    }
  }

  void reset() {
    currentTask = null;
    notifyListeners();
  }
}
