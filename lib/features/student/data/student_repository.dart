import '../../../core/network/api_client.dart';
import '../domain/student_models.dart';

class StudentRepository {
  const StudentRepository(this.api);

  final ApiClient api;

  Future<StudentDashboard> dashboard() async {
    final result = await api.get<Map<String, dynamic>>(
      'student',
      'get_dashboard',
    );
    return StudentDashboard.fromJson(result.data);
  }

  Future<LearningPath> learningPath(String course) async {
    final result = await api.get<Map<String, dynamic>>(
      'student',
      'get_learning_path',
      query: {'course': course},
    );
    return LearningPath.fromJson(result.data);
  }

  /// Throws [ApiException] with code `CONTENT_LOCKED` when the gate is closed —
  /// the UI turns that into an explanation, not an error toast.
  Future<LessonDetail> lesson(String lesson) async {
    final result = await api.get<Map<String, dynamic>>(
      'student',
      'get_lesson',
      query: {'lesson': lesson},
    );
    return LessonDetail.fromJson(result.data);
  }

  Future<Map<String, dynamic>?> remedialPath({String? assignment}) async {
    final result = await api.get<Map<String, dynamic>?>(
      'student',
      'get_remedial_path',
      query: {'assignment': ?assignment},
    );
    return result.data;
  }

  Future<String> completeRemedialResource(String assignment, int rowIdx) async {
    final result = await api.post<Map<String, dynamic>>(
      'student',
      'complete_remedial_resource',
      body: {'assignment': assignment, 'row_idx': rowIdx},
    );
    return (result.data['status'] as String?) ?? '';
  }

  Future<List<Map<String, dynamic>>> library({
    String? itemType,
    String? search,
    int limit = 20,
    int offset = 0,
  }) async {
    final result = await api.get<Map<String, dynamic>>(
      'student',
      'get_library',
      query: {
        'item_type': ?itemType,
        if (search != null && search.isNotEmpty) 'search': search,
        'limit': limit,
        'offset': offset,
      },
    );

    return (result.data['items'] as List? ?? [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
  }

  Future<List<Map<String, dynamic>>> skillReport() async {
    final result = await api.get<List<dynamic>>('student', 'get_skill_report');
    return result.data.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }
}
