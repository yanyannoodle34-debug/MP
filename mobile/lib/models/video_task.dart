enum TaskStep {
  idle,
  generatingScript,
  generatingImages,
  synthesizingAudio,
  composingVideo,
  done,
  error,
  cancelled,
}

extension TaskStepLabel on TaskStep {
  String get label {
    switch (this) {
      case TaskStep.idle:
        return 'Ready';
      case TaskStep.generatingScript:
        return 'Writing script…';
      case TaskStep.generatingImages:
        return 'Generating images…';
      case TaskStep.synthesizingAudio:
        return 'Synthesizing audio…';
      case TaskStep.composingVideo:
        return 'Composing video…';
      case TaskStep.done:
        return 'Done';
      case TaskStep.error:
        return 'Error';
      case TaskStep.cancelled:
        return 'Cancelled';
    }
  }

  bool get isActive =>
      this != TaskStep.idle &&
      this != TaskStep.done &&
      this != TaskStep.error &&
      this != TaskStep.cancelled;

  double get progress {
    switch (this) {
      case TaskStep.idle:
        return 0.0;
      case TaskStep.generatingScript:
        return 0.10;
      case TaskStep.generatingImages:
        return 0.40;
      case TaskStep.synthesizingAudio:
        return 0.65;
      case TaskStep.composingVideo:
        return 0.85;
      case TaskStep.done:
        return 1.0;
      case TaskStep.error:
      case TaskStep.cancelled:
        return 0.0;
    }
  }
}

class VideoTask {
  final String id;
  final String topic;
  final TaskStep step;
  final String? outputPath;
  final String? errorMessage;
  final List<String> logs;
  final double stageProgress; // 0..1 within current stage

  const VideoTask({
    required this.id,
    required this.topic,
    this.step = TaskStep.idle,
    this.outputPath,
    this.errorMessage,
    this.logs = const [],
    this.stageProgress = 0.0,
  });

  VideoTask copyWith({
    TaskStep? step,
    String? outputPath,
    String? errorMessage,
    List<String>? logs,
    double? stageProgress,
  }) {
    return VideoTask(
      id: id,
      topic: topic,
      step: step ?? this.step,
      outputPath: outputPath ?? this.outputPath,
      errorMessage: errorMessage ?? this.errorMessage,
      logs: logs ?? this.logs,
      stageProgress: stageProgress ?? this.stageProgress,
    );
  }

  VideoTask addLog(String msg) => copyWith(logs: [...logs, msg]);
}
