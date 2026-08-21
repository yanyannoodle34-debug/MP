import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import '../models/app_config.dart';
import '../models/scene.dart';
import '../models/video_task.dart';
import '../services/llm_service.dart';
import '../services/visual_service.dart';
import '../services/tts_service.dart';
import '../services/video_service.dart';

class SavedVideo {
  final String path;
  final String topic;
  final DateTime created;
  final int sizeBytes;
  const SavedVideo({
    required this.path,
    required this.topic,
    required this.created,
    required this.sizeBytes,
  });
}

class AppProvider extends ChangeNotifier {
  AppConfig config = const AppConfig();
  VideoTask? currentTask;
  bool _cancelRequested = false;
  List<SavedVideo> drafts = [];

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
    // Scan for existing drafts asynchronously so the UI shows them on launch.
    refreshDrafts();
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

  /// Signal the running generation to stop at the next cancellation checkpoint.
  void stop() {
    if (currentTask == null || !currentTask!.step.isActive) return;
    _cancelRequested = true;
    _update(currentTask!.addLog('Cancellation requested…'));
  }

  void _checkCancelled() {
    if (_cancelRequested) throw const _CancelledException();
  }

  Future<void> generate(String topic) async {
    _cancelRequested = false;
    final task = VideoTask(id: _uuid.v4(), topic: topic);
    _update(task);

    try {
      // ── 1. Script ──────────────────────────────────────────────────────────
      _update(task
          .copyWith(step: TaskStep.generatingScript)
          .addLog('Calling LLM (${config.llmModel})…'));

      _validateKey('LLM API key', config.llmApiKey);

      final script = await _llm.generateScript(topic, config);
      _checkCancelled();
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
      _checkCancelled();
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
      await refreshDrafts();
    } on _CancelledException {
      _update(currentTask!.copyWith(step: TaskStep.cancelled)
          .addLog('Cancelled by user.'));
    } catch (e, st) {
      _update(currentTask!.copyWith(
        step: TaskStep.error,
        errorMessage: e.toString(),
      ).addLog('Error: $e\n$st'));
    } finally {
      _cancelRequested = false;
      await _ttsService.dispose();
    }
  }

  // ── Drafts (saved videos) ─────────────────────────────────────────────────

  Future<void> refreshDrafts() async {
    final ext = await getExternalStorageDirectory();
    final dir = Directory(
        '${ext?.path ?? (await getTemporaryDirectory()).path}/CloudAICreator');
    if (!await dir.exists()) {
      drafts = [];
      notifyListeners();
      return;
    }

    // Load topic-metadata sidecar written on each successful generation.
    final prefs = await SharedPreferences.getInstance();
    final metaRaw = prefs.getString('draft_meta_v1');
    final Map<String, String> meta = metaRaw == null
        ? {}
        : (jsonDecode(metaRaw) as Map<String, dynamic>)
            .map((k, v) => MapEntry(k, v as String));

    final files = dir
        .listSync()
        .whereType<File>()
        .where((f) => f.path.toLowerCase().endsWith('.mp4'))
        .toList();

    drafts = files.map((f) {
      final stat = f.statSync();
      return SavedVideo(
        path: f.path,
        topic: meta[f.path.split('/').last] ?? _titleFromFileName(f.path),
        created: stat.modified,
        sizeBytes: stat.size,
      );
    }).toList()
      ..sort((a, b) => b.created.compareTo(a.created));

    // Persist current topic if this run produced a video.
    if (currentTask?.outputPath != null && currentTask?.topic != null) {
      final name = currentTask!.outputPath!.split('/').last;
      meta[name] = currentTask!.topic;
      await prefs.setString('draft_meta_v1', jsonEncode(meta));
    }

    notifyListeners();
  }

  String _titleFromFileName(String path) {
    final base = path.split('/').last;
    return base
        .replaceAll(RegExp(r'\.mp4$'), '')
        .replaceAll('video_', 'Video ')
        .replaceAll('_', ' ');
  }

  Future<void> deleteDraft(SavedVideo draft) async {
    try {
      await File(draft.path).delete();
    } catch (_) {}
    // Also remove from metadata
    final prefs = await SharedPreferences.getInstance();
    final metaRaw = prefs.getString('draft_meta_v1');
    if (metaRaw != null) {
      final meta = (jsonDecode(metaRaw) as Map<String, dynamic>);
      meta.remove(draft.path.split('/').last);
      await prefs.setString('draft_meta_v1', jsonEncode(meta));
    }
    await refreshDrafts();
  }

  Future<void> clearAllDrafts() async {
    for (final d in [...drafts]) {
      try {
        await File(d.path).delete();
      } catch (_) {}
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('draft_meta_v1');
    drafts = [];
    notifyListeners();
  }

  Future<List<Scene>> _generateSceneAssets(List<Scene> scenes) async {
    final total = scenes.length;
    int done = 0;
    int failed = 0;

    const maxConcurrent = 3;
    final pending = <Future<void>>[];

    for (final scene in scenes) {
      if (_cancelRequested) break;
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
    _cancelRequested = false;
    notifyListeners();
  }
}

class _CancelledException implements Exception {
  const _CancelledException();
  @override
  String toString() => 'Cancelled';
}
