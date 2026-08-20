import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import '../providers/app_provider.dart';
import '../models/video_task.dart';
import 'generate_screen.dart';
import 'preview_screen.dart';
import 'settings_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _ctrl = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _requestPermissions() async {
    await [Permission.storage, Permission.manageExternalStorage].request();
  }

  Future<void> _generate() async {
    final topic = _ctrl.text.trim();
    if (topic.isEmpty) return;

    setState(() => _busy = true);
    await _requestPermissions();

    if (!mounted) return;
    final provider = context.read<AppProvider>();

    if (provider.config.llmApiKey.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Set your LLM API key in Settings first.'),
      ));
      setState(() => _busy = false);
      return;
    }

    provider.generate(topic);

    if (!mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const GenerateScreen()),
    );
    setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('CloudAI Creator'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: 'Settings',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const SettingsScreen()),
            ),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 16),
            Text('AI Video Creator',
                style: Theme.of(context)
                    .textTheme
                    .headlineSmall
                    ?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text(
              'Script + images + voice from cloud AI.\nRendered on your device.',
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: 28),
            _PipelineCard(),
            const SizedBox(height: 28),
            TextField(
              controller: _ctrl,
              maxLines: 3,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _generate(),
              decoration: const InputDecoration(
                labelText: 'Video topic',
                hintText: 'e.g. "The rise of electric vehicles"',
                border: OutlineInputBorder(),
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _busy ? null : _generate,
              icon: _busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.auto_awesome),
              label: const Text('Generate Video'),
            ),
            const Spacer(),
            _RecentVideoTile(),
          ],
        ),
      ),
    );
  }
}

class _PipelineCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    const steps = [
      (Icons.text_fields, 'LLM\nScript'),
      (Icons.image_outlined, 'Cloud\nImages'),
      (Icons.record_voice_over_outlined, 'Cloud\nTTS'),
      (Icons.movie_creation_outlined, 'FFmpeg\nRender'),
    ];

    return Card.outlined(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            for (var i = 0; i < steps.length; i++) ...[
              Column(mainAxisSize: MainAxisSize.min, children: [
                Icon(steps[i].$1,
                    color: Theme.of(context).colorScheme.primary, size: 22),
                const SizedBox(height: 4),
                Text(steps[i].$2,
                    style: Theme.of(context).textTheme.labelSmall,
                    textAlign: TextAlign.center),
              ]),
              if (i < steps.length - 1)
                Icon(Icons.arrow_forward_ios,
                    size: 10,
                    color: Theme.of(context).colorScheme.outlineVariant),
            ],
          ],
        ),
      ),
    );
  }
}

class _RecentVideoTile extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final task = context.watch<AppProvider>().currentTask;
    if (task == null || task.step != TaskStep.done || task.outputPath == null) {
      return const SizedBox.shrink();
    }
    return ListTile(
      leading: const Icon(Icons.check_circle_outline, color: Colors.green),
      title: Text(task.topic, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: const Text('Last video — tap to preview'),
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => PreviewScreen(videoPath: task.outputPath!),
        ),
      ),
    );
  }
}
