import '../../../core/network/api_client.dart';
import '../domain/admin_models.dart';

class AdminRepository {
  const AdminRepository(this.api);

  final ApiClient api;

  /// Leadership KPIs. The endpoint lives in the `teacher` module because it is
  /// open to every staff role — a supervisor sees the same figures.
  Future<ExecutiveKpis> kpis({int days = 30}) async {
    final result = await api.get<Map<String, dynamic>>(
      'teacher',
      'get_executive_kpis',
      query: {'days': days},
    );
    return ExecutiveKpis.fromJson(result.data);
  }
}
