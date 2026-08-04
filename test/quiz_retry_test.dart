import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:edupulse_mobile/app/providers.dart';
import 'package:edupulse_mobile/core/network/api_client.dart';
import 'package:edupulse_mobile/features/quiz/data/quiz_repository.dart';
import 'package:edupulse_mobile/features/quiz/domain/quiz_models.dart';
import 'package:edupulse_mobile/features/quiz/presentation/quiz_screen.dart';

/// Retrying must hand the student a blank attempt.
///
/// The screen keeps the question index and the chosen answers in State, and
/// the result screen is pushed *on top* of it — so popping back lands on a
/// live screen still holding the previous attempt. Left alone that shows the
/// last question with the old answers pre-selected, and bills the new attempt
/// for time spent on the old one.
void main() {
  const quizId = 'QUIZ-1';

  Future<void> pumpQuiz(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          quizRepositoryProvider.overrideWithValue(_FakeQuizRepository()),
        ],
        child: const MaterialApp(
          home: QuizScreen(quiz: quizId),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  int unselectedOptions() =>
      find.byIcon(Icons.radio_button_unchecked).evaluate().length;

  testWidgets('retry returns to the first question with answers cleared', (
    tester,
  ) async {
    await pumpQuiz(tester);

    expect(find.text('السؤال 1 من 3'), findsOneWidget);

    // Work through to the last question, answering as we go.
    await tester.tap(find.text('1/2'));
    await tester.pump();
    expect(unselectedOptions(), 1, reason: 'اختيار واحد من اثنين');

    await tester.tap(find.text('التالي'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('التالي'));
    await tester.pumpAndSettle();
    expect(find.text('السؤال 3 من 3'), findsOneWidget);

    // Submit — confirmation dialog, then the result screen.
    await tester.tap(find.text('سلّم الاختبار'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('سلّم'));
    await tester.pumpAndSettle();

    expect(find.text('لم تجتز هذه المرة'), findsOneWidget);

    await tester.tap(find.text('إعادة المحاولة'));
    await tester.pumpAndSettle();

    expect(
      find.text('السؤال 1 من 3'),
      findsOneWidget,
      reason: 'إعادة المحاولة تبدأ من السؤال الأول لا الأخير',
    );
    expect(
      unselectedOptions(),
      2,
      reason: 'إجابات المحاولة السابقة لا تبقى مُحدَّدة',
    );
  });
}

Map<String, dynamic> _question(int n) => {
  'name': 'Q$n',
  'question': 'سؤال $n',
  'type': 'Choices',
  'options': [
    {'idx': 1, 'text': '1/2'},
    {'idx': 2, 'text': '2/4'},
  ],
};

/// `implements` rather than `extends` so the fake needs no [ApiClient] — and
/// so a new method on the repository fails the build instead of silently
/// falling through to a real network call.
class _FakeQuizRepository implements QuizRepository {
  @override
  ApiClient get api => throw UnimplementedError();

  @override
  Future<QuizPaper> paper(String quiz) async => QuizPaper.fromJson({
    'quiz': quiz,
    'title': 'اختبار — جمع الكسور',
    'passing_percentage': 80,
    'total_marks': 3,
    'questions': [_question(1), _question(2), _question(3)],
    'attempt_state': {'attempts_used': 0, 'attempts_left': null},
  });

  @override
  Future<QuizResult> submit({
    required String quiz,
    required List<QuizAnswer> answers,
    String? device,
    double? timeTaken,
  }) async => QuizResult.fromJson({
    'submission': 'SUB-1',
    'percentage': 33.3,
    'passing_percentage': 80,
    'passed': false,
    'score': 1,
    'score_out_of': 3,
    'attempt_no': 1,
    'next_action': {'action': 'retry', 'route': '/student/quiz'},
    'review': [],
  });

  @override
  Future<List<Map<String, dynamic>>> attempts(String quiz) async => [];
}
