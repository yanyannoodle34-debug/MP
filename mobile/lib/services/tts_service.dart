import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
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
      case TtsProvider.deviceTts:
        // Try Edge TTS first (Microsoft neural voices, free, high quality).
        // Fall back to StreamElements (Amazon Polly, free, public) if Edge fails
        // — this makes the "free" option always work.
        try {
          return await _edgeTts(text, sceneIndex, cfg);
        } catch (e) {
          try {
            return await _streamElementsTts(text, sceneIndex, cfg);
          } catch (_) {
            rethrow; // surface the original edge error, more informative
          }
        }
      case TtsProvider.azureTts:
        return _azureTts(text, sceneIndex, cfg);
      case TtsProvider.openaiTts:
        return _openaiTts(text, sceneIndex, cfg);
      case TtsProvider.elevenLabs:
        return _elevenLabs(text, sceneIndex, cfg);
    }
  }

  // ── Edge TTS (free, no key) ──────────────────────────────────────────────
  // Microsoft's public streaming endpoint. Same tech MoneyPrinterTurbo uses.
  //
  // The endpoint requires a Sec-MS-GEC security token in the URL — this is a
  // SHA-256 hash of a Windows FILETIME tick value (rounded to 5-min intervals)
  // + the trusted client token. Without it the WebSocket upgrade is rejected
  // with 400/403 ("was not upgraded to websocket").

  static const _edgeTrustedToken = '6A5AA1D4EAFF4E9FB37E23D68491D6F4';
  static const _edgeGecVersion = '1-131.0.2903.51';

  String _generateSecMsGec() {
    // Windows FILETIME: 100-nanosecond ticks since 1601-01-01 UTC.
    // (unix_seconds + 11644473600) * 10_000_000
    final unixSecs =
        BigInt.from(DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000);
    var ticks = (unixSecs + BigInt.from(11644473600)) * BigInt.from(10000000);
    // Round DOWN to the nearest 300s (5-minute) interval — the trusted token
    // rotates every 5 min; both client and server compute the same rounded tick.
    final interval = BigInt.from(3000000000); // 300s in 100-ns ticks
    ticks -= ticks % interval;
    final toHash = '$ticks$_edgeTrustedToken';
    return sha256.convert(utf8.encode(toHash)).toString().toUpperCase();
  }

  Future<({String path, double duration})> _edgeTts(
    String text,
    int idx,
    AppConfig cfg,
  ) async {
    final voice = cfg.ttsVoiceId.isNotEmpty
        ? cfg.ttsVoiceId
        : 'en-US-AriaNeural';

    final gec = _generateSecMsGec();
    final wsUrl = 'wss://speech.platform.bing.com'
        '/consumer/speech/synthesize/readaloud/edge/v1'
        '?TrustedClientToken=$_edgeTrustedToken'
        '&Sec-MS-GEC=$gec'
        '&Sec-MS-GEC-Version=$_edgeGecVersion';

    final ws = IOWebSocketChannel.connect(
      Uri.parse(wsUrl),
      headers: {
        'Pragma': 'no-cache',
        'Cache-Control': 'no-cache',
        'Origin': 'chrome-extension://jdiccldimpdaibmpdkjnbmckianbfold',
        'Accept-Encoding': 'gzip, deflate, br',
        'Accept-Language': 'en-US,en;q=0.9',
        'User-Agent':
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
                '(KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36 Edg/131.0.0.0',
      },
    );

    final connectId = _uuid32();

    // 1) Send speech.config
    final configTs = _isoTimestamp();
    ws.sink.add(
      'X-Timestamp:$configTs\r\n'
      'Content-Type:application/json; charset=utf-8\r\n'
      'Path:speech.config\r\n\r\n'
      '{"context":{"synthesis":{"audio":{"metadataoptions":'
      '{"sentenceBoundaryEnabled":"false","wordBoundaryEnabled":"false"},'
      '"outputFormat":"audio-24khz-48kbitrate-mono-mp3"}}}}',
    );

    // 2) Send SSML
    final escaped = _escapeXml(text);
    final ssml =
        '<speak version="1.0" xmlns="http://www.w3.org/2001/10/synthesis" '
        'xml:lang="en-US">'
        '<voice name="$voice">'
        '<prosody pitch="+0Hz" rate="+0%" volume="+0%">$escaped</prosody>'
        '</voice></speak>';

    ws.sink.add(
      'X-RequestId:$connectId\r\n'
      'Content-Type:application/ssml+xml\r\n'
      'X-Timestamp:${_isoTimestamp()}\r\n'
      'Path:ssml\r\n\r\n$ssml',
    );

    final chunks = <int>[];
    final completer = Completer<void>();

    final sub = ws.stream.listen(
      (message) {
        if (message is List<int>) {
          // Binary frame: [2-byte header length BE][header bytes][audio bytes]
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
      await completer.future.timeout(const Duration(seconds: 60));
    } finally {
      await sub.cancel();
      await ws.sink.close();
    }

    if (chunks.isEmpty) {
      throw Exception('Edge TTS returned no audio (voice "$voice" invalid?).');
    }

    return _saveAudio(chunks, idx, 'mp3');
  }

  // ── StreamElements TTS (free fallback, no key) ───────────────────────────
  // Public API used by many streaming tools; wraps Amazon Polly voices.
  // Maps our neural-voice ids to Polly equivalents.

  static const _polyMap = {
    'en-US-AriaNeural': 'Salli',
    'en-US-GuyNeural': 'Matthew',
    'en-US-JennyNeural': 'Joanna',
    'en-US-DavisNeural': 'Matthew',
    'en-GB-SoniaNeural': 'Emma',
    'en-GB-RyanNeural': 'Brian',
    'en-AU-NatashaNeural': 'Nicole',
    'zh-CN-XiaoxiaoNeural': 'Zhiyu',
    'zh-CN-YunxiNeural': 'Zhiyu',
    'ja-JP-NanamiNeural': 'Mizuki',
    'es-ES-ElviraNeural': 'Conchita',
    'fr-FR-DeniseNeural': 'Celine',
    'de-DE-KatjaNeural': 'Marlene',
  };

  Future<({String path, double duration})> _streamElementsTts(
    String text,
    int idx,
    AppConfig cfg,
  ) async {
    final voice = _polyMap[cfg.ttsVoiceId] ?? 'Salli';
    final resp = await _dio.get(
      'https://api.streamelements.com/kappa/v2/speech',
      queryParameters: {'voice': voice, 'text': text},
      options: Options(
        responseType: ResponseType.bytes,
        receiveTimeout: const Duration(minutes: 2),
      ),
    );
    return _saveAudio(resp.data as List<int>, idx, 'mp3');
  }

  // ── Azure TTS ────────────────────────────────────────────────────────────

  Future<({String path, double duration})> _azureTts(
    String text,
    int idx,
    AppConfig cfg,
  ) async {
    final region = cfg.azureRegion.trim().isNotEmpty ? cfg.azureRegion.trim() : 'eastus';
    final voice = cfg.ttsVoiceId.isNotEmpty
        ? cfg.ttsVoiceId
        : 'en-US-AriaNeural';

    final ssml = '<speak version="1.0" xml:lang="en-US">'
        '<voice name="$voice">${_escapeXml(text)}</voice></speak>';

    final resp = await _dio.post(
      'https://$region.tts.speech.microsoft.com/cognitiveservices/v1',
      options: Options(
        headers: {
          'Ocp-Apim-Subscription-Key': _cleanKey(cfg.ttsApiKey),
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
          'xi-api-key': _cleanKey(cfg.ttsApiKey),
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
          'Authorization': 'Bearer ${_cleanKey(cfg.ttsApiKey)}',
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
          // Do a tiny real synthesis to confirm connectivity end-to-end.
          try {
            await synthesize('Hello.', 999, cfg)
                .timeout(const Duration(seconds: 30));
            return null;
          } catch (e) {
            return e.toString();
          }

        case TtsProvider.elevenLabs:
          final r = await _dio.get(
            'https://api.elevenlabs.io/v1/user',
            options: Options(
              headers: {'xi-api-key': _cleanKey(cfg.ttsApiKey)},
              validateStatus: (_) => true,
            ),
          );
          if (r.statusCode != 200) return 'HTTP ${r.statusCode}: ${_err(r.data)}';
          return null;

        case TtsProvider.openaiTts:
          final r = await _dio.get(
            'https://api.openai.com/v1/models',
            options: Options(
              headers: {'Authorization': 'Bearer ${_cleanKey(cfg.ttsApiKey)}'},
              validateStatus: (_) => true,
            ),
          );
          if (r.statusCode != 200) return 'HTTP ${r.statusCode}: ${_err(r.data)}';
          return null;

        case TtsProvider.azureTts:
          final region = cfg.azureRegion.trim().isNotEmpty ? cfg.azureRegion.trim() : 'eastus';
          final r = await _dio.post(
            'https://$region.api.cognitive.microsoft.com/sts/v1.0/issueToken',
            options: Options(
              headers: {'Ocp-Apim-Subscription-Key': _cleanKey(cfg.ttsApiKey)},
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

  String _cleanKey(String raw) {
    var k = raw.trim();
    if (k.toLowerCase().startsWith('bearer ')) k = k.substring(7).trim();
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

  String _escapeXml(String s) => s
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;')
      .replaceAll("'", '&apos;');

  String _isoTimestamp() {
    // Format required by Edge: "Mon Nov 20 2023 14:32:15 GMT+0000 (Coordinated Universal Time)"
    // Simpler ISO also accepted.
    final now = DateTime.now().toUtc();
    return '${now.toIso8601String().replaceFirst(RegExp(r'\.\d+'), '')}Z';
  }

  String _uuid32() {
    // 32 hex chars, no dashes.
    final rng = DateTime.now().microsecondsSinceEpoch;
    final bytes = List<int>.generate(16, (i) => (rng >> (i * 4)) & 0xFF);
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }
}
