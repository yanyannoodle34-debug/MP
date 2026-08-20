import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import '../models/app_config.dart';
import '../models/video_task.dart';
import '../services/llm_service.dart';
import '../services/material_service.dart';
import '../services/subtitle_service.dart';
import '../services/tts_service.dart';
import '../services/video_service.dart';

class AppProvider extends ChangeNotifier {
  AppConfig config = const AppConfig();
  VideoTask? currentTask;

  final _llm = LlmService();
  final _materials = MaterialService();
  final _tts = TtsService();
  final _subtitles = SubtitleService();
  final _video = VideoService();
  final _uuid = const Uuid();

  Future<void> loadConfig() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('app_config');
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
    await prefs.setString('app_config', jsonEncode(cfg.toJson()));
    notifyListeners();
  }

  void _updateTask(VideoTask t) {
    currentTask = t;
    notifyListeners();
  }

  Future<void> generate(String topic) async {
    final task = VideoTask(id: _uuid.v4(), topic: topic);
    _updateTask(task);

    try {
      // ── 1. Script ───────────────────────────────────────────────────────────
      _updateTask(task
          .copyWith(step: TaskStep.generatingScript)
          .addLog('Calling LLM: "${config.llmModel}"…'));

      if (config.llmApiKey.isEmpty) {
        throw Exception('LLM API key is not set. Go to Settings.');
      }

      final scriptResult = await _llm.generateScript(topic, config);
      _updateTask(currentTask!
          .copyWith(script: scriptResult.script)
          .addLog('Script ready (${scriptResult.script.split(' ').length} words).')
          .addLog('Search terms: ${scriptResult.searchTerms.join(', ')}'));

      // ── 2. Materials ────────────────────────────────────────────────────────
      _updateTask(currentTask!
          .copyWith(step: TaskStep.downloadingMaterials)
          .addLog('Fetching stock videos from Pexels…'));

      if (config.pexelsApiKey.isEmpty) {
        throw Exception('Pexels API key is not set. Go to Settings.');
      }

      final clipPaths = await _materials.fetchAndDownload(
        scriptResult.searchTerms,
        config,
        onProgress: (p, log) {
          _updateTask(currentTask!
              .copyWith(materialProgress: p)
              .addLog(log));
        },
      );
      _updateTask(currentTask!.addLog('Downloaded ${clipPaths.length} clip(s).'));

      // ── 3. TTS ──────────────────────────────────────────────────────────────
      _updateTask(currentTask!
          .copyWith(step: TaskStep.synthesizingAudio)
          .addLog('Synthesizing audio on-device…'));

      final audioPath =
          await _tts.synthesizeToFile(scriptResult.script, config);
      _updateTask(currentTask!.addLog('Audio ready: $audioPath'));

      // ── 4. Subtitles ────────────────────────────────────────────────────────
      final tmpDir = await getTemporaryDirectory();
      final srtPath = '${tmpDir.path}/mpt_subs.srt';

      // Probe audio duration for subtitle timing
      final audioDur = config.videoDurationSec.toDouble();
      final entries =
          _subtitles.buildEntries(scriptResult.script, audioDur);
      await File(srtPath).writeAsString(_subtitles.toSrt(entries));
      _updateTask(currentTask!.addLog('Subtitle file written.'));

      // ── 5. Compose ──────────────────────────────────────────────────────────
      _updateTask(currentTask!
          .copyWith(step: TaskStep.composingVideo)
          .addLog('Starting ffmpeg composition…'));

      final outputPath = await _video.compose(
        clipPaths: clipPaths,
        audioPath: audioPath,
        srtPath: srtPath,
        cfg: config,
        onLog: (log) => _updateTask(currentTask!.addLog(log)),
      );

      _updateTask(currentTask!
          .copyWith(step: TaskStep.done, outputPath: outputPath)
          .addLog('✓ Video saved to $outputPath'));
    } catch (e, st) {
      _updateTask(currentTask!
          .copyWith(
            step: TaskStep.error,
            errorMessage: e.toString(),
          )
          .addLog('✗ Error: $e\n$st'));
    }
  }

  void reset() {
    currentTask = null;
    notifyListeners();
  }
}
