class AppConfig {
  final String llmBaseUrl;
  final String llmApiKey;
  final String llmModel;
  final String pexelsApiKey;
  final String ttsLanguage;
  final double ttsSpeechRate;
  final bool subtitlesEnabled;
  final int videoDurationSec;

  const AppConfig({
    this.llmBaseUrl = 'https://openrouter.ai/api/v1',
    this.llmApiKey = '',
    this.llmModel = 'openai/gpt-4o-mini',
    this.pexelsApiKey = '',
    this.ttsLanguage = 'en-US',
    this.ttsSpeechRate = 0.9,
    this.subtitlesEnabled = true,
    this.videoDurationSec = 30,
  });

  AppConfig copyWith({
    String? llmBaseUrl,
    String? llmApiKey,
    String? llmModel,
    String? pexelsApiKey,
    String? ttsLanguage,
    double? ttsSpeechRate,
    bool? subtitlesEnabled,
    int? videoDurationSec,
  }) {
    return AppConfig(
      llmBaseUrl: llmBaseUrl ?? this.llmBaseUrl,
      llmApiKey: llmApiKey ?? this.llmApiKey,
      llmModel: llmModel ?? this.llmModel,
      pexelsApiKey: pexelsApiKey ?? this.pexelsApiKey,
      ttsLanguage: ttsLanguage ?? this.ttsLanguage,
      ttsSpeechRate: ttsSpeechRate ?? this.ttsSpeechRate,
      subtitlesEnabled: subtitlesEnabled ?? this.subtitlesEnabled,
      videoDurationSec: videoDurationSec ?? this.videoDurationSec,
    );
  }

  Map<String, dynamic> toJson() => {
        'llmBaseUrl': llmBaseUrl,
        'llmApiKey': llmApiKey,
        'llmModel': llmModel,
        'pexelsApiKey': pexelsApiKey,
        'ttsLanguage': ttsLanguage,
        'ttsSpeechRate': ttsSpeechRate,
        'subtitlesEnabled': subtitlesEnabled,
        'videoDurationSec': videoDurationSec,
      };

  factory AppConfig.fromJson(Map<String, dynamic> j) => AppConfig(
        llmBaseUrl: j['llmBaseUrl'] as String? ?? 'https://openrouter.ai/api/v1',
        llmApiKey: j['llmApiKey'] as String? ?? '',
        llmModel: j['llmModel'] as String? ?? 'openai/gpt-4o-mini',
        pexelsApiKey: j['pexelsApiKey'] as String? ?? '',
        ttsLanguage: j['ttsLanguage'] as String? ?? 'en-US',
        ttsSpeechRate: (j['ttsSpeechRate'] as num?)?.toDouble() ?? 0.9,
        subtitlesEnabled: j['subtitlesEnabled'] as bool? ?? true,
        videoDurationSec: j['videoDurationSec'] as int? ?? 30,
      );
}
