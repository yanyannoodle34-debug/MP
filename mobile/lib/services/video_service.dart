import 'dart:io';
import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/ffprobe_kit.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';
import 'package:path_provider/path_provider.dart';
import '../models/app_config.dart';
import '../models/scene.dart';

const _kW = 1080;
const _kH = 1920;
const _kFps = 25;

class VideoService {
  Future<String> compose({
    required List<Scene> scenes,
    required AppConfig cfg,
    required void Function(double progress, String log) onProgress,
  }) async {
    final tmpDir = await getTemporaryDirectory();
    final workDir = Directory('${tmpDir.path}/cloudai_work');
    await workDir.create(recursive: true);

    // Step 1: per-scene video clips
    final clipPaths = <String>[];
    for (var i = 0; i < scenes.length; i++) {
      final scene = scenes[i];
      onProgress(
          i / scenes.length * 0.7, 'Rendering scene ${i + 1}/${scenes.length}…');

      final clipPath = '${workDir.path}/clip_$i.mp4';
      await _renderSceneClip(
        scene: scene,
        outPath: clipPath,
        kenBurns: cfg.kenBurnsEnabled,
      );
      clipPaths.add(clipPath);
    }

    // Step 2: concat all clips
    onProgress(0.75, 'Concatenating ${clipPaths.length} clips…');
    final concatPath = '${workDir.path}/concat.mp4';
    await _concatClips(clipPaths, concatPath);

    // Step 3: burn subtitles (optional)
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

  // ── Scene clip: routes to image or video path ────────────────────────────

  Future<void> _renderSceneClip({
    required Scene scene,
    required String outPath,
    required bool kenBurns,
  }) async {
    if (scene.mediaIsVideo) {
      await _renderVideoClip(
        videoPath: scene.mediaPath!,
        audioPath: scene.audioPath!,
        duration: scene.audioDuration,
        outPath: outPath,
        sceneIndex: scene.index,
      );
    } else {
      await _renderImageClip(
        imagePath: scene.mediaPath!,
        audioPath: scene.audioPath!,
        duration: scene.audioDuration,
        outPath: outPath,
        kenBurns: kenBurns,
        sceneIndex: scene.index,
      );
    }
  }

  // Image + ken-burns + audio → clip
  Future<void> _renderImageClip({
    required String imagePath,
    required String audioPath,
    required double duration,
    required String outPath,
    required bool kenBurns,
    required int sceneIndex,
  }) async {
    final frames = (duration * _kFps).ceil();

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
    if (!ReturnCode.isSuccess(await session.getReturnCode())) {
      final logs = await session.getAllLogsAsString();
      if (kenBurns) {
        // Retry without ken-burns
        await _renderImageClip(
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

  // Stock video + audio → clip (loop video if shorter than audio, crop to 9:16)
  Future<void> _renderVideoClip({
    required String videoPath,
    required String audioPath,
    required double duration,
    required String outPath,
    required int sceneIndex,
  }) async {
    // scale + crop to 1080x1920 portrait
    // stream_loop = -1 loops the video source, then -t caps to audio length
    // audio from source 1 (the tts audio)
    final cmd = [
      '-y',
      '-stream_loop', '-1',
      '-i', _q(videoPath),
      '-i', _q(audioPath),
      '-filter_complex',
      '[0:v]scale=$_kW:$_kH:force_original_aspect_ratio=increase,'
          'crop=$_kW:$_kH,setpts=PTS-STARTPTS[vout]',
      '-map', '[vout]', '-map', '1:a',
      '-c:v', 'libx264', '-preset', 'veryfast', '-crf', '24',
      '-c:a', 'aac', '-b:a', '128k',
      '-t', duration.toStringAsFixed(3),
      '-pix_fmt', 'yuv420p',
      '-movflags', '+faststart',
      _q(outPath),
    ].join(' ');

    final session = await FFmpegKit.execute(cmd);
    if (!ReturnCode.isSuccess(await session.getReturnCode())) {
      final logs = await session.getAllLogsAsString();
      throw Exception('Scene $sceneIndex video render failed.\n$logs');
    }
  }

  // ── Concat via concat demuxer ─────────────────────────────────────────────

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
    if (!ReturnCode.isSuccess(await session.getReturnCode())) {
      // Fallback: re-encode instead of stream copy (clips may differ in codec params)
      final reencodeCmd = [
        '-y',
        '-f', 'concat', '-safe', '0', '-i', _q(listFile),
        '-c:v', 'libx264', '-preset', 'veryfast', '-crf', '24',
        '-c:a', 'aac', '-b:a', '128k',
        _q(outPath),
      ].join(' ');
      final session2 = await FFmpegKit.execute(reencodeCmd);
      if (!ReturnCode.isSuccess(await session2.getReturnCode())) {
        final logs = await session2.getAllLogsAsString();
        throw Exception('Concat failed.\n$logs');
      }
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
    if (!ReturnCode.isSuccess(await session.getReturnCode())) {
      await File(input).copy(out);
    }
  }

  // ── SRT generation ────────────────────────────────────────────────────────

  Future<String> _writeSrt(List<Scene> scenes, String dir) async {
    final srtPath = '$dir/subs.srt';
    final buf = StringBuffer();
    int idx = 1;
    double cursor = 0.0;

    for (var i = 0; i < scenes.length; i++) {
      final scene = scenes[i];
      final dur = scene.audioDuration;
      final words = scene.narration.trim().split(RegExp(r'\s+'));
      final chunkSize = (words.length / 2).ceil().clamp(3, 8);

      final sceneStart = cursor;
      for (var w = 0; w < words.length; w += chunkSize) {
        final chunk = words.sublist(w, (w + chunkSize).clamp(0, words.length));
        final segDur = dur * chunk.length / words.length;
        final start = cursor;
        final end = cursor + segDur;

        buf.writeln(idx++);
        buf.writeln('${_ts(start)} --> ${_ts(end)}');
        buf.writeln(chunk.join(' '));
        buf.writeln();
        cursor = end;
      }
      cursor = sceneStart + dur; // ensure cursor aligns even with rounding
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

  Future<String> _buildOutputPath() async {
    final ext = await getExternalStorageDirectory();
    final dir = Directory(
        '${ext?.path ?? (await getTemporaryDirectory()).path}/CloudAICreator');
    await dir.create(recursive: true);
    return '${dir.path}/video_${DateTime.now().millisecondsSinceEpoch}.mp4';
  }

  Future<double> probeDuration(String path) async {
    final session = await FFprobeKit.getMediaInformation(path);
    final info = session.getMediaInformation();
    return double.tryParse(info?.getDuration() ?? '') ?? 4.0;
  }

  String _q(String p) => "'$p'";

  String _srtEscape(String p) =>
      p.replaceAll('\\', '\\\\').replaceAll("'", "\\'").replaceAll(':', '\\:');
}
