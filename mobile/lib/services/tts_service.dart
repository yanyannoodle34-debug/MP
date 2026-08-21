import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:web_socket_channel/io.dart';
import '../models/app_config.dart';

class TtsService {
  final Dio _dio = Dio();

  /// Synthesizes [text] to an audio file. Returns local path + duration (seconds).
  Future<({String path, double duration})> synthesize(
    String text,
    int sceneIndex,
    AppConfig cfg,
  ) async {
    switch (cfg.ttsProvider) {
      case TtsProvider.edgeTts:
        return _edgeTts(text, sceneIndex, cfg);
      case TtsProvider.deviceTts:
        // Device TTS was intentionally not re-added (dep conflicts).
        // Fall back to edge for now — same result: free voice.
        return _edgeTts(text, sceneIndex, cfg);
      case TtsProvider.azureTts:
        return _azureTts(text, sceneIndex, cfg);
      case TtsProvider.openaiTts:
        return _openaiTts(text, sceneIndex, cfg);
      case TtsProvider.elevenLabs:
        return _elevenLabs(text, sceneIndex, cfg);
    }
  }

  // ── Edge TTS (free, no key) ──────────────────────────────────────────────
  // Uses Microsoft's public Cognitive Services streaming endpoint.
  // Same tech MoneyPrinterTurbo uses. No API key required.

  static const _edgeTrustedToken = '6A5AA1D4EAFF4E9FB37E23D68491D6F4';
  static const _edgeWsUrl =
      'wss://speech.platform.bing.com/consumer/speech/synthesize/readaloud/edge/v1'
      '?TrustedClientToken=$_edgeTrustedToken';

  Future<({String path, double duration})> _edgeTts(
    String text,
    int idx,
    AppConfig cfg,
  ) async {
    final voice = cfg.ttsVoiceId.isNotEmpty
        ? cfg.ttsVoiceId
        : 'en-US-AriaNeural';

    final ws = IOWebSocketChannel.connect(
      Uri.parse(_edgeWsUrl),
      headers: {
        'Origin': 'chrome-extension://jdiccldimpdaibmpdkjnbmckianbfold',
        'User-Agent':
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
                '(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36 Edg/120.0.0.0',
      },
    );

    // Send audio format config
    final configId = _uuid();
    ws.sink.add(
      'X-Timestamp:${_isoNow()}\r\n'
      'Content-Type:application/json; charset=utf-8\r\n'
      'Path:speech.config\r\n\r\n'
      '{"context":{"synthesis":{"audio":{"metadataoptions":{"sentenceBoundaryEnabled":"false","wordBoundaryEnabled":"false"},"outputFormat":"audio-24khz-48kbitrate-mono-mp3"}}}}',
    );

    // Send SSML
    final ssml =
        '<speak version="1.0" xml:lang="en-US" xmlns="http://www.w3.org/2001/10/synthesis">'
        '<voice name="$voice">'
        '<prosody rate="+0%" pitch="+0Hz">${_escapeXml(text)}</prosody>'
        '</voice></speak>';

    ws.sink.add(
      'X-RequestId:$configId\r\n'
      'Content-Type:application/ssml+xml\r\n'
      'X-Timestamp:${_isoNow()}\r\n'
      'Path:ssml\r\n\r\n$ssml',
    );

    final chunks = <int>[];
    final completer = Completer<void>();

    ws.stream.listen(
      (message) {
        if (message is List<int>) {
          // Binary: parse header + audio payload.
          // Format: [2-byte header length BE][header bytes][audio bytes]
          final bytes = Uint8List.fromList(message);
          if (bytes.length < 2) return;
          final headerLen = (bytes[0] << 8) | bytes[1];
          if (bytes.length > headerLen + 2) {
            chunks.addAll(bytes.sublist(headerLen + 2));
          }
        } else if (message is String) {
          if (message.contains('Path:turn.end')) {
            if (!completer.isCompleted) completer.complete();
          }
        }
      },
      onError: (e) {
        if (!completer.isCompleted) completer.completeError(e);
      },
      onDone: () {
        if (!completer.isCompleted) completer.complete();
      },
      cancelOnError: true,
    );

    try {
      await completer.future.timeout(const Duration(minutes: 2));
    } finally {
      await ws.sink.close();
    }

    if (chunks.isEmpty) {
      throw Exception(
        'Edge TTS returned no audio. Voice "$voice" may be invalid or '
        'network is blocked.',
      );
    }

    return _saveAudio(chunks, idx, 'mp3');
  }

  // ── Azure TTS ────────────────────────────────────────────────────────────

  Future<({String path, double duration})> _azureTts(
    String text,
    int idx,
    AppConfig cfg,
  ) async {
    final region = cfg.azureRegion.isNotEmpty ? cfg.azureRegion : 'eastus';
    final voice = cfg.ttsVoiceId.isNotEmpty
        ? cfg.ttsVoiceId
        : 'en-US-AriaNeural';

    final ssml =
        '<speak version="1.0" xml:lang="en-US">'
        '<voice name="$voice">${_escapeXml(text)}</voice></speak>';

    final resp = await _dio.post(
      'https://$region.tts.speech.microsoft.com/cognitiveservices/v1',
      options: Options(
        headers: {
          'Ocp-Apim-Subscription-Key': cfg.ttsApiKey,
          'Content-Type': 'application/ssml+xml',
          'X-Microsoft-OutputFormat': 'audio-24khz-48kbitrate-mono-mp3',
          'User-Agent': 'CloudAICreator',
        },
        responseType: ResponseType.bytes,
        receiveTimeout: const Duration(minutes: 2),
      ),
      data: ssml,
    );

    return _saveAudio(resp.data as List<int>, idx, 'mp3');
  }

  // ── ElevenLabs ────────────────────────────────────────────────────────────

  Future<({String path, double duration})> _elevenLabs(
    String text,
    int idx,
    AppConfig cfg,
  ) async {
    final voiceId = cfg.ttsVoiceId.isNotEmpty
        ? cfg.ttsVoiceId
        : 'EXAVITQu4vr4xnSDxMaL';

    final resp = await _dio.post(
      'https://api.elevenlabs.io/v1/text-to-speech/$voiceId',
      options: Options(
        headers: {
          'xi-api-key': cfg.ttsApiKey,
          'Content-Type': 'application/json',
          'Accept': 'audio/mpeg',
        },
        responseType: ResponseType.bytes,
        receiveTimeout: const Duration(minutes: 2),
      ),
      data: {
        'text': text,
        'model_id': 'eleven_turbo_v2',
        'voice_settings': {'stability': 0.5, 'similarity_boost': 0.75},
      },
    );

    return _saveAudio(resp.data as List<int>, idx, 'mp3');
  }

  // ── OpenAI TTS ────────────────────────────────────────────────────────────

  Future<({String path, double duration})> _openaiTts(
    String text,
    int idx,
    AppConfig cfg,
  ) async {
    final resp = await _dio.post(
      'https://api.openai.com/v1/audio/speech',
      options: Options(
        headers: {
          'Authorization': 'Bearer ${cfg.ttsApiKey}',
          'Content-Type': 'application/json',
        },
        responseType: ResponseType.bytes,
        receiveTimeout: const Duration(minutes: 2),
      ),
      data: {
        'model': 'tts-1',
        'input': text,
        'voice': cfg.ttsVoice.isNotEmpty ? cfg.ttsVoice : 'nova',
        'response_format': 'mp3',
      },
    );

    return _saveAudio(resp.data as List<int>, idx, 'mp3');
  }

  // ── Voice listing ────────────────────────────────────────────────────────

  Future<List<({String id, String name})>> fetchVoices(AppConfig cfg) async {
    switch (cfg.ttsProvider) {
      case TtsProvider.edgeTts:
      case TtsProvider.deviceTts:
      case TtsProvider.azureTts:
        // Curated shortlist of high-quality neural voices supported by both
        // Edge and Azure. Users can also type any Azure voice manually.
        return const [
          (id: 'en-US-AriaNeural', name: 'Aria (US, F)'),
          (id: 'en-US-GuyNeural', name: 'Guy (US, M)'),
          (id: 'en-US-JennyNeural', name: 'Jenny (US, F)'),
          (id: 'en-US-DavisNeural', name: 'Davis (US, M)'),
          (id: 'en-GB-SoniaNeural', name: 'Sonia (UK, F)'),
          (id: 'en-GB-RyanNeural', name: 'Ryan (UK, M)'),
          (id: 'en-AU-NatashaNeural', name: 'Natasha (AU, F)'),
          (id: 'zh-CN-XiaoxiaoNeural', name: 'Xiaoxiao (中文, F)'),
          (id: 'zh-CN-YunxiNeural', name: 'Yunxi (中文, M)'),
          (id: 'ja-JP-NanamiNeural', name: 'Nanami (日本語, F)'),
          (id: 'es-ES-ElviraNeural', name: 'Elvira (ES, F)'),
          (id: 'fr-FR-DeniseNeural', name: 'Denise (FR, F)'),
          (id: 'de-DE-KatjaNeural', name: 'Katja (DE, F)'),
        ];

      case TtsProvider.openaiTts:
        const v = ['alloy', 'echo', 'fable', 'onyx', 'nova', 'shimmer'];
        return v.map((s) => (id: s, name: s)).toList();

      case TtsProvider.elevenLabs:
        final r = await _dio.get(
          'https://api.elevenlabs.io/v1/voices',
          options: Options(
            headers: {'xi-api-key': cfg.ttsApiKey},
            receiveTimeout: const Duration(seconds: 20),
          ),
        );
        final voices = r.data['voices'] as List? ?? [];
        return voices
            .map((v) => (
                  id: (v['voice_id'] as String?) ?? '',
                  name: (v['name'] as String?) ?? '(unnamed)',
                ))
            .where((v) => v.id.isNotEmpty)
            .toList();
    }
  }

  // ── Key validation ────────────────────────────────────────────────────────

  Future<String?> testKey(AppConfig cfg) async {
    try {
      switch (cfg.ttsProvider) {
        case TtsProvider.edgeTts:
        case TtsProvider.deviceTts:
          // Free provider — try a tiny synthesis to confirm connectivity.
          try {
            await synthesize('Hello.', 999, cfg).timeout(const Duration(seconds: 15));
            return null;
          } catch (e) {
            return e.toString();
          }

        case TtsProvider.elevenLabs:
          final r = await _dio.get(
            'https://api.elevenlabs.io/v1/user',
            options: Options(
              headers: {'xi-api-key': cfg.ttsApiKey},
              validateStatus: (_) => true,
            ),
          );
          if (r.statusCode != 200) return 'HTTP ${r.statusCode}: ${_err(r.data)}';
          return null;

        case TtsProvider.openaiTts:
          final r = await _dio.get(
            'https://api.openai.com/v1/models',
            options: Options(
              headers: {'Authorization': 'Bearer ${cfg.ttsApiKey}'},
              validateStatus: (_) => true,
            ),
          );
          if (r.statusCode != 200) return 'HTTP ${r.statusCode}: ${_err(r.data)}';
          return null;

        case TtsProvider.azureTts:
          // POST /issueToken — auth-only, no synthesis cost.
          final region = cfg.azureRegion.isNotEmpty ? cfg.azureRegion : 'eastus';
          final r = await _dio.post(
            'https://$region.api.cognitive.microsoft.com/sts/v1.0/issueToken',
            options: Options(
              headers: {'Ocp-Apim-Subscription-Key': cfg.ttsApiKey},
              validateStatus: (_) => true,
            ),
          );
          if (r.statusCode != 200) return 'HTTP ${r.statusCode}: ${_err(r.data)}';
          return null;
      }
    } catch (e) {
      if (e is DioException && e.response != null) {
        return 'HTTP ${e.response!.statusCode}: ${_err(e.response!.data)}';
      }
      return e.toString();
    }
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  Future<({String path, double duration})> _saveAudio(
    List<int> bytes,
    int idx,
    String ext,
  ) async {
    final tmpDir = await getTemporaryDirectory();
    final path = '${tmpDir.path}/scene_${idx}_audio.$ext';
    await File(path).writeAsBytes(bytes);
    final sizeKb = bytes.length / 1024;
    final estimatedSec = (sizeKb * 8) / 48; // 48 kbps mp3
    return (path: path, duration: estimatedSec.clamp(1.0, 60.0));
  }

  Future<void> dispose() async {}

  String _err(dynamic body) {
    if (body is Map) {
      final err = body['error'];
      if (err is Map) return (err['message'] as String?) ?? body.toString();
      if (err is String) return err;
      return (body['message'] as String?) ?? body.toString();
    }
    return body?.toString() ?? 'unknown error';
  }

  String _escapeXml(String s) => s
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;')
      .replaceAll("'", '&apos;');

  String _isoNow() {
    final now = DateTime.now().toUtc();
    return now.toIso8601String().replaceFirst(RegExp(r'\.\d+'), '') + 'Z';
  }

  String _uuid() {
    // Simple hex UUID (32 chars, no dashes) — good enough for Edge's request-id.
    final now = DateTime.now().microsecondsSinceEpoch.toRadixString(16).padLeft(16, '0');
    final rand = base64Url
        .encode(List.generate(8, (_) => now.codeUnitAt(_ % now.length)))
        .replaceAll(RegExp(r'[^0-9a-fA-F]'), '')
        .padRight(16, '0')
        .substring(0, 16);
    return (now + rand).substring(0, 32);
  }
}
