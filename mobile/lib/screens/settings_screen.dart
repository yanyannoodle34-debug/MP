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
  late final _llmUrlCtrl = TextEditingController();
  late final _llmKeyCtrl = TextEditingController();
  late final _llmModelCtrl = TextEditingController();
  late final _pexelsKeyCtrl = TextEditingController();
  late final _ttsLangCtrl = TextEditingController();
  late double _speechRate;
  late bool _subtitles;
  late int _duration;

  @override
  void initState() {
    super.initState();
    final cfg = context.read<AppProvider>().config;
    _llmUrlCtrl.text = cfg.llmBaseUrl;
    _llmKeyCtrl.text = cfg.llmApiKey;
    _llmModelCtrl.text = cfg.llmModel;
    _pexelsKeyCtrl.text = cfg.pexelsApiKey;
    _ttsLangCtrl.text = cfg.ttsLanguage;
    _speechRate = cfg.ttsSpeechRate;
    _subtitles = cfg.subtitlesEnabled;
    _duration = cfg.videoDurationSec;
  }

  @override
  void dispose() {
    for (final c in [
      _llmUrlCtrl, _llmKeyCtrl, _llmModelCtrl, _pexelsKeyCtrl, _ttsLangCtrl
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    final cfg = AppConfig(
      llmBaseUrl: _llmUrlCtrl.text.trim(),
      llmApiKey: _llmKeyCtrl.text.trim(),
      llmModel: _llmModelCtrl.text.trim(),
      pexelsApiKey: _pexelsKeyCtrl.text.trim(),
      ttsLanguage: _ttsLangCtrl.text.trim(),
      ttsSpeechRate: _speechRate,
      subtitlesEnabled: _subtitles,
      videoDurationSec: _duration,
    );
    await context.read<AppProvider>().saveConfig(cfg);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Settings saved.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _section('LLM (Script Generation)', [
            _field('API Base URL', _llmUrlCtrl,
                hint: 'https://openrouter.ai/api/v1'),
            _field('API Key', _llmKeyCtrl, obscure: true, hint: 'sk-or-…'),
            _field('Model', _llmModelCtrl, hint: 'openai/gpt-4o-mini'),
          ]),
          const SizedBox(height: 16),
          _section('Pexels (Stock Videos)', [
            _field('Pexels API Key', _pexelsKeyCtrl,
                obscure: true, hint: 'Free key at pexels.com/api'),
          ]),
          const SizedBox(height: 16),
          _section('Text-to-Speech (on-device)', [
            _field('Language code', _ttsLangCtrl, hint: 'en-US'),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Speech rate: ${_speechRate.toStringAsFixed(2)}',
                      style: theme.textTheme.bodyMedium),
                  Slider(
                    value: _speechRate,
                    min: 0.5,
                    max: 1.5,
                    divisions: 20,
                    label: _speechRate.toStringAsFixed(2),
                    onChanged: (v) => setState(() => _speechRate = v),
                  ),
                ],
              ),
            ),
            SwitchListTile(
              title: const Text('Burn subtitles'),
              value: _subtitles,
              onChanged: (v) => setState(() => _subtitles = v),
              contentPadding: EdgeInsets.zero,
            ),
          ]),
          const SizedBox(height: 16),
          _section('Video', [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Target duration: ${_duration}s',
                      style: theme.textTheme.bodyMedium),
                  Slider(
                    value: _duration.toDouble(),
                    min: 15,
                    max: 60,
                    divisions: 9,
                    label: '${_duration}s',
                    onChanged: (v) =>
                        setState(() => _duration = v.round()),
                  ),
                ],
              ),
            ),
          ]),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: _save,
            icon: const Icon(Icons.save),
            label: const Text('Save Settings'),
          ),
          const SizedBox(height: 8),
          Text(
            'OpenRouter free tier: openai/gpt-4o-mini\n'
            'Get a Pexels key free at pexels.com/api',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.outline),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _section(String title, List<Widget> children) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                style: Theme.of(context)
                    .textTheme
                    .titleSmall
                    ?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            ...children,
          ],
        ),
      ),
    );
  }

  Widget _field(
    String label,
    TextEditingController ctrl, {
    bool obscure = false,
    String? hint,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: TextField(
        controller: ctrl,
        obscureText: obscure,
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          isDense: true,
          border: const OutlineInputBorder(),
        ),
      ),
    );
  }
}
