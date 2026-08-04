import '../../../core/network/api_client.dart';
import '../domain/remedial_models.dart';

class RemedialRepository {
  const RemedialRepository(this.api);

  final ApiClient api;

  /// Returns the student's active remedial path, or null when there is none —
  /// which is the healthy case, not an error.
  Future<RemedialPath?> active({String? assignment}) async {
    final result = await api.get<Map<String, dynamic>?>(
      'student',
      'get_remedial_path',
      query: {'assignment': ?assignment},
    );

    final data = result.data;
    return data == null ? null : RemedialPath.fromJson(data);
  }

  /// Marks one resource done. The server decides the resulting status —
  /// it flips to `Re-Assessment Pending` once everything is complete.
  Future<RemedialStatus> completeResource({
    required String assignment,
    required int rowIdx,
  }) async {
    final result = await api.post<Map<String, dynamic>>(
      'student',
      'complete_remedial_resource',
      body: {'assignment': assignment, 'row_idx': rowIdx},
    );

    return RemedialStatus.fromWire(result.data['status'] as String?);
  }
}
