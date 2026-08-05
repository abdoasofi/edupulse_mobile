import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:edupulse_mobile/core/network/api_client.dart';
import 'package:edupulse_mobile/features/student/domain/student_models.dart';
import 'package:edupulse_mobile/features/video/data/video_repository.dart';
import 'package:edupulse_mobile/features/video/presentation/mastery_player.dart';

/// The player must pick its backend from `kind` alone.
///
/// Before this, one `video_player` controller handled everything — which
/// silently means a school on YouTube ships an app that cannot play a single
/// one of its lessons. Nothing errors; the video just never starts.
void main() {
  VideoDescriptor descriptor(String kind, String? url) =>
      VideoDescriptor.fromJson({
        'kind': kind,
        'url': url,
        'duration': 420,
        'resume_at': 0.0,
      });

  group('backend selection', () {
    test('youtube goes to the iframe player', () {
      expect(
        backendFor(descriptor('youtube', 'dQw4w9WgXcQ')),
        PlayerBackend.youtube,
      );
    });

    test('mp4 and hls both go to the native player', () {
      // One controller covers both; the platform picks the codec. Splitting
      // them would be two code paths with nothing different to say.
      expect(backendFor(descriptor('mp4', '/files/a.mp4')), PlayerBackend.native);
      expect(backendFor(descriptor('hls', '/files/a.m3u8')), PlayerBackend.native);
    });

    test('a lesson with no clip attached picks no backend', () {
      expect(backendFor(descriptor('none', null)), PlayerBackend.none);
    });

    test('an empty or missing url never reaches a player', () {
      // A controller handed an empty URI throws on a background isolate, where
      // the failure surfaces as a frozen spinner rather than a message.
      expect(backendFor(descriptor('mp4', '')), PlayerBackend.none);
      expect(backendFor(descriptor('youtube', null)), PlayerBackend.none);
    });

    test('a kind this build predates degrades to none, not to a wrong player', () {
      // The server can add a provider that emits a new kind. Falling through
      // to the native player would hand it a URL it cannot open.
      expect(backendFor(descriptor('dash', '/files/a.mpd')), PlayerBackend.none);
    });
  });

  group('empty state', () {
    testWidgets('a lesson with no video says so instead of spinning', (
      tester,
    ) async {
      // A student left on an indefinite spinner has no way to know the lesson
      // simply has no clip attached yet.
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MasteryPlayer(
              lesson: 'LESSON-1',
              video: descriptor('none', null),
              repository: VideoRepository(_DeadApiClient()),
              resolveUrl: (p) => p,
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.byIcon(Icons.videocam_off_outlined), findsOneWidget);
      expect(find.text('لا يوجد فيديو لهذا الدرس.'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });
  });
}

/// Every call fails. Playback must never depend on a reachable server — the
/// heartbeat is best-effort by design.
class _DeadApiClient implements ApiClient {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      Future<Never>.error(StateError('offline'));
}
