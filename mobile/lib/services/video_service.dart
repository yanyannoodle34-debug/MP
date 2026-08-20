import 'dart:io';
import 'package:ffmpeg_kit_flutter_full_gpl/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_full_gpl/ffprobe_kit.dart';
import 'package:ffmpeg_kit_flutter_full_gpl/return_code.dart';
import 'package:path_provider/path_provider.dart';
import '../models/app_config.dart';
import '../models/scene.dart';

const _kW = 1080;
const _kH = 1920;
const _kFps = 25;

class VideoService {
  /// Compose a portrait 9:16 video from [scenes] (each has imagePath + audioPath + audioDuration).
  /// Returns path to the finished MP4.
  Future<String> compose({
    required List<Scene> scenes,
    required AppConfig cfg,
    required void Function(double progress, String log) onProgress,
  }) async {
    final tmpDir = await getTemporaryDirectory();
    final workDir = Directory('${tmpDir.path}/cloudai_work');
    await workDir.create(recursive: true);

    // ── Step 1: per-scene video clips ─────────────────────────────────────
    final clipPaths = <String>[];
    for (var i = 0; i < scenes.length; i++) {
      final scene = scenes[i];
      onProgress(i / scenes.length * 0.7, 'Rendering scene ${i + 1}/${scenes.length}…');

      final clipPath = '${workDir.path}/clip_$i.mp4';
      await _renderSceneClip(
        imagePath: scene.imagePath!,
        audioPath: scene.audioPath!,
        duration: scene.audioDuration,
        outPath: clipPath,
        kenBurns: cfg.kenBurnsEnabled,
        sceneIndex: i,
      );
      clipPaths.add(clipPath);
    }

    // ── Step 2: concat all clips ──────────────────────────────────────────
    onProgress(0.75, 'Concatenating ${clipPaths.length} clips…');
    final concatPath = '${workDir.path}/concat.mp4';
    await _concatClips(clipPaths, concatPath);

    // ── Step 3: burn subtitles (optional) ────────────────────────────────
    final outputPath = await _buildOutputPath();

    if (cfg.subtitlesEnabled) {
      onProgress(0.88, 'Burning subtitles…');
      final srtPath = await _writeSrt(scenes, workDir.path);
      await _burnSubtitles(concatPath, srtPath, outputPath);
    } else {
      await File(concatPath).copy(outputPath);
    }

    onProgress(1.0, 'Video ready: $outputPath');
    return outputPath;
  }

  // ── Scene clip (image + audio + optional ken-burns zoom) ─────────────────

  Future<void> _renderSceneClip({
    required String imagePath,
    required String audioPath,
    required double duration,
    required String outPath,
    required bool kenBurns,
    required int sceneIndex,
  }) async {
    final frames = (duration * _kFps).ceil();

    // Ken-burns: slow zoom-in starting from 1.0x, ending ~1.08x over the clip
    // zoompan: z = zoom factor, d = total frames, s = output size
    final videoFilter = kenBurns
        ? '[0:v]scale=${_kW * 2}:${_kH * 2},'
            'zoompan=z=\'if(lte(on,$frames),1.0+0.0008*on,1.0+0.0008*$frames)\':'
            'x=\'iw/2-(iw/zoom/2)\':y=\'ih/2-(ih/zoom/2)\':'
            'd=$frames:s=${_kW}x$_kH:fps=$_kFps,'
            'scale=$_kW:$_kH[vout]'
        : '[0:v]scale=$_kW:$_kH:force_original_aspect_ratio=increase,'
            'crop=$_kW:$_kH[vout]';

    final cmd = [
      '-y',
      '-loop', '1', '-i', _q(imagePath),
      '-i', _q(audioPath),
      '-filter_complex', videoFilter,
      '-map', '[vout]', '-map', '1:a',
      '-c:v', 'libx264', '-preset', 'veryfast', '-crf', '24',
      '-c:a', 'aac', '-b:a', '128k',
      '-t', duration.toStringAsFixed(3),
      '-pix_fmt', 'yuv420p',
      '-movflags', '+faststart',
      _q(outPath),
    ].join(' ');

    final session = await FFmpegKit.execute(cmd);
    final rc = await session.getReturnCode();
    if (!ReturnCode.isSuccess(rc)) {
      final logs = await session.getAllLogsAsString();
      // If zoompan fails, retry without ken-burns
      if (kenBurns) {
        await _renderSceneClip(
          imagePath: imagePath,
          audioPath: audioPath,
          duration: duration,
          outPath: outPath,
          kenBurns: false,
          sceneIndex: sceneIndex,
        );
        return;
      }
      throw Exception('Scene $sceneIndex render failed.\n$logs');
    }
  }

  // ── Concat clips via concat demuxer ──────────────────────────────────────

  Future<void> _concatClips(List<String> clips, String outPath) async {
    final tmpDir = await getTemporaryDirectory();
    final listFile = '${tmpDir.path}/cloudai_list.txt';
    final buf = StringBuffer();
    for (final c in clips) {
      buf.writeln("file '${c.replaceAll("'", "\\'")}'");
    }
    await File(listFile).writeAsString(buf.toString());

    final cmd = [
      '-y',
      '-f', 'concat', '-safe', '0', '-i', _q(listFile),
      '-c', 'copy',
      _q(outPath),
    ].join(' ');

    final session = await FFmpegKit.execute(cmd);
    final rc = await session.getReturnCode();
    if (!ReturnCode.isSuccess(rc)) {
      final logs = await session.getAllLogsAsString();
      throw Exception('Concat failed.\n$logs');
    }
  }

  // ── Subtitle burn-in ──────────────────────────────────────────────────────

  Future<void> _burnSubtitles(String input, String srt, String out) async {
    final style = 'FontName=sans-serif,FontSize=48,'
        'PrimaryColour=&H00FFFFFF,Bold=1,'
        'BorderStyle=1,Outline=2,OutlineColour=&H00000000,'
        'Shadow=0,Alignment=2,MarginV=100';

    final cmd = [
      '-y',
      '-i', _q(input),
      '-vf', "subtitles='${_srtEscape(srt)}':force_style='$style'",
      '-c:v', 'libx264', '-preset', 'veryfast', '-crf', '24',
      '-c:a', 'copy',
      '-movflags', '+faststart',
      _q(out),
    ].join(' ');

    final session = await FFmpegKit.execute(cmd);
    final rc = await session.getReturnCode();
    if (!ReturnCode.isSuccess(rc)) {
      // subtitle filter failed → just copy without subs
      await File(input).copy(out);
    }
  }

  // ── SRT generation from scenes ────────────────────────────────────────────

  Future<String> _writeSrt(List<Scene> scenes, String dir) async {
    final srtPath = '$dir/subs.srt';
    final buf = StringBuffer();
    int idx = 1;
    double cursor = 0.0;

    for (final scene in scenes) {
      final dur = scene.audioDuration;
      final words = scene.narration.trim().split(RegExp(r'\s+'));
      final chunkSize = (words.length / 2).ceil().clamp(3, 8);

      for (var i = 0; i < words.length; i += chunkSize) {
        final chunk = words.sublist(i, (i + chunkSize).clamp(0, words.length));
        final segDur = dur * chunk.length / words.length;
        final start = cursor;
        final end = cursor + segDur;

        buf.writeln(idx++);
        buf.writeln('${_ts(start)} --> ${_ts(end)}');
        buf.writeln(chunk.join(' '));
        buf.writeln();
        cursor = end;
      }
      // Ensure cursor advances by full scene duration
      if (cursor < (scenes.indexOf(scene) + 1) * dur) {
        cursor = scenes.sublist(0, scenes.indexOf(scene) + 1)
            .fold(0.0, (s, sc) => s + sc.audioDuration);
      }
    }

    await File(srtPath).writeAsString(buf.toString());
    return srtPath;
  }

  String _ts(double s) {
    final ms = (s * 1000).round();
    final h = ms ~/ 3600000;
    final m = (ms % 3600000) ~/ 60000;
    final sec = (ms % 60000) ~/ 1000;
    final millis = ms % 1000;
    return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:'
        '${sec.toString().padLeft(2, '0')},${millis.toString().padLeft(3, '0')}';
  }

  // ── Output path ───────────────────────────────────────────────────────────

  Future<String> _buildOutputPath() async {
    final ext = await getExternalStorageDirectory();
    final dir = Directory(
        '${ext?.path ?? (await getTemporaryDirectory()).path}/CloudAICreator');
    await dir.create(recursive: true);
    return '${dir.path}/video_${DateTime.now().millisecondsSinceEpoch}.mp4';
  }

  // ── Probe duration via FFprobe ────────────────────────────────────────────

  Future<double> probeDuration(String path) async {
    final session = await FFprobeKit.getMediaInformation(path);
    final info = session.getMediaInformation();
    return double.tryParse(info?.getDuration() ?? '') ?? 4.0;
  }

  // ── String helpers ────────────────────────────────────────────────────────

  String _q(String p) => "'$p'";

  String _srtEscape(String p) =>
      p.replaceAll('\\', '\\\\').replaceAll("'", "\\'").replaceAll(':', '\\:');
}
