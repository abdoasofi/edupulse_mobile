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
}
