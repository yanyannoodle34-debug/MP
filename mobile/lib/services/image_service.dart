import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import '../models/app_config.dart';

class ImageService {
  final Dio _dio = Dio();

  /// Generates an image for [prompt] using the configured provider
  /// and saves it to a temp file. Returns the local file path.
  Future<String> generate(String prompt, int sceneIndex, AppConfig cfg) async {
    switch (cfg.imageProvider) {
      case ImageGenProvider.dalle3:
        return _dalle3(prompt, sceneIndex, cfg);
      case ImageGenProvider.stabilityAi:
        return _stabilityAi(prompt, sceneIndex, cfg);
      case ImageGenProvider.flux:
        return _flux(prompt, sceneIndex, cfg);
    }
  }

  // ── DALL-E 3 ──────────────────────────────────────────────────────────────

  Future<String> _dalle3(String prompt, int idx, AppConfig cfg) async {
    final resp = await _dio.post(
      'https://api.openai.com/v1/images/generations',
      options: Options(
        headers: {
          'Authorization': 'Bearer ${cfg.imageApiKey}',
          'Content-Type': 'application/json',
        },
        receiveTimeout: const Duration(minutes: 2),
      ),
      data: {
        'model': 'dall-e-3',
        'prompt': '$prompt, cinematic 4K portrait 9:16',
        'n': 1,
        'size': '1024x1792', // portrait 9:16
        'quality': 'standard',
        'response_format': 'url',
      },
    );

    final url = resp.data['data'][0]['url'] as String;
    return _downloadImage(url, idx);
  }

  // ── Stability AI (Stable Diffusion 3) ─────────────────────────────────────

  Future<String> _stabilityAi(String prompt, int idx, AppConfig cfg) async {
    final resp = await _dio.post(
      'https://api.stability.ai/v2beta/stable-image/generate/sd3',
      options: Options(
        headers: {
          'Authorization': 'Bearer ${cfg.imageApiKey}',
          'Accept': 'application/json',
        },
        contentType: 'multipart/form-data',
        receiveTimeout: const Duration(minutes: 3),
      ),
      data: FormData.fromMap({
        'prompt': '$prompt, cinematic 4K portrait',
        'model': cfg.imageModel.isNotEmpty ? cfg.imageModel : 'sd3-medium',
        'aspect_ratio': '9:16',
        'output_format': 'jpeg',
      }),
    );

    // Response contains base64 image
    final b64 = resp.data['image'] as String?;
    if (b64 == null || b64.isEmpty) {
      throw Exception('Stability AI returned no image data.');
    }

    final tmpDir = await getTemporaryDirectory();
    final path = '${tmpDir.path}/scene_${idx}_img.jpg';
    await File(path).writeAsBytes(base64Decode(b64));
    return path;
  }

  // ── fal.ai Flux ───────────────────────────────────────────────────────────

  Future<String> _flux(String prompt, int idx, AppConfig cfg) async {
    // fal.ai Flux Schnell — fast, free tier available
    final model = cfg.imageModel.isNotEmpty
        ? cfg.imageModel
        : 'fal-ai/flux/schnell';

    final resp = await _dio.post(
      'https://fal.run/$model',
      options: Options(
        headers: {
          'Authorization': 'Key ${cfg.imageApiKey}',
          'Content-Type': 'application/json',
        },
        receiveTimeout: const Duration(minutes: 3),
      ),
      data: {
        'prompt': '$prompt, cinematic 4K portrait',
        'image_size': 'portrait_16_9',
        'num_inference_steps': 4, // schnell is very fast
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
    return _downloadImage(url, idx);
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  Future<String> _downloadImage(String url, int idx) async {
    final tmpDir = await getTemporaryDirectory();
    final path = '${tmpDir.path}/scene_${idx}_img.jpg';
    await _dio.download(
      url,
      path,
      options: Options(receiveTimeout: const Duration(minutes: 2)),
    );
    return path;
  }

  // ── Key validation ────────────────────────────────────────────────────────
  /// Cheap auth check. Returns null on success, error message on failure.
  /// Uses each provider's lightest available auth-checking endpoint.
  Future<String?> testKey(AppConfig cfg) async {
    try {
      switch (cfg.imageProvider) {
        case ImageGenProvider.dalle3:
          // GET /models is auth-only, no image generation cost.
          final r = await _dio.get(
            'https://api.openai.com/v1/models',
            options: Options(
              headers: {'Authorization': 'Bearer ${cfg.imageApiKey}'},
              receiveTimeout: const Duration(seconds: 15),
              validateStatus: (_) => true,
            ),
          );
          if (r.statusCode != 200) return 'HTTP ${r.statusCode}: ${_err(r.data)}';
          return null;

        case ImageGenProvider.stabilityAi:
          // GET /v1/user/account — free, auth-only.
          final r = await _dio.get(
            'https://api.stability.ai/v1/user/account',
            options: Options(
              headers: {'Authorization': 'Bearer ${cfg.imageApiKey}'},
              receiveTimeout: const Duration(seconds: 15),
              validateStatus: (_) => true,
            ),
          );
          if (r.statusCode != 200) return 'HTTP ${r.statusCode}: ${_err(r.data)}';
          return null;

        case ImageGenProvider.flux:
          // fal.ai — call queue status endpoint, auth-only.
          final r = await _dio.get(
            'https://queue.fal.run/fal-ai/flux/schnell',
            options: Options(
              headers: {'Authorization': 'Key ${cfg.imageApiKey}'},
              receiveTimeout: const Duration(seconds: 15),
              validateStatus: (_) => true,
            ),
          );
          // 401/403 = bad key; anything else (400, 404, 200) = auth passed
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
