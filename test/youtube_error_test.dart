import 'package:flutter_test/flutter_test.dart';
import 'package:youtube_player_iframe/youtube_player_iframe.dart';

import 'package:edupulse_mobile/features/video/presentation/mastery_player.dart';

/// The iframe backend can only fail *inside* a webview, where nothing throws
/// and nothing renders. On a device with no DNS it drew a blank rectangle: no
/// spinner, no message, nothing to report. Every path out of that state has to
/// end in words a student can read.
void main() {
  group('youtubeMessage', () {
    test('every error code produces something readable', () {
      // The guard that matters. A code with no message would put the player
      // back where it started — an empty box — and a new code is exactly what
      // a YouTube API change would introduce.
      for (final error in YoutubeError.values) {
        expect(
          youtubeMessage(error).trim(),
          isNotEmpty,
          reason: '$error has no message',
        );
      }
    });

    test('a video whose owner blocked embedding says so, and who to tell', () {
      // The one case worth naming precisely: the id is valid, the server
      // accepts it, and the lesson is simply dead. Nothing before playback can
      // detect it, so the message is the only path back to a working lesson.
      for (final error in [
        YoutubeError.notEmbeddable,
        YoutubeError.sameAsNotEmbeddable,
        YoutubeError.sameAsNotEmbeddable2,
      ]) {
        expect(youtubeMessage(error), contains('خارج يوتيوب'));
        expect(youtubeMessage(error), contains('معلّم'));
      }
    });

    test('a missing or private video is not reported as a device problem', () {
      // Telling a student their phone cannot play it sends them to the wrong
      // person. This is the teacher's link to fix.
      for (final error in [
        YoutubeError.videoNotFound,
        YoutubeError.cannotFindVideo,
      ]) {
        expect(youtubeMessage(error), contains('غير موجود'));
      }
    });

    test('an unrecognised code still lands on the generic message', () {
      expect(youtubeMessage(YoutubeError.unknown), contains('تعذّر'));
      expect(youtubeMessage(YoutubeError.none), contains('تعذّر'));
    });
  });

  group('playerReadyTimeout', () {
    test('is finite, so no backend can wait forever', () {
      // Both backends stall silently on an unreachable host — ExoPlayer never
      // completes its future, the iframe never emits an event. The deadline is
      // the only thing that ends either wait.
      expect(playerReadyTimeout, greaterThan(Duration.zero));
      expect(playerReadyTimeout, lessThan(const Duration(minutes: 1)));
    });
  });
}
