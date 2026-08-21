import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import '../models/app_config.dart';

/// Result of a visual fetch — either a still image or a video clip.
class VisualAsset {
  final String path;
  final bool isVideo;
  const VisualAsset({required this.path, required this.isVideo});
}

/// Unified provider for both AI-generated images and stock media search.
class VisualService {
  final Dio _dio = Dio();
  final Random _rng = Random();

  Future<VisualAsset> fetch({
    required String imagePrompt,
    required String searchQuery,
    required int sceneIndex,
    required AppConfig cfg,
  }) async {
    switch (cfg.visualSource) {
      case VisualSource.dalle3:
        return _dalle3(imagePrompt, sceneIndex, cfg);
      case VisualSource.stabilityAi:
        return _stabilityAi(imagePrompt, sceneIndex, cfg);
      case VisualSource.flux:
        return _flux(imagePrompt, sceneIndex, cfg);
      case VisualSource.pexels:
        return _pexels(searchQuery, sceneIndex, cfg);
      case VisualSource.pixabay:
        return _pixabay(searchQuery, sceneIndex, cfg);
      case VisualSource.coverr:
        return _coverr(searchQuery, sceneIndex, cfg);
    }
  }

  // ── AI generators ────────────────────────────────────────────────────────

  Future<VisualAsset> _dalle3(String prompt, int idx, AppConfig cfg) async {
    final key = _cleanKey(cfg.visualApiKey);
    final resp = await _dio.post(
      'https://api.openai.com/v1/images/generations',
      options: Options(
        headers: {
          'Authorization': 'Bearer $key',
          'Content-Type': 'application/json',
        },
        receiveTimeout: const Duration(minutes: 2),
      ),
      data: {
        'model': 'dall-e-3',
        'prompt': '$prompt, cinematic 4K portrait 9:16',
        'n': 1,
        'size': '1024x1792',
        'quality': 'standard',
        'response_format': 'url',
      },
    );
    final url = resp.data['data'][0]['url'] as String;
    final path = await _download(url, idx, 'jpg');
    return VisualAsset(path: path, isVideo: false);
  }

  Future<VisualAsset> _stabilityAi(String prompt, int idx, AppConfig cfg) async {
    final key = _cleanKey(cfg.visualApiKey);
    final resp = await _dio.post(
      'https://api.stability.ai/v2beta/stable-image/generate/sd3',
      options: Options(
        headers: {
          'Authorization': 'Bearer $key',
          'Accept': 'application/json',
        },
        contentType: 'multipart/form-data',
        receiveTimeout: const Duration(minutes: 3),
      ),
      data: FormData.fromMap({
        'prompt': '$prompt, cinematic 4K portrait',
        'model': cfg.visualModel.isNotEmpty ? cfg.visualModel : 'sd3-medium',
        'aspect_ratio': '9:16',
        'output_format': 'jpeg',
      }),
    );
    final b64 = resp.data['image'] as String?;
    if (b64 == null || b64.isEmpty) {
      throw Exception('Stability AI returned no image data.');
    }
    final tmpDir = await getTemporaryDirectory();
    final path = '${tmpDir.path}/scene_${idx}_img.jpg';
    await File(path).writeAsBytes(base64Decode(b64));
    return VisualAsset(path: path, isVideo: false);
  }

  Future<VisualAsset> _flux(String prompt, int idx, AppConfig cfg) async {
    final model = cfg.visualModel.isNotEmpty
        ? cfg.visualModel
        : 'fal-ai/flux/schnell';
    final key = _cleanKey(cfg.visualApiKey);
    final resp = await _dio.post(
      'https://fal.run/$model',
      options: Options(
        headers: {
          'Authorization': 'Key $key',
          'Content-Type': 'application/json',
        },
        receiveTimeout: const Duration(minutes: 3),
      ),
      data: {
        'prompt': '$prompt, cinematic 4K portrait',
        'image_size': 'portrait_16_9',
        'num_inference_steps': 4,
        'num_images': 1,
        'enable_safety_checker': true,
        'output_format': 'jpeg',
      },
    );
    final images = resp.data['images'] as List?;
    if (images == null || images.isEmpty) {
      throw Exception('Flux returned no images.');
    }
    final url = images[0]['url'] as String;
    final path = await _download(url, idx, 'jpg');
    return VisualAsset(path: path, isVideo: false);
  }

  // ── Stock providers ──────────────────────────────────────────────────────

  Future<VisualAsset> _pexels(String query, int idx, AppConfig cfg) async {
    if (query.isEmpty) throw Exception('Pexels: empty search query');
    final key = _cleanKey(cfg.visualApiKey);
    final resp = await _dio.get(
      'https://api.pexels.com/videos/search',
      queryParameters: {
        'query': query,
        'per_page': 10,
        'orientation': 'portrait',
      },
      options: Options(
        headers: {'Authorization': key},
        receiveTimeout: const Duration(seconds: 20),
        validateStatus: (_) => true,
      ),
    );
    if (resp.statusCode != 200) {
      throw Exception('Pexels HTTP ${resp.statusCode}: ${_err(resp.data)} '
          '(check Settings → Visuals → API Key)');
    }
    final videos = resp.data['videos'] as List?;
    if (videos == null || videos.isEmpty) {
      throw Exception('Pexels: no videos for "$query"');
    }
    final video = videos[_rng.nextInt(videos.length.clamp(1, 5))];
    final files = (video['video_files'] as List)
        .cast<Map<String, dynamic>>();
    // Prefer HD portrait ~720p to keep downloads fast.
    files.sort((a, b) {
      final aw = (a['width'] as int?) ?? 0;
      final bw = (b['width'] as int?) ?? 0;
      return (aw - 720).abs().compareTo((bw - 720).abs());
    });
    final url = files.first['link'] as String;
    final path = await _download(url, idx, 'mp4');
    return VisualAsset(path: path, isVideo: true);
  }

  Future<VisualAsset> _pixabay(String query, int idx, AppConfig cfg) async {
    if (query.isEmpty) throw Exception('Pixabay: empty search query');
    final key = _cleanKey(cfg.visualApiKey);
    final resp = await _dio.get(
      'https://pixabay.com/api/videos/',
      queryParameters: {
        'key': key,
        'q': query,
        'per_page': 10,
        'safesearch': 'true',
      },
      options: Options(
        receiveTimeout: const Duration(seconds: 20),
        validateStatus: (_) => true,
      ),
    );
    if (resp.statusCode != 200) {
      throw Exception('Pixabay HTTP ${resp.statusCode}: ${_err(resp.data)}');
    }
    final hits = resp.data['hits'] as List?;
    if (hits == null || hits.isEmpty) {
      throw Exception('Pixabay: no videos for "$query"');
    }
    final video = hits[_rng.nextInt(hits.length.clamp(1, 5))];
    final videos = video['videos'] as Map<String, dynamic>;
    // Pixabay: large > medium > small > tiny. Pick medium (~960px) or large.
    final pick =
        (videos['medium'] ?? videos['large'] ?? videos['small'] ?? videos['tiny'])
            as Map<String, dynamic>;
    final url = pick['url'] as String;
    final path = await _download(url, idx, 'mp4');
    return VisualAsset(path: path, isVideo: true);
  }

  Future<VisualAsset> _coverr(String query, int idx, AppConfig cfg) async {
    if (query.isEmpty) throw Exception('Coverr: empty search query');
    final key = _cleanKey(cfg.visualApiKey);
    final resp = await _dio.get(
      'https://api.coverr.co/videos',
      queryParameters: {
        'urls': 'true',
        'query': query,
        'page_size': 10,
      },
      options: Options(
        headers: {'Authorization': 'Bearer $key'},
        receiveTimeout: const Duration(seconds: 20),
        validateStatus: (_) => true,
      ),
    );
    if (resp.statusCode == 401 || resp.statusCode == 403) {
      throw Exception('Coverr HTTP ${resp.statusCode}: ${_err(resp.data)}');
    }
    final hits = (resp.data['hits'] as List?) ?? [];
    if (hits.isEmpty) {
      throw Exception('Coverr: no videos for "$query"');
    }
    final video = hits[_rng.nextInt(hits.length.clamp(1, 5))];
    // Coverr's video download URL — prefer 'mp4' key in urls map.
    final urls = video['urls'] as Map<String, dynamic>?;
    final url = (urls?['mp4'] ?? urls?['mp4_download'] ?? urls?['poster']) as String?;
    if (url == null) throw Exception('Coverr: no downloadable URL');
    final path = await _download(url, idx, 'mp4');
    return VisualAsset(path: path, isVideo: true);
  }

  // ── Helpers ──────────────────────────────────────────────────────────────

  Future<String> _download(String url, int idx, String ext) async {
    final tmpDir = await getTemporaryDirectory();
    final path = '${tmpDir.path}/scene_${idx}_visual.$ext';
    await _dio.download(
      url,
      path,
      options: Options(receiveTimeout: const Duration(minutes: 3)),
    );
    return path;
  }

  // ── Key validation ────────────────────────────────────────────────────────

  Future<String?> testKey(AppConfig cfg) async {
    try {
      final key = _cleanKey(cfg.visualApiKey);
      switch (cfg.visualSource) {
        case VisualSource.dalle3:
          final r = await _dio.get(
            'https://api.openai.com/v1/models',
            options: Options(
              headers: {'Authorization': 'Bearer $key'},
              validateStatus: (_) => true,
            ),
          );
          if (r.statusCode != 200) return 'HTTP ${r.statusCode}: ${_err(r.data)}';
          return null;

        case VisualSource.stabilityAi:
          final r = await _dio.get(
            'https://api.stability.ai/v1/user/account',
            options: Options(
              headers: {'Authorization': 'Bearer $key'},
              validateStatus: (_) => true,
            ),
          );
          if (r.statusCode != 200) return 'HTTP ${r.statusCode}: ${_err(r.data)}';
          return null;

        case VisualSource.flux:
          final r = await _dio.get(
            'https://queue.fal.run/fal-ai/flux/schnell',
            options: Options(
              headers: {'Authorization': 'Key $key'},
              validateStatus: (_) => true,
            ),
          );
          if (r.statusCode == 401 || r.statusCode == 403) {
            return 'HTTP ${r.statusCode}: ${_err(r.data)}';
          }
          return null;

        case VisualSource.pexels:
          // Use the same /videos/search endpoint the app actually calls,
          // so the test proves what the app does.
          final r = await _dio.get(
            'https://api.pexels.com/videos/search',
            queryParameters: {'query': 'nature', 'per_page': 1},
            options: Options(
              headers: {'Authorization': key},
              validateStatus: (_) => true,
            ),
          );
          if (r.statusCode != 200) return 'HTTP ${r.statusCode}: ${_err(r.data)}';
          return null;

        case VisualSource.pixabay:
          final r = await _dio.get(
            'https://pixabay.com/api/videos/',
            queryParameters: {'key': key, 'q': 'nature', 'per_page': 3},
            options: Options(validateStatus: (_) => true),
          );
          if (r.statusCode != 200) return 'HTTP ${r.statusCode}: ${_err(r.data)}';
          return null;

        case VisualSource.coverr:
          final r = await _dio.get(
            'https://api.coverr.co/videos',
            queryParameters: {'page_size': 1},
            options: Options(
              headers: {'Authorization': 'Bearer $key'},
              validateStatus: (_) => true,
            ),
          );
          if (r.statusCode == 401 || r.statusCode == 403) {
            return 'HTTP ${r.statusCode}: ${_err(r.data)}';
          }
          return null;
      }
    } catch (e) {
      if (e is DioException && e.response != null) {
        return 'HTTP ${e.response!.statusCode}: ${_err(e.response!.data)}';
      }
      return e.toString();
    }
  }

  /// Strip whitespace and a leading "Bearer " that users often copy from docs.
  String _cleanKey(String raw) {
    var k = raw.trim();
    if (k.toLowerCase().startsWith('bearer ')) k = k.substring(7).trim();
    if (k.toLowerCase().startsWith('key ')) k = k.substring(4).trim();
    return k;
  }

  String _err(dynamic body) {
    if (body is Map) {
      final err = body['error'];
      if (err is Map) return (err['message'] as String?) ?? body.toString();
      if (err is String) return err;
      return (body['message'] as String?) ?? body.toString();
    }
    return body?.toString() ?? 'unknown error';
  }
}
