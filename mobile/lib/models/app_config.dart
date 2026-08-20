enum LlmProvider { openrouter, openai }

enum ImageProvider { dalle3, stabilityAi, flux }

enum TtsProvider { elevenLabs, openaiTts, device }

class AppConfig {
  // ── LLM ──────────────────────────────────────────────────────────────────
  final LlmProvider llmProvider;
  final String llmApiKey;
  final String llmModel;

  // ── Image ─────────────────────────────────────────────────────────────────
  final ImageProvider imageProvider;
  final String imageApiKey;
  final String imageModel; // e.g. 'dall-e-3', 'sd3-medium', 'fal-ai/flux/schnell'

  // ── TTS ───────────────────────────────────────────────────────────────────
  final TtsProvider ttsProvider;
  final String ttsApiKey;       // ElevenLabs or OpenAI key
  final String ttsVoiceId;      // ElevenLabs voice ID
  final String ttsVoice;        // OpenAI: alloy | echo | fable | onyx | nova | shimmer
  final String ttsLanguage;     // device TTS language code
  final double ttsSpeechRate;   // device TTS rate

  // ── Video ─────────────────────────────────────────────────────────────────
  final bool subtitlesEnabled;
  final int sceneCount;        // 4–8 scenes
  final bool kenBurnsEnabled;  // slow zoom effect on images

  const AppConfig({
    this.llmProvider = LlmProvider.openrouter,
    this.llmApiKey = '',
    this.llmModel = 'openai/gpt-4o-mini',
    this.imageProvider = ImageProvider.dalle3,
    this.imageApiKey = '',
    this.imageModel = 'dall-e-3',
    this.ttsProvider = TtsProvider.elevenLabs,
    this.ttsApiKey = '',
    this.ttsVoiceId = 'EXAVITQu4vr4xnSDxMaL', // ElevenLabs "Sarah"
    this.ttsVoice = 'nova',
    this.ttsLanguage = 'en-US',
    this.ttsSpeechRate = 0.9,
    this.subtitlesEnabled = true,
    this.sceneCount = 5,
    this.kenBurnsEnabled = true,
  });

  String get llmBaseUrl => llmProvider == LlmProvider.openrouter
      ? 'https://openrouter.ai/api/v1'
      : 'https://api.openai.com/v1';

  AppConfig copyWith({
    LlmProvider? llmProvider,
    String? llmApiKey,
    String? llmModel,
    ImageProvider? imageProvider,
    String? imageApiKey,
    String? imageModel,
    TtsProvider? ttsProvider,
    String? ttsApiKey,
    String? ttsVoiceId,
    String? ttsVoice,
    String? ttsLanguage,
    double? ttsSpeechRate,
    bool? subtitlesEnabled,
    int? sceneCount,
    bool? kenBurnsEnabled,
  }) {
    return AppConfig(
      llmProvider: llmProvider ?? this.llmProvider,
      llmApiKey: llmApiKey ?? this.llmApiKey,
      llmModel: llmModel ?? this.llmModel,
      imageProvider: imageProvider ?? this.imageProvider,
      imageApiKey: imageApiKey ?? this.imageApiKey,
      imageModel: imageModel ?? this.imageModel,
      ttsProvider: ttsProvider ?? this.ttsProvider,
      ttsApiKey: ttsApiKey ?? this.ttsApiKey,
      ttsVoiceId: ttsVoiceId ?? this.ttsVoiceId,
      ttsVoice: ttsVoice ?? this.ttsVoice,
      ttsLanguage: ttsLanguage ?? this.ttsLanguage,
      ttsSpeechRate: ttsSpeechRate ?? this.ttsSpeechRate,
      subtitlesEnabled: subtitlesEnabled ?? this.subtitlesEnabled,
      sceneCount: sceneCount ?? this.sceneCount,
      kenBurnsEnabled: kenBurnsEnabled ?? this.kenBurnsEnabled,
    );
  }

  Map<String, dynamic> toJson() => {
        'llmProvider': llmProvider.name,
        'llmApiKey': llmApiKey,
        'llmModel': llmModel,
        'imageProvider': imageProvider.name,
        'imageApiKey': imageApiKey,
        'imageModel': imageModel,
        'ttsProvider': ttsProvider.name,
        'ttsApiKey': ttsApiKey,
        'ttsVoiceId': ttsVoiceId,
        'ttsVoice': ttsVoice,
        'ttsLanguage': ttsLanguage,
        'ttsSpeechRate': ttsSpeechRate,
        'subtitlesEnabled': subtitlesEnabled,
        'sceneCount': sceneCount,
        'kenBurnsEnabled': kenBurnsEnabled,
      };

  factory AppConfig.fromJson(Map<String, dynamic> j) => AppConfig(
        llmProvider: LlmProvider.values.firstWhere(
          (e) => e.name == j['llmProvider'],
          orElse: () => LlmProvider.openrouter,
        ),
        llmApiKey: j['llmApiKey'] as String? ?? '',
        llmModel: j['llmModel'] as String? ?? 'openai/gpt-4o-mini',
        imageProvider: ImageProvider.values.firstWhere(
          (e) => e.name == j['imageProvider'],
          orElse: () => ImageProvider.dalle3,
        ),
        imageApiKey: j['imageApiKey'] as String? ?? '',
        imageModel: j['imageModel'] as String? ?? 'dall-e-3',
        ttsProvider: TtsProvider.values.firstWhere(
          (e) => e.name == j['ttsProvider'],
          orElse: () => TtsProvider.elevenLabs,
        ),
        ttsApiKey: j['ttsApiKey'] as String? ?? '',
        ttsVoiceId: j['ttsVoiceId'] as String? ?? 'EXAVITQu4vr4xnSDxMaL',
        ttsVoice: j['ttsVoice'] as String? ?? 'nova',
        ttsLanguage: j['ttsLanguage'] as String? ?? 'en-US',
        ttsSpeechRate:
            (j['ttsSpeechRate'] as num?)?.toDouble() ?? 0.9,
        subtitlesEnabled: j['subtitlesEnabled'] as bool? ?? true,
        sceneCount: j['sceneCount'] as int? ?? 5,
        kenBurnsEnabled: j['kenBurnsEnabled'] as bool? ?? true,
      );
}
