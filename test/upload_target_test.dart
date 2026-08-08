import 'package:flutter_test/flutter_test.dart';

import 'package:edupulse_mobile/features/teacher/domain/teacher_models.dart';

/// The authoring screen renders from `strategy` and nothing else.
///
/// That is the whole contract: five providers on the server collapse into three
/// ways of getting a video in, and a school on Drive and a school on YouTube
/// run the same binary. If this mapping is ever wrong, a teacher is shown a
/// form that cannot produce a reference their school's provider accepts.
void main() {
  Map<String, dynamic> wire({
    String? strategy = 'site_file',
    bool available = true,
    String provider = 'Frappe Drive',
  }) => {
    'provider': provider,
    'provider_label': 'ملفات الموقع',
    'strategy': strategy,
    'hint_ar': 'ارفع الملف إلى الموقع مباشرة.',
    'accepts': ['video/mp4'],
    'available': available,
    'offline_allowed': true,
  };

  group('strategy mapping', () {
    test('every strategy the server declares has a form here', () {
      expect(UploadStrategy.fromWire('site_file'), UploadStrategy.siteFile);
      expect(UploadStrategy.fromWire('external_url'), UploadStrategy.externalUrl);
      expect(UploadStrategy.fromWire('direct_post'), UploadStrategy.directPost);
    });

    test('a strategy this build predates offers nothing, not the wrong form', () {
      // A sixth provider could introduce one. Falling through to the file
      // picker would have the teacher upload to a site that will not serve it.
      expect(UploadStrategy.fromWire('presigned_v2'), UploadStrategy.unknown);
      expect(UploadStrategy.fromWire(null), UploadStrategy.unknown);
    });
  });

  group('canUpload', () {
    test('a configured, implemented provider can be uploaded to', () {
      expect(UploadTarget.fromJson(wire()).canUpload, true);
    });

    test('a half-built provider refuses before the teacher records anything', () {
      // Bunny and S3 are selectable in the table but have no handler. Better a
      // disabled button than a teacher who uploads and is refused at the end.
      expect(UploadTarget.fromJson(wire(available: false)).canUpload, false);
    });

    test('an unrecognised strategy refuses even when the server says available', () {
      // `available` answers "is the provider built?", not "can THIS app talk to
      // it?". An older app against a newer server must not guess.
      expect(UploadTarget.fromJson(wire(strategy: 'presigned_v2')).canUpload, false);
    });
  });

  group('lesson rows', () {
    test('a lesson with no video carries no provider label', () {
      // Labelling a blank lesson with the school's default reads as "already
      // uploaded", and it gets skipped by the person sent to fix it.
      final row = AuthoringLesson.fromJson({
        'lesson': 'L1',
        'title': 'جمع الكسور',
        'course': 'C1',
        'course_title': 'الرياضيات',
        'has_video': false,
        'provider': null,
        'provider_label': null,
        'duration': 0,
        'is_remedial': 0,
      });

      expect(row.hasVideo, false);
      expect(row.provider, isNull);
      expect(row.providerLabel, isNull);
    });

    test('the row reports the lesson stamp, whatever the tenant default is', () {
      final row = AuthoringLesson.fromJson({
        'lesson': 'L2',
        'title': 'ضرب الكسور',
        'course': 'C1',
        'course_title': 'الرياضيات',
        'has_video': true,
        'provider': 'YouTube',
        'provider_label': 'يوتيوب (غير مُدرج)',
        'duration': 634,
        'is_remedial': 1,
      });

      expect(row.provider, 'YouTube');
      expect(row.duration, 634);
      expect(row.isRemedial, true);
    });

    test('a server that omits the newer fields still yields a usable row', () {
      final row = AuthoringLesson.fromJson({'lesson': 'L3', 'title': 'درس'});

      expect(row.hasVideo, false);
      expect(row.duration, 0);
      expect(row.isRemedial, false);
    });
  });
}
