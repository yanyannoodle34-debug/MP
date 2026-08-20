import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/app_config.dart';
import '../providers/app_provider.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late AppConfig _cfg;
  bool _dirty = false;

  late final TextEditingController _llmKey;
  late final TextEditingController _llmModel;
  late final TextEditingController _imageKey;
  late final TextEditingController _imageModel;
  late final TextEditingController _ttsKey;
  late final TextEditingController _ttsVoiceId;
  late final TextEditingController _ttsVoice;

  @override
  void initState() {
    super.initState();
    _cfg = context.read<AppProvider>().config;
    _llmKey = TextEditingController(text: _cfg.llmApiKey);
    _llmModel = TextEditingController(text: _cfg.llmModel);
    _imageKey = TextEditingController(text: _cfg.imageApiKey);
    _imageModel = TextEditingController(text: _cfg.imageModel);
    _ttsKey = TextEditingController(text: _cfg.ttsApiKey);
    _ttsVoiceId = TextEditingController(text: _cfg.ttsVoiceId);
    _ttsVoice = TextEditingController(text: _cfg.ttsVoice);
  }

  @override
  void dispose() {
    for (final c in [_llmKey, _llmModel, _imageKey, _imageModel, _ttsKey, _ttsVoiceId, _ttsVoice]) {
      c.dispose();
    }
    super.dispose();
  }

  void _mark() => setState(() => _dirty = true);

  Future<void> _save() async {
    final updated = _cfg.copyWith(
      llmApiKey: _llmKey.text.trim(),
      llmModel: _llmModel.text.trim(),
      imageApiKey: _imageKey.text.trim(),
      imageModel: _imageModel.text.trim(),
      ttsApiKey: _ttsKey.text.trim(),
      ttsVoiceId: _ttsVoiceId.text.trim(),
      ttsVoice: _ttsVoice.text.trim(),
    );
    await context.read<AppProvider>().saveConfig(updated);
    setState(() => _dirty = false);
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Settings saved')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        actions: [
          if (_dirty)
            TextButton(
              onPressed: _save,
              child: Text('Save', style: TextStyle(color: cs.primary)),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ── LLM ─────────────────────────────────────────────────────────
          _section('Script Generation (LLM)'),
          _chips<LlmProvider>(
            label: 'Provider',
            value: _cfg.llmProvider,
            options: LlmProvider.values,
            nameOf: (v) => v == LlmProvider.openrouter ? 'OpenRouter' : 'OpenAI',
            onChanged: (v) => setState(() {
              _cfg = _cfg.copyWith(
                llmProvider: v,
                llmModel: v == LlmProvider.openrouter ? 'openai/gpt-4o-mini' : 'gpt-4o-mini',
              );
              _llmModel.text = _cfg.llmModel;
              _dirty = true;
            }),
          ),
          _key('API Key', _llmKey,
              hint: _cfg.llmProvider == LlmProvider.openrouter
                  ? 'sk-or-…  openrouter.ai/keys'
                  : 'sk-…  platform.openai.com'),
          _text('Model', _llmModel, hint: _cfg.llmModel),
          _stepper('Scenes', _cfg.sceneCount, 3, 8, (v) =>
              setState(() { _cfg = _cfg.copyWith(sceneCount: v); _dirty = true; })),
          const SizedBox(height: 24),

          // ── Image ────────────────────────────────────────────────────────
          _section('Image Generation'),
          _chips<ImageGenProvider>(
            label: 'Provider',
            value: _cfg.imageProvider,
            options: ImageGenProvider.values,
            nameOf: (v) => switch (v) {
              ImageGenProvider.dalle3 => 'DALL-E 3',
              ImageGenProvider.stabilityAi => 'Stability AI',
              ImageGenProvider.flux => 'fal.ai Flux',
            },
            onChanged: (v) => setState(() {
              _cfg = _cfg.copyWith(
                imageProvider: v,
                imageModel: switch (v) {
                  ImageGenProvider.dalle3 => 'dall-e-3',
                  ImageGenProvider.stabilityAi => 'sd3-medium',
                  ImageGenProvider.flux => 'fal-ai/flux/schnell',
                },
              );
              _imageModel.text = _cfg.imageModel;
              _dirty = true;
            }),
          ),
          _key('API Key', _imageKey,
              hint: switch (_cfg.imageProvider) {
                ImageGenProvider.dalle3 => 'sk-…  platform.openai.com',
                ImageGenProvider.stabilityAi => 'sk-…  platform.stability.ai',
                ImageGenProvider.flux => 'your-key  fal.ai/dashboard',
              }),
          _text('Model', _imageModel, hint: _cfg.imageModel),
          const SizedBox(height: 24),

          // ── TTS ──────────────────────────────────────────────────────────
          _section('Voice (TTS)'),
          _chips<TtsProvider>(
            label: 'Provider',
            value: _cfg.ttsProvider,
            options: TtsProvider.values,
            nameOf: (v) => switch (v) {
              TtsProvider.elevenLabs => 'ElevenLabs',
              TtsProvider.openaiTts => 'OpenAI TTS',
            },
            onChanged: (v) =>
                setState(() { _cfg = _cfg.copyWith(ttsProvider: v); _dirty = true; }),
          ),
          _key('API Key', _ttsKey,
              hint: _cfg.ttsProvider == TtsProvider.elevenLabs
                  ? 'xi-…  elevenlabs.io'
                  : 'sk-…  platform.openai.com'),
          if (_cfg.ttsProvider == TtsProvider.elevenLabs)
            _text('Voice ID', _ttsVoiceId, hint: 'EXAVITQu4vr4xnSDxMaL'),
          if (_cfg.ttsProvider == TtsProvider.openaiTts)
            _text('Voice', _ttsVoice,
                hint: 'nova | alloy | echo | fable | onyx | shimmer'),
          const SizedBox(height: 24),

          // ── Video ────────────────────────────────────────────────────────
          _section('Video'),
          SwitchListTile(
            title: const Text('Subtitles'),
            subtitle: const Text('Burn captions into video'),
            value: _cfg.subtitlesEnabled,
            onChanged: (v) =>
                setState(() { _cfg = _cfg.copyWith(subtitlesEnabled: v); _dirty = true; }),
          ),
          SwitchListTile(
            title: const Text('Ken Burns effect'),
            subtitle: const Text('Slow zoom on each image'),
            value: _cfg.kenBurnsEnabled,
            onChanged: (v) =>
                setState(() { _cfg = _cfg.copyWith(kenBurnsEnabled: v); _dirty = true; }),
          ),
          const SizedBox(height: 32),
          FilledButton(onPressed: _dirty ? _save : null, child: const Text('Save')),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _section(String t) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Text(t,
            style: Theme.of(context)
                .textTheme
                .titleSmall
                ?.copyWith(color: Theme.of(context).colorScheme.primary)),
      );

  Widget _key(String label, TextEditingController c, {String hint = ''}) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: TextField(
          controller: c,
          obscureText: true,
          onChanged: (_) => _mark(),
          decoration: InputDecoration(
              labelText: label, hintText: hint, border: const OutlineInputBorder()),
        ),
      );

  Widget _text(String label, TextEditingController c, {String hint = ''}) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: TextField(
          controller: c,
          onChanged: (_) => _mark(),
          decoration: InputDecoration(
              labelText: label, hintText: hint, border: const OutlineInputBorder()),
        ),
      );

  Widget _stepper(String label, int value, int min, int max, ValueChanged<int> cb) =>
      ListTile(
        title: Text(label),
        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
          IconButton(
              icon: const Icon(Icons.remove),
              onPressed: value > min ? () => cb(value - 1) : null),
          Text('$value', style: Theme.of(context).textTheme.titleMedium),
          IconButton(
              icon: const Icon(Icons.add),
              onPressed: value < max ? () => cb(value + 1) : null),
        ]),
      );

  Widget _chips<T>({
    required String label,
    required T value,
    required List<T> options,
    required String Function(T) nameOf,
    required ValueChanged<T> onChanged,
  }) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: Theme.of(context).textTheme.labelMedium),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            children: options
                .map((o) => ChoiceChip(
                    label: Text(nameOf(o)),
                    selected: o == value,
                    onSelected: (_) => onChanged(o)))
                .toList(),
          ),
        ]),
      );
}
