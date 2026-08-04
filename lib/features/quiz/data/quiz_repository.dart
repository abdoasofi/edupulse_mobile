import 'dart:convert';

import '../../../core/network/api_client.dart';
import '../domain/quiz_models.dart';

class QuizRepository {
  const QuizRepository(this.api);

  final ApiClient api;

  /// Fetch a paper. Throws `CONTENT_LOCKED` / `ATTEMPTS_EXHAUSTED` when the
  /// student may not sit it — both are pedagogical states, not failures.
  Future<QuizPaper> paper(String quiz) async {
    final result = await api.get<Map<String, dynamic>>(
      'quiz',
      'get_quiz',
      query: {'quiz': quiz},
    );
    return QuizPaper.fromJson(result.data);
  }

  Future<QuizResult> submit({
    required String quiz,
    required List<QuizAnswer> answers,
    String? device,
    double? timeTaken,
  }) async {
    final result = await api.post<Map<String, dynamic>>(
      'quiz',
      'submit_quiz',
      body: {
        'quiz': quiz,
        'answers': jsonEncode(answers.map((a) => a.toJson()).toList()),
        'device': ?device,
        'time_taken': ?timeTaken,
      },
    );

    return QuizResult.fromJson(result.data);
  }

  Future<List<Map<String, dynamic>>> attempts(String quiz) async {
    final result = await api.get<Map<String, dynamic>>(
      'quiz',
      'get_attempts',
      query: {'quiz': quiz},
    );

    return (result.data['attempts'] as List? ?? [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
  }
}
