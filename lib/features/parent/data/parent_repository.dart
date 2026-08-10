import '../../../core/network/api_client.dart';
import '../domain/parent_models.dart';

/// بوابة ولي الأمر — read-only throughout.
///
/// Every call is scoped to one child and the server checks the guardian link
/// on each of them, so nothing here caches a child id across requests.
class ParentRepository {
  const ParentRepository(this.api);

  final ApiClient api;

  Future<List<Child>> children() async {
    final result = await api.get<List<dynamic>>('parent', 'get_children');

    return result.data
        .map((e) => Child.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  /// The window is the parent's question, not a setting: "this week" is what
  /// they open the app asking, and a longer one is a deliberate second look.
  Future<ChildSummary> summary(String student, {int days = 7}) async {
    final result = await api.get<Map<String, dynamic>>(
      'parent',
      'get_child_summary',
      query: {'student': student, 'days': days},
    );
    return ChildSummary.fromJson(result.data);
  }

  Future<FlaggedSubjects> flagged(String student) async {
    final result = await api.get<Map<String, dynamic>>(
      'parent',
      'get_flagged_subjects',
      query: {'student': student},
    );
    return FlaggedSubjects.fromJson(result.data);
  }

  Future<List<MasteryTrend>> trend(String student, {String? course}) async {
    final result = await api.get<List<dynamic>>(
      'parent',
      'get_child_mastery_trend',
      query: {'student': student, 'course': ?course},
    );

    return result.data
        .map((e) => MasteryTrend.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }
}
