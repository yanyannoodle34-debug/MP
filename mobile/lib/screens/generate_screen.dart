import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/video_task.dart';
import '../providers/app_provider.dart';
import 'preview_screen.dart';

class GenerateScreen extends StatelessWidget {
  const GenerateScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Generating…')),
      body: Consumer<AppProvider>(
        builder: (context, provider, _) {
          final task = provider.currentTask;
          if (task == null) return const SizedBox.shrink();

          return Column(
            children: [
              _ProgressHeader(task: task),
              Expanded(child: _LogView(logs: task.logs)),
              if (task.step == TaskStep.done)
                _DoneBar(videoPath: task.outputPath!, onPreview: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) =>
                          PreviewScreen(videoPath: task.outputPath!),
                    ),
                  );
                }),
              if (task.step == TaskStep.error)
                _ErrorBar(message: task.errorMessage ?? 'Unknown error'),
            ],
          );
        },
      ),
    );
  }
}

class _ProgressHeader extends StatelessWidget {
  final VideoTask task;
  const _ProgressHeader({required this.task});

  static const _steps = [
    (TaskStep.generatingScript, Icons.description, 'Script'),
    (TaskStep.downloadingMaterials, Icons.download, 'Materials'),
    (TaskStep.synthesizingAudio, Icons.record_voice_over, 'Audio'),
    (TaskStep.composingVideo, Icons.movie_creation, 'Compose'),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final currentIdx = _steps.indexWhere((s) => s.$1 == task.step);

    return Container(
      color: theme.colorScheme.surfaceContainerHighest,
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          LinearProgressIndicator(
            value: task.step.progress,
            minHeight: 6,
            borderRadius: BorderRadius.circular(3),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: List.generate(_steps.length, (i) {
              final (step, icon, label) = _steps[i];
              final done = currentIdx > i ||
                  task.step == TaskStep.done;
              final active = currentIdx == i;
              return _StepDot(
                icon: icon,
                label: label,
                done: done,
                active: active,
              );
            }),
          ),
          const SizedBox(height: 8),
          Text(
            task.step == TaskStep.error
                ? '✗ ${task.errorMessage ?? "Error"}'
                : task.step.label,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: task.step == TaskStep.error
                  ? theme.colorScheme.error
                  : null,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _StepDot extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool done;
  final bool active;
  const _StepDot(
      {required this.icon,
      required this.label,
      required this.done,
      required this.active});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    Color bg;
    Color fg;
    if (done) {
      bg = scheme.primary;
      fg = scheme.onPrimary;
    } else if (active) {
      bg = scheme.secondaryContainer;
      fg = scheme.onSecondaryContainer;
    } else {
      bg = scheme.surfaceContainerLow;
      fg = scheme.onSurfaceVariant;
    }

    return Column(
      children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          width: 40,
          height: 40,
          decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
          child: active
              ? Padding(
                  padding: const EdgeInsets.all(10),
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    color: fg,
                  ),
                )
              : Icon(done ? Icons.check : icon, color: fg, size: 20),
        ),
        const SizedBox(height: 4),
        Text(label, style: TextStyle(fontSize: 10, color: fg)),
      ],
    );
  }
}

class _LogView extends StatefulWidget {
  final List<String> logs;
  const _LogView({required this.logs});

  @override
  State<_LogView> createState() => _LogViewState();
}

class _LogViewState extends State<_LogView> {
  final _scroll = ScrollController();

  @override
  void didUpdateWidget(_LogView old) {
    super.didUpdateWidget(old);
    if (widget.logs.length != old.logs.length) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scroll.hasClients) {
          _scroll.animateTo(_scroll.position.maxScrollExtent,
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOut);
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      color: theme.colorScheme.surface,
      child: ListView.builder(
        controller: _scroll,
        padding: const EdgeInsets.all(12),
        itemCount: widget.logs.length,
        itemBuilder: (_, i) => Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Text(
            '› ${widget.logs[i]}',
            style: TextStyle(
              fontFamily: 'monospace',
              fontSize: 12,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }
}

class _DoneBar extends StatelessWidget {
  final String videoPath;
  final VoidCallback onPreview;
  const _DoneBar({required this.videoPath, required this.onPreview});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: FilledButton.icon(
          onPressed: onPreview,
          icon: const Icon(Icons.play_circle),
          label: const Text('Preview & Save Video'),
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
        ),
      ),
    );
  }
}

class _ErrorBar extends StatelessWidget {
  final String message;
  const _ErrorBar({required this.message});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Text(
          message,
          style: TextStyle(color: Theme.of(context).colorScheme.error),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}
