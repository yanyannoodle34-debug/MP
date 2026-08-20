import 'dart:io';
import 'package:ffmpeg_kit_flutter_full_gpl/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_full_gpl/ffprobe_kit.dart';
import 'package:ffmpeg_kit_flutter_full_gpl/return_code.dart';
import 'package:path_provider/path_provider.dart';
import '../models/app_config.dart';

/// Target resolution: portrait 9:16 (1080×1920) for short-form video.
const _kWidth = 1080;
const _kHeight = 1920;

class VideoService {
  /// Full pipeline: clips → concat → scale → audio → subtitles → output.mp4
  Future<String> compose({
    required List<String> clipPaths,
    required String audioPath,
    required String srtPath,
    required AppConfig cfg,
    required void Function(String log) onLog,
  }) async {
    final tmpDir = await getTemporaryDirectory();
    final workDir = Directory('${tmpDir.path}/mpt_work');
    await workDir.create(recursive: true);

    // ── Step 1: probe audio duration ─────────────────────────────────────────
    onLog('Probing audio duration…');
    final audioDur = await _probeDuration(audioPath);
    onLog('Audio duration: ${audioDur.toStringAsFixed(2)}s');

    // ── Step 2: write a concat demuxer file with looped clips ────────────────
    onLog('Preparing ${clipPaths.length} clip(s)…');
    final concatFile = '${workDir.path}/concat.txt';
    await _writeConcatFile(concatFile, clipPaths, audioDur);

    // ── Step 3: compose with ffmpeg ──────────────────────────────────────────
    final outputPath = await _outputPath();
    onLog('Running ffmpeg compose…');

    // Build the ffmpeg command.
    // We use stream_loop + -t to loop the concat source to match audio length.
    // subtitles filter requires libass (included in full_gpl build).
    final subtitleFilter = cfg.subtitlesEnabled
        ? ",subtitles='${_escapePath(srtPath)}'"
            ":force_style='FontName=sans-serif,FontSize=52,"
            "PrimaryColour=&H00FFFFFF,Bold=1,"
            "BorderStyle=1,Outline=2,OutlineColour=&H00000000,"
            "Shadow=0,Alignment=2,MarginV=80'"
        : '';

    final cmd = [
      '-y',
      '-stream_loop', '-1',
      '-f', 'concat', '-safe', '0', '-i', concatFile,
      '-i', audioPath,
      '-filter_complex',
      '[0:v]scale=$_kWidth:$_kHeight:force_original_aspect_ratio=increase,'
          'crop=$_kWidth:$_kHeight,setpts=PTS-STARTPTS$subtitleFilter[vout]',
      '-map', '[vout]',
      '-map', '1:a',
      '-c:v', 'libx264', '-preset', 'fast', '-crf', '23',
      '-c:a', 'aac', '-b:a', '128k',
      '-t', audioDur.toStringAsFixed(3),
      '-movflags', '+faststart',
      outputPath,
    ].join(' ');

    onLog('ffmpeg: $cmd');
    final session = await FFmpegKit.execute(cmd);
    final rc = await session.getReturnCode();

    if (!ReturnCode.isSuccess(rc)) {
      final logs = await session.getAllLogsAsString();
      // If subtitle filter failed, retry without subtitles (libass font issue)
      if (cfg.subtitlesEnabled && (logs?.contains('subtitles') ?? false)) {
        onLog('Subtitle filter failed, retrying without subtitles…');
        return compose(
          clipPaths: clipPaths,
          audioPath: audioPath,
          srtPath: srtPath,
          cfg: cfg.copyWith(subtitlesEnabled: false),
          onLog: onLog,
        );
      }
      throw Exception('ffmpeg failed.\n${logs ?? "no logs"}');
    }

    onLog('Video written to $outputPath');
    return outputPath;
  }

  Future<double> _probeDuration(String path) async {
    final session = await FFprobeKit.getMediaInformation(path);
    final info = session.getMediaInformation();
    final dur = info?.getDuration();
    return double.tryParse(dur ?? '') ?? 30.0;
  }

  Future<void> _writeConcatFile(
    String dest,
    List<String> clips,
    double totalDur,
  ) async {
    // Repeat the clip list until we have at least totalDur seconds of content.
    final buf = StringBuffer();
    double accumulated = 0.0;
    int idx = 0;

    // Probe durations once
    final durations = <double>[];
    for (final c in clips) {
      durations.add(await _probeDuration(c));
    }

    while (accumulated < totalDur + 1) {
      final c = clips[idx % clips.length];
      final d = durations[idx % durations.length];
      buf.writeln("file '${c.replaceAll("'", "'\\''")}'");
      accumulated += d;
      idx++;
      if (idx > 200) break; // safety cap
    }

    await File(dest).writeAsString(buf.toString());
  }

  Future<String> _outputPath() async {
    final ext = await getExternalStorageDirectory();
    final dir = Directory('${ext?.path ?? (await getTemporaryDirectory()).path}/MoneyPrinterMobile');
    await dir.create(recursive: true);
    final ts = DateTime.now().millisecondsSinceEpoch;
    return '${dir.path}/video_$ts.mp4';
  }

  String _escapePath(String p) => p.replaceAll('\\', '\\\\').replaceAll("'", "\\'").replaceAll(':', '\\:');
}
