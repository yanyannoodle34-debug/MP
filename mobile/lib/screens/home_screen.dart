import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import '../providers/app_provider.dart';
import 'generate_screen.dart';
import 'settings_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _topicCtrl = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _topicCtrl.dispose();
    super.dispose();
  }

  Future<void> _generate() async {
    final topic = _topicCtrl.text.trim();
    if (topic.isEmpty) return;

    // Request storage permission (Android 9 and below need WRITE_EXTERNAL_STORAGE)
    await [Permission.storage, Permission.manageExternalStorage]
        .request();

    setState(() => _busy = true);

    final provider = context.read<AppProvider>();
    provider.generate(topic);

    if (mounted) {
      await Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const GenerateScreen()),
      );
      provider.reset();
    }

    setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Scaffold(
      backgroundColor: scheme.surface,
      appBar: AppBar(
        title: const Text('MoneyPrinter Mobile'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const SettingsScreen()),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Hero illustration
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.movie_creation,
                      size: 80,
                      color: scheme.primary,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'AI Short Video Generator',
                      style: theme.textTheme.headlineSmall
                          ?.copyWith(fontWeight: FontWeight.bold),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Runs entirely on-device.\n'
                      'Enter a topic → get a ready-to-post short video.',
                      style: theme.textTheme.bodyMedium
                          ?.copyWith(color: scheme.onSurfaceVariant),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),

              // Input card
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      TextField(
                        controller: _topicCtrl,
                        maxLines: 3,
                        textInputAction: TextInputAction.done,
                        decoration: InputDecoration(
                          hintText:
                              'Enter a topic…\ne.g. "Why coffee makes you productive"',
                          border: const OutlineInputBorder(),
                          prefixIcon: const Icon(Icons.lightbulb_outline),
                          filled: true,
                          fillColor: scheme.surfaceContainerLowest,
                        ),
                        onSubmitted: (_) => _generate(),
                      ),
                      const SizedBox(height: 12),
                      FilledButton.icon(
                        onPressed: _busy ? null : _generate,
                        icon: _busy
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.auto_awesome),
                        label: Text(_busy ? 'Generating…' : 'Generate Video'),
                        style: FilledButton.styleFrom(
                          minimumSize: const Size.fromHeight(48),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 16),
              _ChipRow(),
            ],
          ),
        ),
      ),
    );
  }
}

/// Quick-fill suggestion chips
class _ChipRow extends StatelessWidget {
  static const _suggestions = [
    'Morning productivity tips',
    'Space exploration facts',
    'Street food around the world',
    'How to learn faster',
    'Hidden gems of Tokyo',
  ];

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 4,
      alignment: WrapAlignment.center,
      children: _suggestions
          .map((s) => ActionChip(
                label: Text(s, style: const TextStyle(fontSize: 12)),
                onPressed: () {
                  final state = context.findAncestorStateOfType<
                      _HomeScreenState>();
                  state?._topicCtrl.text = s;
                },
              ))
          .toList(),
    );
  }
}
