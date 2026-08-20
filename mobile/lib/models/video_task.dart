enum TaskStep {
  idle,
  generatingScript,
  downloadingMaterials,
  synthesizingAudio,
  composingVideo,
  done,
  error,
}

extension TaskStepLabel on TaskStep {
  String get label {
    switch (this) {
      case TaskStep.idle:
        return 'Ready';
      case TaskStep.generatingScript:
        return 'Generating script…';
      case TaskStep.downloadingMaterials:
        return 'Downloading materials…';
      case TaskStep.synthesizingAudio:
        return 'Synthesizing audio…';
      case TaskStep.composingVideo:
        return 'Composing video…';
      case TaskStep.done:
        return 'Done';
      case TaskStep.error:
        return 'Error';
    }
  }

  bool get isActive =>
      this != TaskStep.idle &&
      this != TaskStep.done &&
      this != TaskStep.error;

  double get progress {
    switch (this) {
      case TaskStep.idle:
        return 0.0;
      case TaskStep.generatingScript:
        return 0.15;
      case TaskStep.downloadingMaterials:
        return 0.40;
      case TaskStep.synthesizingAudio:
        return 0.65;
      case TaskStep.composingVideo:
        return 0.85;
      case TaskStep.done:
        return 1.0;
      case TaskStep.error:
        return 0.0;
    }
  }
}

class ScriptResult {
  final String script;
  final List<String> searchTerms;

  const ScriptResult({required this.script, required this.searchTerms});
}

class SubtitleEntry {
  final Duration start;
  final Duration end;
  final String text;

  const SubtitleEntry({
    required this.start,
    required this.end,
    required this.text,
  });
}

class VideoTask {
  final String id;
  final String topic;
  final TaskStep step;
  final String? script;
  final String? outputPath;
  final String? errorMessage;
  final List<String> logs;
  final double materialProgress;

  const VideoTask({
    required this.id,
    required this.topic,
    this.step = TaskStep.idle,
    this.script,
    this.outputPath,
    this.errorMessage,
    this.logs = const [],
    this.materialProgress = 0.0,
  });

  VideoTask copyWith({
    TaskStep? step,
    String? script,
    String? outputPath,
    String? errorMessage,
    List<String>? logs,
    double? materialProgress,
  }) {
    return VideoTask(
      id: id,
      topic: topic,
      step: step ?? this.step,
      script: script ?? this.script,
      outputPath: outputPath ?? this.outputPath,
      errorMessage: errorMessage ?? this.errorMessage,
      logs: logs ?? this.logs,
      materialProgress: materialProgress ?? this.materialProgress,
    );
  }

  VideoTask addLog(String msg) => copyWith(logs: [...logs, msg]);
}
