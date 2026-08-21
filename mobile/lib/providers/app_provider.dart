import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import '../models/app_config.dart';
import '../models/scene.dart';
import '../models/video_task.dart';
import '../services/llm_service.dart';
import '../services/visual_service.dart';
import '../services/tts_service.dart';
import '../services/video_service.dart';

class AppProvider extends ChangeNotifier {
  AppConfig config = const AppConfig();
  VideoTask? currentTask;

  final _llm = LlmService();
  final _visualService = VisualService();
  final _ttsService = TtsService();
  final _videoService = VideoService();
  final _uuid = const Uuid();

  Future<void> loadConfig() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('app_config_v3');
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
    await prefs.setString('app_config_v3', jsonEncode(cfg.toJson()));
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

      // ── 2. Visuals + Audio (parallel per scene) ────────────────────────────
      if (config.visualSource.isAI || config.visualSource.isStock) {
        _validateKey('${config.visualSource.displayName} API key', config.visualApiKey);
      }
      if (config.ttsProvider.requiresKey) {
        _validateKey('TTS API key', config.ttsApiKey);
      }

      final sourceLabel = config.visualSource.isAI
          ? 'AI-generated images'
          : 'stock video clips (${config.visualSource.displayName})';
      _update(currentTask!
          .copyWith(step: TaskStep.generatingImages)
          .addLog('Fetching ${script.scenes.length} $sourceLabel + audio in parallel…'));

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

    final ok = scenes
        .where((s) =>
            s.mediaPath != null &&
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
    final searchTerms = scene.searchQuery.isNotEmpty
        ? scene.searchQuery
        : scene.narration.split(' ').take(5).join(' ');

    // Fire both in parallel but track their errors independently so we can
    // tell the user which service failed.
    _update(currentTask!.addLog(
        'Scene ${i + 1}: fetching ${config.visualSource.displayName}…'));

    final visualFut = _visualService
        .fetch(
      imagePrompt: scene.imagePrompt,
      searchQuery: searchTerms,
      sceneIndex: i,
      cfg: config,
    )
        .then<Object?>((v) => v, onError: (e) => e);

    final audioFut = _ttsService
        .synthesize(scene.narration, i, config)
        .then<Object?>((a) => a, onError: (e) => e);

    final results = await Future.wait([visualFut, audioFut]);
    final visualResult = results[0];
    final audioResult = results[1];

    final errors = <String>[];
    if (visualResult is Exception || visualResult is Error) {
      errors.add('${config.visualSource.displayName}: $visualResult');
    }
    if (audioResult is Exception || audioResult is Error) {
      errors.add('${config.ttsProvider.displayName}: $audioResult');
    }
    if (errors.isNotEmpty) {
      throw Exception(errors.join(' | '));
    }

    final visual = visualResult as VisualAsset;
    scene.mediaPath = visual.path;
    scene.mediaIsVideo = visual.isVideo;

    final audio = audioResult as ({String path, double duration});
    scene.audioPath = audio.path;

    try {
      final probed = await _videoService.probeDuration(audio.path);
      scene.audioDuration = probed > 0 ? probed : audio.duration;
    } catch (_) {
      scene.audioDuration = audio.duration;
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
