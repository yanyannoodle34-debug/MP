import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import '../providers/app_provider.dart';
import '../models/app_config.dart';
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
      body: RefreshIndicator(
        onRefresh: () => context.read<AppProvider>().refreshDrafts(),
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
          children: [
            Text('AI Video Creator',
                style: Theme.of(context)
                    .textTheme
                    .headlineSmall
                    ?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text(
              'Script + visuals + voice from cloud AI.\nRendered on your device.',
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: 20),
            _PipelineCard(),
            const SizedBox(height: 12),
            _StatusBar(),
            const SizedBox(height: 20),
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
            const SizedBox(height: 28),
            _DraftsSection(),
          ],
        ),
      ),
    );
  }
}

class _DraftsSection extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final drafts = context.watch<AppProvider>().drafts;
    final cs = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Icon(Icons.movie_filter_outlined,
                size: 18, color: cs.primary),
            const SizedBox(width: 8),
            Text('My Videos',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: cs.primary, fontWeight: FontWeight.w700)),
            const SizedBox(width: 8),
            if (drafts.isNotEmpty)
              Text('${drafts.length}',
                  style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
            const Spacer(),
            if (drafts.isNotEmpty)
              TextButton.icon(
                icon: const Icon(Icons.delete_sweep_outlined, size: 18),
                label: const Text('Clear all'),
                onPressed: () async {
                  final ok = await showDialog<bool>(
                    context: context,
                    builder: (_) => AlertDialog(
                      title: const Text('Delete all videos?'),
                      content: Text(
                          '${drafts.length} video file(s) will be permanently deleted from your device.'),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(context, false),
                          child: const Text('Cancel'),
                        ),
                        FilledButton(
                          onPressed: () => Navigator.pop(context, true),
                          style: FilledButton.styleFrom(backgroundColor: cs.error),
                          child: const Text('Delete all'),
                        ),
                      ],
                    ),
                  );
                  if (ok == true && context.mounted) {
                    await context.read<AppProvider>().clearAllDrafts();
                  }
                },
                style: TextButton.styleFrom(foregroundColor: cs.error),
              ),
          ],
        ),
        const SizedBox(height: 8),
        if (drafts.isEmpty)
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest.withAlpha(60),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              children: [
                Icon(Icons.videocam_off_outlined,
                    size: 32, color: cs.outline),
                const SizedBox(height: 8),
                Text('No videos yet',
                    style: TextStyle(color: cs.onSurfaceVariant)),
                const SizedBox(height: 4),
                Text('Generated videos will appear here.',
                    style: TextStyle(
                        fontSize: 12, color: cs.onSurfaceVariant)),
              ],
            ),
          )
        else
          ...drafts.map((d) => _DraftTile(draft: d)),
      ],
    );
  }
}

class _DraftTile extends StatelessWidget {
  final SavedVideo draft;
  const _DraftTile({required this.draft});

  String _formatSize(int bytes) {
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  String _formatDate(DateTime d) {
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')} '
        '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: cs.primaryContainer,
          child: Icon(Icons.play_arrow, color: cs.onPrimaryContainer),
        ),
        title: Text(draft.topic,
            maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text(
          '${_formatDate(draft.created)}  •  ${_formatSize(draft.sizeBytes)}',
          style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
        ),
        trailing: IconButton(
          icon: Icon(Icons.delete_outline, color: cs.error, size: 20),
          tooltip: 'Delete',
          onPressed: () async {
            final ok = await showDialog<bool>(
              context: context,
              builder: (_) => AlertDialog(
                title: const Text('Delete video?'),
                content: Text(draft.topic),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('Cancel'),
                  ),
                  FilledButton(
                    onPressed: () => Navigator.pop(context, true),
                    style: FilledButton.styleFrom(backgroundColor: cs.error),
                    child: const Text('Delete'),
                  ),
                ],
              ),
            );
            if (ok == true && context.mounted) {
              await context.read<AppProvider>().deleteDraft(draft);
            }
          },
        ),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => PreviewScreen(videoPath: draft.path)),
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

class _StatusBar extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final cfg = context.watch<AppProvider>().config;
    final cs = Theme.of(context).colorScheme;

    final items = [
      (
        'LLM',
        cfg.llmProvider.displayName,
        cfg.llmApiKey.isNotEmpty,
      ),
      (
        cfg.visualSource.isAI ? 'Image' : 'Video',
        cfg.visualSource.displayName,
        cfg.visualApiKey.isNotEmpty,
      ),
      (
        'Voice',
        cfg.ttsProvider.displayName,
        !cfg.ttsProvider.requiresKey || cfg.ttsApiKey.isNotEmpty,
      ),
    ];

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: items.map((item) {
          final label = item.$1;
          final name = item.$2;
          final ok = item.$3;
          return Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
                decoration: BoxDecoration(
                  color: (ok ? Colors.green : cs.error).withAlpha(24),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          ok
                              ? Icons.check_circle_outline
                              : Icons.error_outline,
                          size: 12,
                          color: ok ? Colors.green : cs.error,
                        ),
                        const SizedBox(width: 4),
                        Text(label,
                            style: TextStyle(
                                fontSize: 10,
                                color: cs.onSurfaceVariant)),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(name,
                        style: const TextStyle(
                            fontSize: 11, fontWeight: FontWeight.w600),
                        overflow: TextOverflow.ellipsis),
                  ],
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

