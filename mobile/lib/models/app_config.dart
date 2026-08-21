enum LlmProvider { openrouter, openai, deepseek }

/// All visual sources — both AI generators and stock media providers.
enum VisualSource {
  dalle3,
  stabilityAi,
  flux,
  pexels,
  pixabay,
  coverr,
}

/// TTS providers, from truly free (edge, device) to paid (openai, elevenlabs, azure).
enum TtsProvider {
  edgeTts,      // free, no key — Microsoft's public streaming endpoint
  deviceTts,    // free, on-device Android TTS
  azureTts,     // paid, 500k chars/month free tier — requires region + key
  openaiTts,    // paid
  elevenLabs,   // paid
}

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

extension VisualSourceInfo on VisualSource {
  String get displayName => switch (this) {
        VisualSource.dalle3 => 'DALL-E 3',
        VisualSource.stabilityAi => 'Stability AI',
        VisualSource.flux => 'fal.ai Flux',
        VisualSource.pexels => 'Pexels',
        VisualSource.pixabay => 'Pixabay',
        VisualSource.coverr => 'Coverr',
      };

  /// True when this source generates images via AI.
  /// False when it searches an existing stock library.
  bool get isAI => switch (this) {
        VisualSource.dalle3 ||
        VisualSource.stabilityAi ||
        VisualSource.flux =>
          true,
        _ => false,
      };

  bool get isStock => !isAI;

  /// True if the source primarily returns video clips.
  /// (Pexels/Pixabay support both — we default to video for stock.)
  bool get producesVideo => switch (this) {
        VisualSource.pexels ||
        VisualSource.pixabay ||
        VisualSource.coverr =>
          true,
        _ => false,
      };

  String get defaultModel => switch (this) {
        VisualSource.dalle3 => 'dall-e-3',
        VisualSource.stabilityAi => 'sd3-medium',
        VisualSource.flux => 'fal-ai/flux/schnell',
        _ => '',
      };

  String get keyHint => switch (this) {
        VisualSource.dalle3 => 'sk-…  platform.openai.com',
        VisualSource.stabilityAi => 'sk-…  platform.stability.ai',
        VisualSource.flux => 'your-key  fal.ai/dashboard',
        VisualSource.pexels => 'get free key at pexels.com/api',
        VisualSource.pixabay => 'get free key at pixabay.com/api/docs',
        VisualSource.coverr => 'get free key at coverr.co/api',
      };

  String get category => isAI ? 'AI Image' : 'Stock';
}

extension TtsProviderInfo on TtsProvider {
  String get displayName => switch (this) {
        TtsProvider.edgeTts => 'Edge TTS (free)',
        TtsProvider.deviceTts => 'On-Device (free)',
        TtsProvider.azureTts => 'Azure TTS',
        TtsProvider.openaiTts => 'OpenAI TTS',
        TtsProvider.elevenLabs => 'ElevenLabs',
      };

  bool get requiresKey => switch (this) {
        TtsProvider.edgeTts || TtsProvider.deviceTts => false,
        _ => true,
      };

  String get keyHint => switch (this) {
        TtsProvider.azureTts => 'Azure Speech key  portal.azure.com',
        TtsProvider.openaiTts => 'sk-…  platform.openai.com',
        TtsProvider.elevenLabs => 'xi-…  elevenlabs.io',
        _ => '',
      };
}

class AppConfig {
  // ── LLM ──────────────────────────────────────────────────────────────────
  final LlmProvider llmProvider;
  final String llmApiKey;
  final String llmModel;

  // ── Visual (AI OR stock) ─────────────────────────────────────────────────
  final VisualSource visualSource;
  final String visualApiKey;
  final String visualModel; // only used by AI sources

  // ── TTS ───────────────────────────────────────────────────────────────────
  final TtsProvider ttsProvider;
  final String ttsApiKey;
  final String ttsVoiceId;      // ElevenLabs voice id, Edge voice name
  final String ttsVoice;        // OpenAI voice name
  final String azureRegion;     // Azure Speech region (e.g. "eastus")

  // ── Video ─────────────────────────────────────────────────────────────────
  final bool subtitlesEnabled;
  final int sceneCount;
  final bool kenBurnsEnabled;

  const AppConfig({
    this.llmProvider = LlmProvider.openrouter,
    this.llmApiKey = '',
    this.llmModel = 'openai/gpt-4o-mini',
    this.visualSource = VisualSource.pexels,
    this.visualApiKey = '',
    this.visualModel = '',
    this.ttsProvider = TtsProvider.edgeTts,
    this.ttsApiKey = '',
    this.ttsVoiceId = 'en-US-AriaNeural',
    this.ttsVoice = 'nova',
    this.azureRegion = 'eastus',
    this.subtitlesEnabled = true,
    this.sceneCount = 5,
    this.kenBurnsEnabled = true,
  });

  String get llmBaseUrl => llmProvider.baseUrl;

  AppConfig copyWith({
    LlmProvider? llmProvider,
    String? llmApiKey,
    String? llmModel,
    VisualSource? visualSource,
    String? visualApiKey,
    String? visualModel,
    TtsProvider? ttsProvider,
    String? ttsApiKey,
    String? ttsVoiceId,
    String? ttsVoice,
    String? azureRegion,
    bool? subtitlesEnabled,
    int? sceneCount,
    bool? kenBurnsEnabled,
  }) {
    return AppConfig(
      llmProvider: llmProvider ?? this.llmProvider,
      llmApiKey: llmApiKey ?? this.llmApiKey,
      llmModel: llmModel ?? this.llmModel,
      visualSource: visualSource ?? this.visualSource,
      visualApiKey: visualApiKey ?? this.visualApiKey,
      visualModel: visualModel ?? this.visualModel,
      ttsProvider: ttsProvider ?? this.ttsProvider,
      ttsApiKey: ttsApiKey ?? this.ttsApiKey,
      ttsVoiceId: ttsVoiceId ?? this.ttsVoiceId,
      ttsVoice: ttsVoice ?? this.ttsVoice,
      azureRegion: azureRegion ?? this.azureRegion,
      subtitlesEnabled: subtitlesEnabled ?? this.subtitlesEnabled,
      sceneCount: sceneCount ?? this.sceneCount,
      kenBurnsEnabled: kenBurnsEnabled ?? this.kenBurnsEnabled,
    );
  }

  Map<String, dynamic> toJson() => {
        'llmProvider': llmProvider.name,
        'llmApiKey': llmApiKey,
        'llmModel': llmModel,
        'visualSource': visualSource.name,
        'visualApiKey': visualApiKey,
        'visualModel': visualModel,
        'ttsProvider': ttsProvider.name,
        'ttsApiKey': ttsApiKey,
        'ttsVoiceId': ttsVoiceId,
        'ttsVoice': ttsVoice,
        'azureRegion': azureRegion,
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
        visualSource: VisualSource.values.firstWhere(
          (e) => e.name == j['visualSource'],
          orElse: () => VisualSource.pexels,
        ),
        visualApiKey: j['visualApiKey'] as String? ?? '',
        visualModel: j['visualModel'] as String? ?? '',
        ttsProvider: TtsProvider.values.firstWhere(
          (e) => e.name == j['ttsProvider'],
          orElse: () => TtsProvider.edgeTts,
        ),
        ttsApiKey: j['ttsApiKey'] as String? ?? '',
        ttsVoiceId: j['ttsVoiceId'] as String? ?? 'en-US-AriaNeural',
        ttsVoice: j['ttsVoice'] as String? ?? 'nova',
        azureRegion: j['azureRegion'] as String? ?? 'eastus',
        subtitlesEnabled: j['subtitlesEnabled'] as bool? ?? true,
        sceneCount: j['sceneCount'] as int? ?? 5,
        kenBurnsEnabled: j['kenBurnsEnabled'] as bool? ?? true,
      );
}
