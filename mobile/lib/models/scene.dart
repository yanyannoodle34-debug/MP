class Scene {
  final int index;
  final String narration;
  final String imagePrompt;   // AI generation prompt (empty for stock)
  final String searchQuery;   // stock search terms (empty for AI)

  String? mediaPath;          // downloaded/generated file path
  bool mediaIsVideo;          // true = video clip, false = still image
  String? audioPath;
  double audioDuration;

  Scene({
    required this.index,
    required this.narration,
    this.imagePrompt = '',
    this.searchQuery = '',
    this.mediaPath,
    this.mediaIsVideo = false,
    this.audioPath,
    this.audioDuration = 4.0,
  });
}

class VideoScript {
  final String title;
  final List<Scene> scenes;

  const VideoScript({required this.title, required this.scenes});
}
