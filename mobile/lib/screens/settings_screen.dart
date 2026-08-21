import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../models/app_config.dart';
import '../providers/app_provider.dart';
import '../services/image_service.dart';
import '../services/llm_service.dart';
import '../services/tts_service.dart';

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

  final _llmService = LlmService();
  final _imageService = ImageService();
  final _ttsService = TtsService();

  // per-field key visibility (default: obscured)
  bool _llmKeyVisible = false;
  bool _imageKeyVisible = false;
  bool _ttsKeyVisible = false;

  // per-section test / fetch state
  _TestResult? _llmTest;
  _TestResult? _imageTest;
  _TestResult? _ttsTest;
  bool _llmTesting = false;
  bool _imageTesting = false;
  bool _ttsTesting = false;

  List<String> _availableModels = [];
  bool _fetchingModels = false;

  List<({String id, String name})> _availableVoices = [];
  bool _fetchingVoices = false;

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

  // Snapshot current form → AppConfig so services can call APIs before saving.
  AppConfig _current() => _cfg.copyWith(
        llmApiKey: _llmKey.text.trim(),
        llmModel: _llmModel.text.trim(),
        imageApiKey: _imageKey.text.trim(),
        imageModel: _imageModel.text.trim(),
        ttsApiKey: _ttsKey.text.trim(),
        ttsVoiceId: _ttsVoiceId.text.trim(),
        ttsVoice: _ttsVoice.text.trim(),
      );

  Future<void> _save() async {
    await context.read<AppProvider>().saveConfig(_current());
    setState(() {
      _cfg = _current();
      _dirty = false;
    });
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Settings saved')));
    }
  }

  // ── Test actions ──────────────────────────────────────────────────────────

  Future<void> _testLlmKey() async {
    if (_llmKey.text.trim().isEmpty) {
      setState(() => _llmTest = _TestResult.error('Enter API key first'));
      return;
    }
    setState(() { _llmTesting = true; _llmTest = null; });
    final err = await _llmService.testKey(_current());
    if (!mounted) return;
    setState(() {
      _llmTesting = false;
      _llmTest = err == null ? _TestResult.ok('Key works!') : _TestResult.error(err);
    });
  }

  Future<void> _fetchModels() async {
    if (_llmKey.text.trim().isEmpty) {
      setState(() => _llmTest = _TestResult.error('Enter API key first'));
      return;
    }
    setState(() { _fetchingModels = true; });
    try {
      final models = await _llmService.fetchModels(_current());
      if (!mounted) return;
      setState(() {
        _fetchingModels = false;
        _availableModels = models;
      });
      if (models.isEmpty) {
        setState(() => _llmTest = _TestResult.error('No models returned'));
      } else {
        setState(() => _llmTest = _TestResult.ok('${models.length} models available'));
        _showModelPicker();
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _fetchingModels = false;
        _llmTest = _TestResult.error(e.toString());
      });
    }
  }

  Future<void> _testImageKey() async {
    if (_imageKey.text.trim().isEmpty) {
      setState(() => _imageTest = _TestResult.error('Enter API key first'));
      return;
    }
    setState(() { _imageTesting = true; _imageTest = null; });
    final err = await _imageService.testKey(_current());
    if (!mounted) return;
    setState(() {
      _imageTesting = false;
      _imageTest = err == null ? _TestResult.ok('Key works!') : _TestResult.error(err);
    });
  }

  Future<void> _testTtsKey() async {
    if (_ttsKey.text.trim().isEmpty) {
      setState(() => _ttsTest = _TestResult.error('Enter API key first'));
      return;
    }
    setState(() { _ttsTesting = true; _ttsTest = null; });
    final err = await _ttsService.testKey(_current());
    if (!mounted) return;
    setState(() {
      _ttsTesting = false;
      _ttsTest = err == null ? _TestResult.ok('Key works!') : _TestResult.error(err);
    });
  }

  Future<void> _fetchVoices() async {
    if (_ttsKey.text.trim().isEmpty) {
      setState(() => _ttsTest = _TestResult.error('Enter API key first'));
      return;
    }
    setState(() { _fetchingVoices = true; });
    try {
      final voices = await _ttsService.fetchVoices(_current());
      if (!mounted) return;
      setState(() {
        _fetchingVoices = false;
        _availableVoices = voices;
      });
      if (voices.isEmpty) {
        setState(() => _ttsTest = _TestResult.error('No voices returned'));
      } else {
        _showVoicePicker();
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _fetchingVoices = false;
        _ttsTest = _TestResult.error(e.toString());
      });
    }
  }

  void _showModelPicker() {
    showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => _ModelPicker(
        models: _availableModels,
        current: _llmModel.text,
      ),
    ).then((picked) {
      if (picked != null && picked.isNotEmpty) {
        setState(() {
          _llmModel.text = picked;
          _dirty = true;
        });
      }
    });
  }

  void _showVoicePicker() {
    showModalBottomSheet<({String id, String name})>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => _VoicePicker(
        voices: _availableVoices,
        currentId: _cfg.ttsProvider == TtsProvider.elevenLabs
            ? _ttsVoiceId.text
            : _ttsVoice.text,
      ),
    ).then((picked) {
      if (picked != null) {
        setState(() {
          if (_cfg.ttsProvider == TtsProvider.elevenLabs) {
            _ttsVoiceId.text = picked.id;
          } else {
            _ttsVoice.text = picked.id;
          }
          _dirty = true;
        });
      }
    });
  }

  // ── Build ─────────────────────────────────────────────────────────────────

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
          _section('Script Generation (LLM)', Icons.text_fields),
          _chips<LlmProvider>(
            value: _cfg.llmProvider,
            options: LlmProvider.values,
            nameOf: (v) => v.displayName,
            onChanged: (v) => setState(() {
              _cfg = _cfg.copyWith(llmProvider: v, llmModel: v.defaultModel);
              _llmModel.text = v.defaultModel;
              _availableModels = [];
              _llmTest = null;
              _dirty = true;
            }),
          ),
          _key(
            'API Key',
            _llmKey,
            hint: _cfg.llmProvider.keyHint,
            visible: _llmKeyVisible,
            onToggleVisibility: () =>
                setState(() => _llmKeyVisible = !_llmKeyVisible),
          ),
          _row(
            children: [
              Expanded(
                child: TextField(
                  controller: _llmModel,
                  onChanged: (_) => _mark(),
                  decoration: const InputDecoration(
                    labelText: 'Model',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              _IconAction(
                icon: Icons.download_for_offline_outlined,
                tooltip: 'Fetch available models',
                loading: _fetchingModels,
                onPressed: _fetchModels,
              ),
            ],
          ),
          _testRow(
            testing: _llmTesting,
            result: _llmTest,
            onTest: _testLlmKey,
          ),
          _stepper('Scenes', _cfg.sceneCount, 3, 8, (v) =>
              setState(() { _cfg = _cfg.copyWith(sceneCount: v); _dirty = true; })),
          const SizedBox(height: 24),

          // ── Image ────────────────────────────────────────────────────────
          _section('Image Generation', Icons.image_outlined),
          _chips<ImageGenProvider>(
            value: _cfg.imageProvider,
            options: ImageGenProvider.values,
            nameOf: (v) => switch (v) {
              ImageGenProvider.dalle3 => 'DALL-E 3',
              ImageGenProvider.stabilityAi => 'Stability AI',
              ImageGenProvider.flux => 'fal.ai Flux',
            },
            onChanged: (v) => setState(() {
              final defaultModel = switch (v) {
                ImageGenProvider.dalle3 => 'dall-e-3',
                ImageGenProvider.stabilityAi => 'sd3-medium',
                ImageGenProvider.flux => 'fal-ai/flux/schnell',
              };
              _cfg = _cfg.copyWith(imageProvider: v, imageModel: defaultModel);
              _imageModel.text = defaultModel;
              _imageTest = null;
              _dirty = true;
            }),
          ),
          _key(
            'API Key',
            _imageKey,
            hint: _imageKeyHint(),
            visible: _imageKeyVisible,
            onToggleVisibility: () =>
                setState(() => _imageKeyVisible = !_imageKeyVisible),
          ),
          _text('Model', _imageModel, hint: _cfg.imageModel),
          _testRow(
            testing: _imageTesting,
            result: _imageTest,
            onTest: _testImageKey,
          ),
          const SizedBox(height: 24),

          // ── TTS ──────────────────────────────────────────────────────────
          _section('Voice (TTS)', Icons.record_voice_over_outlined),
          _chips<TtsProvider>(
            value: _cfg.ttsProvider,
            options: TtsProvider.values,
            nameOf: (v) => switch (v) {
              TtsProvider.elevenLabs => 'ElevenLabs',
              TtsProvider.openaiTts => 'OpenAI TTS',
            },
            onChanged: (v) => setState(() {
              _cfg = _cfg.copyWith(ttsProvider: v);
              _availableVoices = [];
              _ttsTest = null;
              _dirty = true;
            }),
          ),
          _key(
            'API Key',
            _ttsKey,
            hint: _cfg.ttsProvider == TtsProvider.elevenLabs
                ? 'xi-…  elevenlabs.io'
                : 'sk-…  platform.openai.com',
            visible: _ttsKeyVisible,
            onToggleVisibility: () =>
                setState(() => _ttsKeyVisible = !_ttsKeyVisible),
          ),
          _row(
            children: [
              Expanded(
                child: TextField(
                  controller: _cfg.ttsProvider == TtsProvider.elevenLabs
                      ? _ttsVoiceId
                      : _ttsVoice,
                  onChanged: (_) => _mark(),
                  decoration: InputDecoration(
                    labelText: _cfg.ttsProvider == TtsProvider.elevenLabs
                        ? 'Voice ID'
                        : 'Voice',
                    hintText: _cfg.ttsProvider == TtsProvider.elevenLabs
                        ? 'EXAVITQu4vr4xnSDxMaL'
                        : 'nova | alloy | echo | fable | onyx | shimmer',
                    border: const OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              _IconAction(
                icon: Icons.download_for_offline_outlined,
                tooltip: 'Browse voices',
                loading: _fetchingVoices,
                onPressed: _fetchVoices,
              ),
            ],
          ),
          _testRow(
            testing: _ttsTesting,
            result: _ttsTest,
            onTest: _testTtsKey,
          ),
          const SizedBox(height: 24),

          // ── Video ────────────────────────────────────────────────────────
          _section('Video', Icons.movie_creation_outlined),
          SwitchListTile(
            title: const Text('Subtitles'),
            subtitle: const Text('Burn captions into video'),
            value: _cfg.subtitlesEnabled,
            onChanged: (v) =>
                setState(() { _cfg = _cfg.copyWith(subtitlesEnabled: v); _dirty = true; }),
            contentPadding: EdgeInsets.zero,
          ),
          SwitchListTile(
            title: const Text('Ken Burns effect'),
            subtitle: const Text('Slow zoom on each image'),
            value: _cfg.kenBurnsEnabled,
            onChanged: (v) =>
                setState(() { _cfg = _cfg.copyWith(kenBurnsEnabled: v); _dirty = true; }),
            contentPadding: EdgeInsets.zero,
          ),
          const SizedBox(height: 32),
          FilledButton.icon(
            onPressed: _dirty ? _save : null,
            icon: const Icon(Icons.save_outlined),
            label: const Text('Save settings'),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  String _imageKeyHint() => switch (_cfg.imageProvider) {
        ImageGenProvider.dalle3 => 'sk-…  platform.openai.com',
        ImageGenProvider.stabilityAi => 'sk-…  platform.stability.ai',
        ImageGenProvider.flux => 'your-key  fal.ai/dashboard',
      };

  // ── Widget helpers ────────────────────────────────────────────────────────

  Widget _section(String title, IconData icon) => Padding(
        padding: const EdgeInsets.only(bottom: 10, top: 4),
        child: Row(children: [
          Icon(icon, size: 18, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 8),
          Text(title,
              style: Theme.of(context)
                  .textTheme
                  .titleSmall
                  ?.copyWith(color: Theme.of(context).colorScheme.primary)),
        ]),
      );

  Widget _row({required List<Widget> children}) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(children: children),
      );

  Widget _key(
    String label,
    TextEditingController c, {
    required bool visible,
    required VoidCallback onToggleVisibility,
    String hint = '',
  }) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: TextField(
          controller: c,
          obscureText: !visible,
          onChanged: (_) => _mark(),
          autocorrect: false,
          enableSuggestions: false,
          decoration: InputDecoration(
            labelText: label,
            hintText: hint,
            border: const OutlineInputBorder(),
            isDense: true,
            suffixIcon: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(Icons.content_paste, size: 18),
                  tooltip: 'Paste',
                  onPressed: () async {
                    final data = await Clipboard.getData(Clipboard.kTextPlain);
                    final text = data?.text?.trim();
                    if (text != null && text.isNotEmpty) {
                      c.text = text;
                      _mark();
                    }
                  },
                  visualDensity: VisualDensity.compact,
                ),
                IconButton(
                  icon: Icon(
                      visible ? Icons.visibility_off : Icons.visibility,
                      size: 18),
                  tooltip: visible ? 'Hide' : 'Show',
                  onPressed: onToggleVisibility,
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
          ),
        ),
      );

  Widget _text(String label, TextEditingController c, {String hint = ''}) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: TextField(
          controller: c,
          onChanged: (_) => _mark(),
          decoration: InputDecoration(
              labelText: label,
              hintText: hint,
              border: const OutlineInputBorder(),
              isDense: true),
        ),
      );

  Widget _stepper(String label, int value, int min, int max, ValueChanged<int> cb) =>
      Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Row(children: [
          Text(label, style: Theme.of(context).textTheme.bodyMedium),
          const Spacer(),
          IconButton.outlined(
              icon: const Icon(Icons.remove, size: 18),
              onPressed: value > min ? () => cb(value - 1) : null,
              visualDensity: VisualDensity.compact),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text('$value', style: Theme.of(context).textTheme.titleMedium),
          ),
          IconButton.outlined(
              icon: const Icon(Icons.add, size: 18),
              onPressed: value < max ? () => cb(value + 1) : null,
              visualDensity: VisualDensity.compact),
        ]),
      );

  Widget _chips<T>({
    required T value,
    required List<T> options,
    required String Function(T) nameOf,
    required ValueChanged<T> onChanged,
  }) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Wrap(
          spacing: 8,
          runSpacing: 4,
          children: options
              .map((o) => ChoiceChip(
                    label: Text(nameOf(o)),
                    selected: o == value,
                    onSelected: (_) => onChanged(o),
                  ))
              .toList(),
        ),
      );

  Widget _testRow({
    required bool testing,
    required _TestResult? result,
    required VoidCallback onTest,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, top: 4),
      child: Row(
        children: [
          OutlinedButton.icon(
            onPressed: testing ? null : onTest,
            icon: testing
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.check_circle_outline, size: 18),
            label: const Text('Test API key'),
            style: OutlinedButton.styleFrom(
              visualDensity: VisualDensity.compact,
            ),
          ),
          const SizedBox(width: 12),
          if (result != null)
            Flexible(
              child: Text(
                result.message,
                style: TextStyle(
                  fontSize: 12,
                  color: result.ok ? Colors.green : Colors.red,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
        ],
      ),
    );
  }
}

class _TestResult {
  final bool ok;
  final String message;
  const _TestResult._(this.ok, this.message);
  factory _TestResult.ok(String m) => _TestResult._(true, m);
  factory _TestResult.error(String m) => _TestResult._(false, m);
}

class _IconAction extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final bool loading;
  final VoidCallback onPressed;

  const _IconAction({
    required this.icon,
    required this.tooltip,
    required this.loading,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return IconButton.outlined(
      onPressed: loading ? null : onPressed,
      tooltip: tooltip,
      icon: loading
          ? const SizedBox(
              width: 18, height: 18,
              child: CircularProgressIndicator(strokeWidth: 2))
          : Icon(icon),
    );
  }
}

class _ModelPicker extends StatefulWidget {
  final List<String> models;
  final String current;

  const _ModelPicker({required this.models, required this.current});

  @override
  State<_ModelPicker> createState() => _ModelPickerState();
}

class _ModelPickerState extends State<_ModelPicker> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final filtered = _query.isEmpty
        ? widget.models
        : widget.models
            .where((m) => m.toLowerCase().contains(_query.toLowerCase()))
            .toList();

    return SafeArea(
      child: DraggableScrollableSheet(
        initialChildSize: 0.7,
        maxChildSize: 0.95,
        minChildSize: 0.4,
        expand: false,
        builder: (_, scroll) => Column(
          children: [
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.symmetric(vertical: 8),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.outlineVariant,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Icon(Icons.list_alt, color: Theme.of(context).colorScheme.primary),
                  const SizedBox(width: 8),
                  Text('Choose model',
                      style: Theme.of(context).textTheme.titleMedium),
                  const Spacer(),
                  Text('${widget.models.length}',
                      style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurfaceVariant)),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(
                onChanged: (v) => setState(() => _query = v),
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  hintText: 'Filter models…',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: ListView.builder(
                controller: scroll,
                itemCount: filtered.length,
                itemBuilder: (_, i) {
                  final m = filtered[i];
                  return ListTile(
                    dense: true,
                    title: Text(m,
                        style: const TextStyle(fontFamily: 'monospace', fontSize: 13)),
                    trailing: m == widget.current
                        ? Icon(Icons.check,
                            color: Theme.of(context).colorScheme.primary)
                        : null,
                    onTap: () => Navigator.pop(context, m),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _VoicePicker extends StatelessWidget {
  final List<({String id, String name})> voices;
  final String currentId;

  const _VoicePicker({required this.voices, required this.currentId});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: DraggableScrollableSheet(
        initialChildSize: 0.6,
        maxChildSize: 0.9,
        expand: false,
        builder: (_, scroll) => Column(
          children: [
            Container(
              width: 40, height: 4,
              margin: const EdgeInsets.symmetric(vertical: 8),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.outlineVariant,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Icon(Icons.record_voice_over,
                      color: Theme.of(context).colorScheme.primary),
                  const SizedBox(width: 8),
                  Text('Choose voice',
                      style: Theme.of(context).textTheme.titleMedium),
                ],
              ),
            ),
            Expanded(
              child: ListView.builder(
                controller: scroll,
                itemCount: voices.length,
                itemBuilder: (_, i) {
                  final v = voices[i];
                  return ListTile(
                    title: Text(v.name),
                    subtitle: Text(v.id,
                        style: const TextStyle(
                            fontFamily: 'monospace', fontSize: 11)),
                    trailing: v.id == currentId
                        ? Icon(Icons.check,
                            color: Theme.of(context).colorScheme.primary)
                        : null,
                    onTap: () => Navigator.pop(context, v),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
