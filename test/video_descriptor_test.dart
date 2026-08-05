import 'package:flutter_test/flutter_test.dart';

import 'package:edupulse_mobile/features/student/domain/student_models.dart';

/// The playback descriptor is the whole contract between a school's CDN choice
/// and this app. Five providers on the server collapse into three `kind`s here,
/// and everything else — expiry, offline entitlement — travels as data rather
/// than as a branch someone has to remember to add.
void main() {
  Map<String, dynamic> wire({
    String kind = 'mp4',
    String? url = '/files/a.mp4',
    Object? expiresIn,
    Object? offlineAllowed,
    String? provider,
  }) => {
    'kind': kind,
    'url': url,
    'duration': 420,
    'min_watch_percentage': 90,
    'watched_percentage': 12.5,
    'resume_at': 30.0,
    'completed': false,
    'poster': null,
    'provider': provider,
    'offline_allowed': offlineAllowed,
    'expires_in': expiresIn,
  };

  group('parsing', () {
    test('reads the fields the video-delivery layer added', () {
      final v = VideoDescriptor.fromJson(
        wire(provider: 'Bunny Stream', offlineAllowed: true, expiresIn: 3600),
      );

      expect(v.provider, 'Bunny Stream');
      expect(v.offlineAllowed, true);
      expect(v.expiresIn, 3600);
    });

    test('an older server that omits them stays playable', () {
      // The app must not require a field the tenant's site has not shipped yet.
      final v = VideoDescriptor.fromJson({
        'kind': 'mp4',
        'url': '/files/a.mp4',
        'duration': 100,
      });

      expect(v.playable, true);
      expect(v.provider, isNull);
      expect(v.offlineAllowed, false);
      expect(v.expiresIn, isNull);
    });

    test('every server kind maps to a backend this app has', () {
      expect(VideoKind.fromWire('hls'), VideoKind.hls);
      expect(VideoKind.fromWire('mp4'), VideoKind.mp4);
      expect(VideoKind.fromWire('youtube'), VideoKind.youtube);
      expect(VideoKind.fromWire('none'), VideoKind.none);
    });

    test('an unknown kind degrades to none rather than crashing', () {
      // A future provider could introduce a kind this build predates. Refusing
      // to parse would take the whole lesson screen down; "no video" would not.
      expect(VideoKind.fromWire('dash'), VideoKind.none);
      expect(VideoKind.fromWire(null), VideoKind.none);
    });

    test('a kind with no url is not playable', () {
      expect(VideoDescriptor.fromJson(wire(url: null)).playable, false);
      expect(VideoDescriptor.fromJson(wire(url: '')).playable, false);
      expect(VideoDescriptor.fromJson(wire(kind: 'none')).playable, false);
    });
  });

  group('refreshAfter', () {
    test('a URL that never expires is never refreshed', () {
      // Polling a permanent URL would be pure waste on a school's data plan.
      expect(VideoDescriptor.fromJson(wire()).refreshAfter, isNull);
      expect(VideoDescriptor.fromJson(wire(expiresIn: 0)).refreshAfter, isNull);
    });

    test('refreshes ahead of expiry, not on it', () {
      // Refreshing early is free. Refreshing late is a student staring at an
      // error they cannot act on, halfway through a lesson.
      final v = VideoDescriptor.fromJson(wire(expiresIn: 3600));

      expect(v.refreshAfter, const Duration(seconds: 2880));
      expect(v.refreshAfter!.inSeconds, lessThan(3600));
    });

    test('a very short TTL still leaves time to actually fetch', () {
      // 80% of 10s is 8s — short enough that the refresh request itself could
      // outlive the URL. The floor keeps the loop from thrashing.
      expect(
        VideoDescriptor.fromJson(wire(expiresIn: 10)).refreshAfter,
        const Duration(seconds: 30),
      );
    });
  });

  group('resumedAt', () {
    test('carries the live position across a refresh', () {
      // The server answers a re-resolve with its stored resume point, which
      // lags the student's real position by up to one heartbeat. Using it
      // verbatim would rewind them every time a signed URL rotated.
      final fresh = VideoDescriptor.fromJson(wire(expiresIn: 600));
      final resumed = fresh.resumedAt(275);

      expect(resumed.resumeAt, 275);
      expect(fresh.resumeAt, 30.0, reason: 'the original must not mutate');
    });

    test('changes nothing else about the descriptor', () {
      final fresh = VideoDescriptor.fromJson(
        wire(kind: 'hls', provider: 'Bunny Stream', offlineAllowed: true, expiresIn: 600),
      );
      final resumed = fresh.resumedAt(275);

      expect(resumed.kind, fresh.kind);
      expect(resumed.url, fresh.url);
      expect(resumed.duration, fresh.duration);
      expect(resumed.minWatchPercentage, fresh.minWatchPercentage);
      expect(resumed.provider, fresh.provider);
      expect(resumed.offlineAllowed, fresh.offlineAllowed);
      expect(resumed.expiresIn, fresh.expiresIn);
    });
  });

  group('offline entitlement', () {
    test('is carried as data, so no screen hard-codes a provider name', () {
      // YouTube's terms forbid downloading. The server decides that once; the
      // app must never grow an `if (provider == "YouTube")` of its own.
      final youtube = VideoDescriptor.fromJson(
        wire(kind: 'youtube', url: 'dQw4w9WgXcQ', offlineAllowed: false),
      );
      final drive = VideoDescriptor.fromJson(wire(offlineAllowed: true));

      expect(youtube.offlineAllowed, false);
      expect(drive.offlineAllowed, true);
    });
  });
}
