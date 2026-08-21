import 'dart:io';
import 'package:chewie/chewie.dart';
import 'package:flutter/material.dart';
import 'package:saver_gallery/saver_gallery.dart';
import 'package:share_plus/share_plus.dart';
import 'package:video_player/video_player.dart';

class PreviewScreen extends StatefulWidget {
  final String videoPath;

  const PreviewScreen({super.key, required this.videoPath});

  @override
  State<PreviewScreen> createState() => _PreviewScreenState();
}

class _PreviewScreenState extends State<PreviewScreen> {
  VideoPlayerController? _vpc;
  ChewieController? _cc;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _initPlayer();
  }

  Future<void> _initPlayer() async {
    try {
      final vpc = VideoPlayerController.file(File(widget.videoPath));
      await vpc.initialize();

      final cc = ChewieController(
        videoPlayerController: vpc,
        autoPlay: true,
        looping: false,
        aspectRatio: 9 / 16,
        allowFullScreen: true,
      );

      setState(() {
        _vpc = vpc;
        _cc = cc;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  @override
  void dispose() {
    _cc?.dispose();
    _vpc?.dispose();
    super.dispose();
  }

  Future<void> _saveToGallery() async {
    try {
      final result = await SaverGallery.saveFile(
        filePath: widget.videoPath,
        fileName: 'CloudAI_${DateTime.now().millisecondsSinceEpoch}.mp4',
        androidRelativePath: 'Movies/CloudAICreator',
        skipIfExists: false,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
              result.isSuccess ? 'Saved to gallery!' : 'Save failed: ${result.errorMessage}'),
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Save failed: $e')));
      }
    }
  }

  Future<void> _share() async {
    await Share.shareXFiles(
      [XFile(widget.videoPath)],
      text: 'Made with CloudAI Creator',
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('Preview', style: TextStyle(color: Colors.white)),
        actions: [
          IconButton(
            icon: const Icon(Icons.save_alt, color: Colors.white),
            tooltip: 'Save to gallery',
            onPressed: _saveToGallery,
          ),
          IconButton(
            icon: const Icon(Icons.share, color: Colors.white),
            tooltip: 'Share',
            onPressed: _share,
          ),
        ],
      ),
      body: Center(
        child: _loading
            ? const CircularProgressIndicator()
            : _error != null
                ? _ErrorView(error: _error!)
                : _cc != null
                    ? Chewie(controller: _cc!)
                    : const SizedBox.shrink(),
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  final String error;
  const _ErrorView({required this.error});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.error_outline, color: Colors.red, size: 48),
          const SizedBox(height: 16),
          const Text('Failed to load video',
              style: TextStyle(color: Colors.white, fontSize: 18)),
          const SizedBox(height: 8),
          Text(error,
              style: const TextStyle(color: Colors.white54, fontSize: 12),
              textAlign: TextAlign.center),
        ],
      ),
    );
  }
}
