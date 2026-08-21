enum LlmProvider { openrouter, openai, deepseek }

enum ImageGenProvider { dalle3, stabilityAi, flux }

enum TtsProvider { elevenLabs, openaiTts }

extension LlmProviderInfo on LlmProvider {
  String get displayName => switch (this) {
        LlmProvider.openrouter => 'OpenRouter',
        LlmProvider.openai => 'OpenAI',
        LlmProvider.deepseek => 'DeepSeek',
      };

  String get baseUrl => switch (this) {
        LlmProvider.openrouter => 'https://openrouter.ai/api/v1',
        LlmProvider.openai => 'https://api.openai.com/v1',
        LlmProvider.deepseek => 'https://api.deepseek.com/v1',
      };

  String get defaultModel => switch (this) {
        LlmProvider.openrouter => 'openai/gpt-4o-mini',
        LlmProvider.openai => 'gpt-4o-mini',
        LlmProvider.deepseek => 'deepseek-chat',
      };

  String get keyHint => switch (this) {
        LlmProvider.openrouter => 'sk-or-…  openrouter.ai/keys',
        LlmProvider.openai => 'sk-…  platform.openai.com',
        LlmProvider.deepseek => 'sk-…  platform.deepseek.com',
      };
}

class AppConfig {
  // ── LLM ──────────────────────────────────────────────────────────────────
  final LlmProvider llmProvider;
  final String llmApiKey;
  final String llmModel;

  // ── Image ─────────────────────────────────────────────────────────────────
  final ImageGenProvider imageProvider;
  final String imageApiKey;
  final String imageModel;

  // ── TTS ───────────────────────────────────────────────────────────────────
  final TtsProvider ttsProvider;
  final String ttsApiKey;
  final String ttsVoiceId;
  final String ttsVoice;

  // ── Video ─────────────────────────────────────────────────────────────────
  final bool subtitlesEnabled;
  final int sceneCount;
  final bool kenBurnsEnabled;

  const AppConfig({
    this.llmProvider = LlmProvider.openrouter,
    this.llmApiKey = '',
    this.llmModel = 'openai/gpt-4o-mini',
    this.imageProvider = ImageGenProvider.dalle3,
    this.imageApiKey = '',
    this.imageModel = 'dall-e-3',
    this.ttsProvider = TtsProvider.elevenLabs,
    this.ttsApiKey = '',
    this.ttsVoiceId = 'EXAVITQu4vr4xnSDxMaL',
    this.ttsVoice = 'nova',
    this.subtitlesEnabled = true,
    this.sceneCount = 5,
    this.kenBurnsEnabled = true,
  });

  String get llmBaseUrl => llmProvider.baseUrl;

  AppConfig copyWith({
    LlmProvider? llmProvider,
    String? llmApiKey,
    String? llmModel,
    ImageGenProvider? imageProvider,
    String? imageApiKey,
    String? imageModel,
    TtsProvider? ttsProvider,
    String? ttsApiKey,
    String? ttsVoiceId,
    String? ttsVoice,
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
        imageProvider: ImageGenProvider.values.firstWhere(
          (e) => e.name == j['imageProvider'],
          orElse: () => ImageGenProvider.dalle3,
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
        subtitlesEnabled: j['subtitlesEnabled'] as bool? ?? true,
        sceneCount: j['sceneCount'] as int? ?? 5,
        kenBurnsEnabled: j['kenBurnsEnabled'] as bool? ?? true,
      );
}
