class Scene {
  final int index;
  final String narration;
  final String imagePrompt;

  String? imagePath;
  String? audioPath;
  double audioDuration;

  Scene({
    required this.index,
    required this.narration,
    required this.imagePrompt,
    this.imagePath,
    this.audioPath,
    this.audioDuration = 4.0,
  });
}

class VideoScript {
  final String title;
  final List<Scene> scenes;

  const VideoScript({required this.title, required this.scenes});
}
