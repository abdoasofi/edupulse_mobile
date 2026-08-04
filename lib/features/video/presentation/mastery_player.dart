import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../../student/domain/student_models.dart';
import '../data/video_repository.dart';

/// The mastery-clip player.
///
/// Reports progress every [VideoRepository.heartbeatSeconds] with the real
/// elapsed playback as `delta`, so seeking to the end cannot mark a lesson
/// complete — the server only credits contiguous playback.
class MasteryPlayer extends StatefulWidget {
  const MasteryPlayer({
    required this.lesson,
    required this.video,
    required this.repository,
    required this.resolveUrl,
    this.onCompleted,
    super.key,
  });

  final String lesson;
  final VideoDescriptor video;
  final VideoRepository repository;

  /// Turns a site-relative media path into something the player can open.
  final String Function(String) resolveUrl;

  /// Fired once, when the server confirms the watch threshold was crossed.
  final void Function(String? gateQuiz)? onCompleted;

  @override
  State<MasteryPlayer> createState() => _MasteryPlayerState();
}

class _MasteryPlayerState extends State<MasteryPlayer> {
  VideoPlayerController? _controller;
  Timer? _heartbeat;

  Duration _lastReported = Duration.zero;
  bool _initialising = true;
  bool _completedNotified = false;
  String? _error;

  static String get _device {
    if (Platform.isAndroid) return 'Android';
    if (Platform.isIOS) return 'iOS';
    return 'Web';
  }

  @override
  void initState() {
    super.initState();
    _setUp();
  }

  Future<void> _setUp() async {
    final raw = widget.video.url;
    final url = raw == null ? null : widget.resolveUrl(raw);

    if (!widget.video.playable || url == null || url.isEmpty) {
      setState(() {
        _initialising = false;
        _error = 'لا يوجد فيديو لهذا الدرس.';
      });
      return;
    }

    final controller = VideoPlayerController.networkUrl(Uri.parse(url));

    try {
      await controller.initialize();

      // Resume where the student left off, on any device.
      final resume = Duration(seconds: widget.video.resumeAt.round());
      if (resume > Duration.zero && resume < controller.value.duration) {
        await controller.seekTo(resume);
        _lastReported = resume;
      }

      if (!mounted) {
        await controller.dispose();
        return;
      }

      setState(() {
        _controller = controller;
        _initialising = false;
      });

      _startHeartbeat();
    } catch (e) {
      await controller.dispose();
      if (!mounted) return;
      setState(() {
        _initialising = false;
        // Surface the real cause. A bare "playback failed" hides DNS blocks,
        // 404s and codec problems alike, which makes field support guesswork.
        _error = 'تعذّر تشغيل الفيديو\n$url\n$e';
      });
    }
  }

  void _startHeartbeat() {
    _heartbeat = Timer.periodic(
      const Duration(seconds: VideoRepository.heartbeatSeconds),
      (_) => _report(),
    );
  }

  Future<void> _report() async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    if (!controller.value.isPlaying) return;

    final position = controller.value.position;
    final delta = position - _lastReported;
    _lastReported = position;

    // Negative or huge jumps are seeks, not watching — send 0 and let the
    // server keep its own authoritative max position.
    final credited = delta.inMilliseconds <= 0
        ? 0.0
        : (delta.inMilliseconds / 1000).clamp(0.0, 30.0);

    try {
      final update = await widget.repository.updateProgress(
        lesson: widget.lesson,
        position: position.inMilliseconds / 1000,
        duration: controller.value.duration.inMilliseconds / 1000,
        delta: credited,
        device: _device,
      );

      if (update.newlyCompleted && !_completedNotified) {
        _completedNotified = true;
        widget.onCompleted?.call(update.gateQuiz);
      }
    } catch (_) {
      // Offline or transient — playback must never stall on a failed report.
      // TODO: queue locally and flush via VideoRepository.syncOffline.
    }
  }

  @override
  void dispose() {
    _heartbeat?.cancel();
    _report();
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_initialising) {
      return const AspectRatio(
        aspectRatio: 16 / 9,
        child: ColoredBox(
          color: Colors.black12,
          child: Center(child: CircularProgressIndicator()),
        ),
      );
    }

    final controller = _controller;

    if (controller == null) {
      return AspectRatio(
        aspectRatio: 16 / 9,
        child: ColoredBox(
          color: Colors.black12,
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.videocam_off_outlined, size: 40),
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Text(
                    _error ?? 'غير متاح',
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 11),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Column(
      children: [
        AspectRatio(
          aspectRatio: controller.value.aspectRatio,
          child: Stack(
            alignment: Alignment.bottomCenter,
            children: [
              VideoPlayer(controller),
              VideoProgressIndicator(controller, allowScrubbing: true),
            ],
          ),
        ),
        _Controls(controller: controller),
      ],
    );
  }
}

class _Controls extends StatelessWidget {
  const _Controls({required this.controller});

  final VideoPlayerController controller;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<VideoPlayerValue>(
      valueListenable: controller,
      builder: (context, value, _) {
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                icon: const Icon(Icons.replay_10),
                onPressed: () => controller.seekTo(
                  value.position - const Duration(seconds: 10),
                ),
              ),
              IconButton(
                iconSize: 42,
                icon: Icon(
                  value.isPlaying
                      ? Icons.pause_circle_filled
                      : Icons.play_circle_fill,
                ),
                onPressed: () =>
                    value.isPlaying ? controller.pause() : controller.play(),
              ),
              IconButton(
                icon: const Icon(Icons.forward_10),
                onPressed: () => controller.seekTo(
                  value.position + const Duration(seconds: 10),
                ),
              ),
              const SizedBox(width: 12),
              Text(
                '${_fmt(value.position)} / ${_fmt(value.duration)}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        );
      },
    );
  }

  String _fmt(Duration d) =>
      '${d.inMinutes.toString().padLeft(2, '0')}:'
      '${(d.inSeconds % 60).toString().padLeft(2, '0')}';
}
