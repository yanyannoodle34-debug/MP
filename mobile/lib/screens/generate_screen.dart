import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/video_task.dart';
import '../providers/app_provider.dart';
import 'preview_screen.dart';

class GenerateScreen extends StatelessWidget {
  const GenerateScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final task = context.watch<AppProvider>().currentTask;
    if (task == null) return const Scaffold(body: Center(child: CircularProgressIndicator()));

    final isError = task.step == TaskStep.error;

    return PopScope(
      canPop: !task.step.isActive,
      child: Scaffold(
        appBar: AppBar(
          title: Text(task.topic, maxLines: 1, overflow: TextOverflow.ellipsis),
          automaticallyImplyLeading: !task.step.isActive,
        ),
        body: Column(
          children: [
            // ── Overall progress bar ────────────────────────────────────────
            LinearProgressIndicator(
              value: isError ? 0 : task.step.progress,
              color: isError ? Colors.red : null,
              backgroundColor: isError
                  ? Colors.red.withAlpha(40)
                  : null,
            ),

            // ── Step chips ──────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: Wrap(
                spacing: 8,
                runSpacing: 6,
                children: TaskStep.values
                    .where((s) => s != TaskStep.idle)
                    .map((s) => _StepChip(step: s, current: task.step))
                    .toList(),
              ),
            ),

            // ── Stage progress (within current step) ────────────────────────
            if (task.step.isActive && task.stageProgress > 0)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(task.step.label,
                        style: Theme.of(context).textTheme.bodySmall),
                    const SizedBox(height: 4),
                    LinearProgressIndicator(value: task.stageProgress),
                  ],
                ),
              ),

            // ── Log output ──────────────────────────────────────────────────
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: _LogView(logs: task.logs, isError: isError),
              ),
            ),

            // ── Bottom actions ──────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
              child: _BottomActions(task: task),
            ),
          ],
        ),
      ),
    );
  }
}

class _StepChip extends StatelessWidget {
  final TaskStep step;
  final TaskStep current;

  const _StepChip({required this.step, required this.current});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDone = step.index < current.index;
    final isActive = step == current;
    final isError = current == TaskStep.error && isActive;

    Color bgColor;
    Color fgColor;
    Widget? icon;

    if (isError) {
      bgColor = cs.errorContainer;
      fgColor = cs.onErrorContainer;
      icon = Icon(Icons.error_outline, size: 14, color: fgColor);
    } else if (isDone) {
      bgColor = cs.primaryContainer;
      fgColor = cs.onPrimaryContainer;
      icon = Icon(Icons.check, size: 14, color: fgColor);
    } else if (isActive) {
      bgColor = cs.primary;
      fgColor = cs.onPrimary;
      icon = SizedBox(
        width: 14,
        height: 14,
        child: CircularProgressIndicator(strokeWidth: 2, color: fgColor),
      );
    } else {
      bgColor = cs.surfaceContainerHighest;
      fgColor = cs.onSurfaceVariant;
      icon = null;
    }

    return Chip(
      avatar: icon,
      label: Text(step.label, style: TextStyle(color: fgColor, fontSize: 12)),
      backgroundColor: bgColor,
      side: BorderSide.none,
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.zero,
    );
  }
}

class _LogView extends StatefulWidget {
  final List<String> logs;
  final bool isError;

  const _LogView({required this.logs, required this.isError});

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
          _scroll.animateTo(
            _scroll.position.maxScrollExtent,
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
          );
        }
      });
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Container(
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withAlpha(80),
        borderRadius: BorderRadius.circular(8),
      ),
      padding: const EdgeInsets.all(12),
      child: ListView.builder(
        controller: _scroll,
        itemCount: widget.logs.length,
        itemBuilder: (_, i) {
          final log = widget.logs[i];
          final isLast = i == widget.logs.length - 1;
          return Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(
              log,
              style: TextStyle(
                fontSize: 12,
                fontFamily: 'monospace',
                color: isLast && widget.isError
                    ? cs.error
                    : isLast
                        ? cs.primary
                        : cs.onSurfaceVariant,
              ),
            ),
          );
        },
      ),
    );
  }
}

class _BottomActions extends StatelessWidget {
  final VideoTask task;

  const _BottomActions({required this.task});

  @override
  Widget build(BuildContext context) {
    // ── Running: show Stop button ──────────────────────────────────────────
    if (task.step.isActive) {
      return OutlinedButton.icon(
        icon: const Icon(Icons.stop_circle_outlined),
        label: const Text('Stop'),
        onPressed: () => context.read<AppProvider>().stop(),
        style: OutlinedButton.styleFrom(
          foregroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    }

    // ── Cancelled ──────────────────────────────────────────────────────────
    if (task.step == TaskStep.cancelled) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Generation cancelled.',
              style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
              textAlign: TextAlign.center),
          const SizedBox(height: 12),
          OutlinedButton(
            onPressed: () {
              context.read<AppProvider>().reset();
              Navigator.pop(context);
            },
            child: const Text('Go back'),
          ),
        ],
      );
    }

    if (task.step == TaskStep.done && task.outputPath != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FilledButton.icon(
            icon: const Icon(Icons.play_circle_outline),
            label: const Text('Watch Video'),
            onPressed: () {
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(
                  builder: (_) => PreviewScreen(videoPath: task.outputPath!),
                ),
              );
            },
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: () {
              context.read<AppProvider>().reset();
              Navigator.pop(context);
            },
            child: const Text('Make Another'),
          ),
        ],
      );
    }

    if (task.step == TaskStep.error) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            task.errorMessage ?? 'Unknown error',
            style: TextStyle(color: Theme.of(context).colorScheme.error, fontSize: 13),
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 12),
          OutlinedButton(
            onPressed: () {
              context.read<AppProvider>().reset();
              Navigator.pop(context);
            },
            child: const Text('Go back'),
          ),
        ],
      );
    }

    return Text(
      task.step.label,
      style: Theme.of(context)
          .textTheme
          .bodySmall
          ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
      textAlign: TextAlign.center,
    );
  }
}
