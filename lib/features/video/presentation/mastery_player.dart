import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:youtube_player_iframe/youtube_player_iframe.dart';

import '../../student/domain/student_models.dart';
import '../data/video_repository.dart';

/// Which backend a descriptor needs.
///
/// Extracted from `build` so the choice is testable on its own. Instantiating
/// the real backends in a unit test proves nothing — one needs a platform
/// webview, the other a codec — while picking the wrong one is exactly the
/// failure that would ship unnoticed and leave a whole school unable to play
/// its lessons.
enum PlayerBackend { native, youtube, none }

/// How long a backend gets to report itself ready before we call it failed.
///
/// Neither backend gives up on its own. ExoPlayer retries an unreachable host
/// behind `initialize()` and the future never completes; the YouTube iframe
/// sits in a webview that emits no event at all when it cannot reach
/// youtube.com. Both leave the student on a spinner — or worse, a blank
/// rectangle — which is the one failure mode indistinguishable from "still
/// loading", and therefore the one nobody ever reports as a bug.
///
/// Long enough for a slow school connection to fetch a manifest, short enough
/// that a student stops waiting and tells someone.
const Duration playerReadyTimeout = Duration(seconds: 20);

PlayerBackend backendFor(VideoDescriptor video) {
  if (!video.playable) return PlayerBackend.none;

  return switch (video.kind) {
    VideoKind.youtube => PlayerBackend.youtube,
    VideoKind.hls || VideoKind.mp4 => PlayerBackend.native,
    VideoKind.none => PlayerBackend.none,
  };
}

/// The mastery-clip player.
///
/// The server hides which CDN a school runs behind a playback descriptor, but
/// it cannot hide the *shape* of the media: an mp4, an HLS manifest and a
/// YouTube embed need three different players. So this widget dispatches on
/// `kind` — three backends, no knowledge of providers — and everything above it
/// keeps talking about one `VideoDescriptor`.
///
/// It also owns the two things neither backend can do for itself:
///
/// **Re-resolving an expiring URL.** A signed CDN link dies on a timer. Left
/// alone it dies mid-lesson, and the student sees a failure they cannot act on.
/// The descriptor carries `expires_in`; this refreshes ahead of it and resumes
/// at the same second.
///
/// **Crediting only contiguous playback**, so seeking to the end never
/// completes a lesson. That rule is the whole unlock gate, so it lives in one
/// place — [_ProgressReporter] — rather than once per backend.
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
  late VideoDescriptor _video;
  late _ProgressReporter _reporter;

  Timer? _refresh;
  Duration _position = Duration.zero;
  bool _refreshing = false;

  /// One retry only. A URL that fails twice is broken, not expired, and an
  /// endless refresh loop would hammer the server behind a spinner.
  bool _retried = false;

  @override
  void initState() {
    super.initState();
    _video = widget.video;
    _reporter = _ProgressReporter(
      lesson: widget.lesson,
      repository: widget.repository,
      onCompleted: widget.onCompleted,
      onPosition: (p) => _position = p,
    );
    _scheduleRefresh();
  }

  @override
  void didUpdateWidget(MasteryPlayer old) {
    super.didUpdateWidget(old);
    if (old.video.url != widget.video.url) {
      _video = widget.video;
      _retried = false;
      _scheduleRefresh();
    }
  }

  @override
  void dispose() {
    _refresh?.cancel();
    _reporter.dispose();
    super.dispose();
  }

  void _scheduleRefresh() {
    _refresh?.cancel();

    final after = _video.refreshAfter;
    if (after == null) return;

    _refresh = Timer(after, () => _reResolve());
  }

  /// Ask the server for a fresh URL and carry the current position across, so
  /// a refresh is invisible rather than a restart from zero.
  Future<void> _reResolve() async {
    if (_refreshing || !mounted) return;
    _refreshing = true;

    try {
      final fresh = await widget.repository.getPlayback(widget.lesson);
      if (!mounted) return;

      setState(() {
        _video = fresh.resumedAt(_position.inSeconds.toDouble());
      });
      _scheduleRefresh();
    } catch (_) {
      // Keep playing on the old URL — it may still have seconds left, and a
      // failed refresh is not itself a reason to stop the lesson.
    } finally {
      _refreshing = false;
    }
  }

  /// A native playback failure on a URL that was going to expire anyway is
  /// almost always the expiry. Try once before showing the student an error.
  Future<bool> _recoverFromFailure() async {
    if (_retried || _video.expiresIn == null) return false;

    _retried = true;
    await _reResolve();
    return mounted;
  }

  @override
  Widget build(BuildContext context) {
    return switch (backendFor(_video)) {
      PlayerBackend.youtube => _YouTubePlayer(
        key: ValueKey('yt:${_video.url}'),
        video: _video,
        reporter: _reporter,
      ),
      PlayerBackend.native => _NativePlayer(
        // Keyed on the URL so a refreshed link rebuilds the controller instead
        // of silently continuing to stream from a dead one.
        key: ValueKey('native:${_video.url}'),
        video: _video,
        reporter: _reporter,
        resolveUrl: widget.resolveUrl,
        onFailure: _recoverFromFailure,
      ),
      PlayerBackend.none => const _PlayerMessage(
        icon: Icons.videocam_off_outlined,
        message: 'لا يوجد فيديو لهذا الدرس.',
      ),
    };
  }
}

// ---------------------------------------------------------------- reporting
/// Sends playback to the server, shared by every backend.
///
/// `delta` is real elapsed playback, clamped: the server credits only
/// contiguous watching, so scrubbing to the end cannot open the quiz gate.
class _ProgressReporter {
  _ProgressReporter({
    required this.lesson,
    required this.repository,
    this.onCompleted,
    this.onPosition,
  });

  final String lesson;
  final VideoRepository repository;
  final void Function(String? gateQuiz)? onCompleted;
  final void Function(Duration)? onPosition;

  Duration _lastReported = Duration.zero;
  bool _notified = false;
  bool _disposed = false;

  static String get device {
    if (Platform.isAndroid) return 'Android';
    if (Platform.isIOS) return 'iOS';
    return 'Web';
  }

  /// Seed the baseline when resuming, so the jump to the resume point is not
  /// credited as watched time the student never spent.
  void seed(Duration position) => _lastReported = position;

  void dispose() => _disposed = true;

  Future<void> report({
    required Duration position,
    required Duration duration,
  }) async {
    if (_disposed) return;

    onPosition?.call(position);

    final delta = position - _lastReported;
    _lastReported = position;

    final credited = delta.inMilliseconds <= 0
        ? 0.0
        : (delta.inMilliseconds / 1000).clamp(0.0, 30.0);

    try {
      final update = await repository.updateProgress(
        lesson: lesson,
        position: position.inMilliseconds / 1000,
        duration: duration.inMilliseconds / 1000,
        delta: credited,
        device: device,
      );

      if (update.newlyCompleted && !_notified) {
        _notified = true;
        onCompleted?.call(update.gateQuiz);
      }
    } catch (_) {
      // Offline or transient — playback must never stall on a failed report.
      // Phase 3 queues these locally and flushes via syncOffline.
    }
  }
}

// ----------------------------------------------------------- native backend
/// mp4 and HLS. `video_player` handles both; the platform decides the codec.
class _NativePlayer extends StatefulWidget {
  const _NativePlayer({
    required this.video,
    required this.reporter,
    required this.resolveUrl,
    required this.onFailure,
    super.key,
  });

  final VideoDescriptor video;
  final _ProgressReporter reporter;
  final String Function(String) resolveUrl;

  /// Returns true when a retry is under way and the error should stay hidden.
  final Future<bool> Function() onFailure;

  @override
  State<_NativePlayer> createState() => _NativePlayerState();
}

class _NativePlayerState extends State<_NativePlayer> {
  VideoPlayerController? _controller;
  Timer? _heartbeat;
  bool _initialising = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _setUp();
  }

  Future<void> _setUp() async {
    final url = widget.resolveUrl(widget.video.url!);
    final controller = VideoPlayerController.networkUrl(Uri.parse(url));

    try {
      await controller.initialize().timeout(playerReadyTimeout);

      // Resume where the student left off, on any device.
      final resume = Duration(seconds: widget.video.resumeAt.round());
      if (resume > Duration.zero && resume < controller.value.duration) {
        await controller.seekTo(resume);
      }
      widget.reporter.seed(resume);

      if (!mounted) {
        await controller.dispose();
        return;
      }

      setState(() {
        _controller = controller;
        _initialising = false;
      });

      _heartbeat = Timer.periodic(
        const Duration(seconds: VideoRepository.heartbeatSeconds),
        (_) => _report(),
      );
    } catch (e) {
      await controller.dispose();
      if (!mounted) return;

      // An expiring URL that fails is almost certainly expired. Let the parent
      // refresh it before the student ever sees a failure.
      if (await widget.onFailure()) return;
      if (!mounted) return;

      setState(() {
        _initialising = false;
        // Surface the real cause. A bare "playback failed" hides DNS blocks,
        // 404s and codec problems alike, which makes field support guesswork.
        _error = 'تعذّر تشغيل الفيديو\n$url\n$e';
      });
    }
  }

  Future<void> _report() async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    if (!controller.value.isPlaying) return;

    await widget.reporter.report(
      position: controller.value.position,
      duration: controller.value.duration,
    );
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
    if (_initialising) return const _PlayerLoading();

    final controller = _controller;
    if (controller == null) {
      return _PlayerMessage(
        icon: Icons.videocam_off_outlined,
        message: _error ?? 'غير متاح',
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

// ---------------------------------------------------------- youtube backend
/// A school on YouTube pays nothing for hosting and cannot cache a thing. The
/// embed carries its own controls, so this only wires the progress heartbeat —
/// the unlock gate has to work identically whichever backend is playing.
class _YouTubePlayer extends StatefulWidget {
  const _YouTubePlayer({
    required this.video,
    required this.reporter,
    super.key,
  });

  final VideoDescriptor video;
  final _ProgressReporter reporter;

  @override
  State<_YouTubePlayer> createState() => _YouTubePlayerState();
}

class _YouTubePlayerState extends State<_YouTubePlayer> {
  late final YoutubePlayerController _controller;
  StreamSubscription<YoutubeVideoState>? _states;
  StreamSubscription<YoutubePlayerValue>? _values;
  Timer? _heartbeat;
  Timer? _deadline;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  String? _error;

  @override
  void initState() {
    super.initState();

    _controller = YoutubePlayerController.fromVideoId(
      videoId: widget.video.url!,
      autoPlay: false,
      startSeconds: widget.video.resumeAt,
      params: const YoutubePlayerParams(showFullscreenButton: true),
    );

    widget.reporter.seed(Duration(seconds: widget.video.resumeAt.round()));

    // The iframe reports position on its own stream; there is no controller
    // value to poll the way video_player exposes one.
    _states = _controller.videoStateStream.listen((state) {
      _position = state.position;
    });

    _values = _controller.listen((value) {
      if (value.hasError) {
        _fail(youtubeMessage(value.error));
      } else if (value.playerState != PlayerState.unknown) {
        // The iframe answered, so the wait is over. Nothing repaints on this —
        // the package owns the loading visual — so there is no setState.
        _deadline?.cancel();
      }
    });

    // A webview that cannot reach youtube.com reports nothing — no error
    // event, no state change, just an empty rectangle. A deadline is the only
    // thing that turns that silence into something a student can act on.
    _deadline = Timer(
      playerReadyTimeout,
      () => _fail('تعذّر الوصول إلى يوتيوب.\nتحقّق من اتصال الجهاز بالإنترنت.'),
    );

    _heartbeat = Timer.periodic(
      const Duration(seconds: VideoRepository.heartbeatSeconds),
      (_) => _report(),
    );
  }

  void _fail(String message) {
    _deadline?.cancel();
    _heartbeat?.cancel();

    // First cause wins: a stalled player that later reports an error should
    // keep the message the student has already been reading.
    if (!mounted || _error != null) return;

    setState(() => _error = message);
  }

  Future<void> _report() async {
    if (_duration == Duration.zero) {
      // Duration is only known once the iframe has loaded metadata. Falling
      // back to the authored duration keeps the watched-% honest until then.
      final seconds = await _controller.duration;
      _duration = seconds > 0
          ? Duration(seconds: seconds.round())
          : Duration(seconds: widget.video.duration);
    }

    if (_position == Duration.zero) return;

    await widget.reporter.report(position: _position, duration: _duration);
  }

  @override
  void dispose() {
    _heartbeat?.cancel();
    _deadline?.cancel();
    _states?.cancel();
    _values?.cancel();
    _report();
    _controller.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final error = _error;
    if (error != null) {
      return _PlayerMessage(icon: Icons.videocam_off_outlined, message: error);
    }

    // No loading overlay of our own. The package draws one — the video
    // thumbnail over a fallback colour — through an OverlayPortal, which
    // renders into the app's root Overlay and therefore paints above any Stack
    // we wrap around the player. A spinner stacked here is invisible on a
    // device; that was verified, not assumed.
    //
    // What we can control is the fallback, and it matters: unset, it defaults
    // to the theme surface — white — so a player waiting on an unreachable
    // youtube.com is indistinguishable from blank page. The same grey the
    // other two states use makes all three read as one component.
    return YoutubePlayer(
      controller: _controller,
      aspectRatio: 16 / 9,
      backgroundColor: Colors.black12,
    );
  }
}

/// What an iframe error means to a school, rather than to a developer.
String youtubeMessage(YoutubeError error) => switch (error) {
  // The one worth naming precisely. A teacher pastes a link to a video whose
  // owner disabled embedding; the id is valid, the server accepts it, and the
  // lesson is simply dead. Nothing before playback can detect this.
  YoutubeError.notEmbeddable ||
  YoutubeError.sameAsNotEmbeddable ||
  YoutubeError.sameAsNotEmbeddable2 =>
    'صاحب هذا الفيديو منع تشغيله خارج يوتيوب.\n'
        'أبلغ معلّمك ليرفعه أو يختار مقطعاً آخر.',
  YoutubeError.videoNotFound ||
  YoutubeError.cannotFindVideo => 'الفيديو غير موجود أو خاص.',
  YoutubeError.invalidParam => 'رابط يوتيوب غير صالح.',
  YoutubeError.html5Error => 'تعذّر تشغيل الفيديو على هذا الجهاز.',
  _ => 'تعذّر تشغيل الفيديو من يوتيوب.',
};

// -------------------------------------------------------------------- chrome
class _PlayerLoading extends StatelessWidget {
  const _PlayerLoading();

  @override
  Widget build(BuildContext context) => const AspectRatio(
    aspectRatio: 16 / 9,
    child: ColoredBox(
      color: Colors.black12,
      child: Center(child: CircularProgressIndicator()),
    ),
  );
}

class _PlayerMessage extends StatelessWidget {
  const _PlayerMessage({required this.icon, required this.message});

  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) => AspectRatio(
    aspectRatio: 16 / 9,
    child: ColoredBox(
      color: Colors.black12,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 40),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                message,
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
              // Media time reads left-to-right in every player, Arabic ones
              // included. Left to the ambient RTL direction, the bidi
              // algorithm reorders the two digit runs and a student 7 seconds
              // into a 10-second clip is shown "00:10 / 00:07" — reading as
              // three seconds past an end they have not reached.
              Directionality(
                textDirection: TextDirection.ltr,
                child: Text(
                  '${_fmt(value.position)} / ${_fmt(value.duration)}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
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
