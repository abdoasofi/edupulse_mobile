import '../../../core/network/api_client.dart';
import '../domain/teacher_models.dart';

class TeacherRepository {
  const TeacherRepository(this.api);

  final ApiClient api;

  /// Omitting `course` lets the server fall back to every course this teacher
  /// is an instructor on — which is what a teacher opening the app wants.
  Future<ClassOverview> classOverview({String? course}) async {
    final result = await api.get<Map<String, dynamic>>(
      'teacher',
      'get_class_overview',
      query: {'course': ?course},
    );
    return ClassOverview.fromJson(result.data);
  }

  /// The default limit is deliberately high: rows are per student *per skill*,
  /// so a class of 25 can legitimately produce 100 of them. A lower cap would
  /// drop whole students off the queue without saying so.
  Future<List<StrugglingEntry>> struggling({String? course, int limit = 100}) async {
    final result = await api.get<List<dynamic>>(
      'teacher',
      'get_struggling_students',
      query: {'course': ?course, 'limit': limit},
    );

    return result.data
        .map((e) => StrugglingEntry.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  Future<MasteryImpact> impact({String? course, String? skill}) async {
    final result = await api.get<Map<String, dynamic>>(
      'teacher',
      'get_mastery_impact',
      query: {'course': ?course, 'skill': ?skill},
    );
    return MasteryImpact.fromJson(result.data);
  }

  // ------------------------------------------------------------ تأليف الفيديو
  /// The lessons this teacher may attach a video to.
  ///
  /// Same `course` convention as above: omitting it means every course they
  /// instruct, which is what a teacher opening the screen wants.
  Future<List<AuthoringLesson>> lessons({String? course}) async {
    final result = await api.get<Map<String, dynamic>>(
      'teacher',
      'get_lessons',
      query: {'course': ?course},
    );

    return ((result.data['lessons'] as List?) ?? const [])
        .map((e) => AuthoringLesson.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  Future<UploadTarget> uploadTarget({String? lesson}) async {
    final result = await api.get<Map<String, dynamic>>(
      'teacher',
      'get_video_upload_target',
      query: {'lesson': ?lesson},
    );
    return UploadTarget.fromJson(result.data);
  }

  /// Point a lesson at a video. `reference` is whatever the strategy produced:
  /// a site path from [uploadToSite], or a link the teacher pasted.
  Future<void> attachVideo({
    required String lesson,
    required String reference,
    int? duration,
  }) => api.post<Map<String, dynamic>>(
    'teacher',
    'attach_video',
    body: {'lesson': lesson, 'reference': reference, 'duration': ?duration},
  );

  Future<void> detachVideo(String lesson) => api.post<Map<String, dynamic>>(
    'teacher',
    'detach_video',
    body: {'lesson': lesson},
  );

  /// Upload to the site's own file store and return the path it is served on.
  ///
  /// Deliberately separate from [attachVideo]: the upload is the slow, failable
  /// half. Bundling them would mean a network blip after a ten-minute upload
  /// discards the file and makes the teacher send it again.
  Future<String> uploadToSite({
    required String path,
    required String filename,
    void Function(int sent, int total)? onProgress,
  }) => api.uploadFile(path: path, filename: filename, onProgress: onProgress);
}
