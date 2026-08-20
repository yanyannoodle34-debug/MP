import 'dart:io';
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import '../models/app_config.dart';

class MaterialService {
  final Dio _dio = Dio();

  /// Downloads stock video clips for the given search terms.
  /// Returns local file paths ordered for concatenation.
  Future<List<String>> fetchAndDownload(
    List<String> terms,
    AppConfig cfg, {
    required void Function(double progress, String log) onProgress,
  }) async {
    final tmpDir = await getTemporaryDirectory();
    final clipsDir = Directory('${tmpDir.path}/mpt_clips');
    await clipsDir.create(recursive: true);

    final paths = <String>[];
    final clipsNeeded = _clipsNeeded(cfg.videoDurationSec);

    int downloaded = 0;
    final termsCycled = _cycleTo(terms, clipsNeeded);

    for (var i = 0; i < termsCycled.length; i++) {
      final term = termsCycled[i];
      onProgress(downloaded / clipsNeeded, 'Searching: "$term"');

      try {
        final videoUrl = await _searchPexels(term, cfg.pexelsApiKey);
        if (videoUrl == null) {
          onProgress(downloaded / clipsNeeded, 'No results for "$term", skipping.');
          continue;
        }

        final dest = '${clipsDir.path}/clip_${i}_${_slug(term)}.mp4';
        await _download(videoUrl, dest, onProgress: (recv, total) {
          final clipProgress = total > 0 ? recv / total : 0.0;
          onProgress(
            (downloaded + clipProgress) / clipsNeeded,
            'Downloading clip ${i + 1}/$clipsNeeded…',
          );
        });

        paths.add(dest);
        downloaded++;
        onProgress(downloaded / clipsNeeded, 'Clip ${i + 1} ready.');
      } catch (e) {
        onProgress(downloaded / clipsNeeded, 'Failed clip ${i + 1}: $e');
      }

      if (downloaded >= clipsNeeded) break;
    }

    if (paths.isEmpty) {
      throw Exception('No video materials could be downloaded.');
    }
    return paths;
  }

  /// Search Pexels for a video clip and return the best SD download URL.
  Future<String?> _searchPexels(String query, String apiKey) async {
    final resp = await _dio.get(
      'https://api.pexels.com/videos/search',
      queryParameters: {'query': query, 'per_page': 5, 'orientation': 'portrait'},
      options: Options(
        headers: {'Authorization': apiKey},
        receiveTimeout: const Duration(seconds: 20),
      ),
    );

    final videos = resp.data['videos'] as List?;
    if (videos == null || videos.isEmpty) return null;

    // Pick a random video from the first 5 results
    videos.shuffle();
    final video = videos.first;
    final files = video['video_files'] as List?;
    if (files == null || files.isEmpty) return null;

    // Prefer HD (720p) to keep file sizes manageable
    final sorted = List.of(files)
      ..sort((a, b) {
        final aw = a['width'] as int? ?? 0;
        final bw = b['width'] as int? ?? 0;
        return (aw - 720).abs().compareTo((bw - 720).abs());
      });

    return sorted.first['link'] as String?;
  }

  Future<void> _download(
    String url,
    String dest, {
    required void Function(int recv, int total) onProgress,
  }) async {
    await _dio.download(
      url,
      dest,
      onReceiveProgress: onProgress,
      options: Options(receiveTimeout: const Duration(minutes: 3)),
    );
  }

  int _clipsNeeded(int durationSec) => (durationSec / 5).ceil().clamp(3, 20);

  List<String> _cycleTo(List<String> src, int count) {
    final out = <String>[];
    if (src.isEmpty) return out;
    for (var i = 0; i < count; i++) {
      out.add(src[i % src.length]);
    }
    return out;
  }

  String _slug(String s) =>
      s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '_').substring(
            0,
            s.length.clamp(0, 20),
          );
}
