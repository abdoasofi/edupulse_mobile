/// Models mirroring `edupulse_core.api.v1.quiz`.
///
/// Note what is absent: no `isCorrect`, no `explanation` on options. The
/// server strips them — grading never happens on the device.
library;

import '../../student/domain/student_models.dart' show asBool, asDouble, asInt;

class QuizOption {
  const QuizOption({required this.idx, required this.text});

  final int idx;
  final String text;

  factory QuizOption.fromJson(Map<String, dynamic> json) => QuizOption(
    idx: asInt(json['idx']),
    text: (json['text'] as String?) ?? '',
  );
}

class QuizQuestion {
  const QuizQuestion({
    required this.name,
    required this.question,
    required this.type,
    required this.options,
    this.multiple = false,
    this.marks = 1,
    this.skill,
  });

  final String name;
  final String question;
  final String type;
  final List<QuizOption> options;
  final bool multiple;
  final int marks;
  final String? skill;

  bool get isFreeText => type == 'User Input' || type == 'Open Ended';

  factory QuizQuestion.fromJson(Map<String, dynamic> json) => QuizQuestion(
    name: json['name'] as String,
    question: (json['question'] as String?) ?? '',
    type: (json['type'] as String?) ?? 'Choices',
    multiple: asBool(json['multiple']),
    marks: json['marks'] == null ? 1 : asInt(json['marks']),
    skill: json['skill'] as String?,
    options: (json['options'] as List? ?? [])
        .map((e) => QuizOption.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList(),
  );
}

class QuizPaper {
  const QuizPaper({
    required this.quiz,
    required this.title,
    required this.questions,
    this.passingPercentage = 80,
    this.totalMarks = 0,
    this.duration,
    this.showAnswers = false,
    this.attemptsUsed = 0,
    this.attemptsLeft,
    this.skill,
  });

  final String quiz;
  final String title;
  final List<QuizQuestion> questions;
  final int passingPercentage;
  final int totalMarks;
  final String? duration;
  final bool showAnswers;
  final int attemptsUsed;
  final int? attemptsLeft;
  final String? skill;

  factory QuizPaper.fromJson(Map<String, dynamic> json) {
    final state = Map<String, dynamic>.from(
      json['attempt_state'] as Map? ?? {},
    );

    return QuizPaper(
      quiz: json['quiz'] as String,
      title: (json['title'] as String?) ?? '',
      passingPercentage: json['passing_percentage'] == null
          ? 80
          : asInt(json['passing_percentage']),
      totalMarks: asInt(json['total_marks']),
      duration: json['duration']?.toString(),
      showAnswers: asBool(json['show_answers']),
      skill: json['skill'] as String?,
      attemptsUsed: asInt(state['attempts_used']),
      attemptsLeft: state['attempts_left'] == null
          ? null
          : asInt(state['attempts_left']),
      questions: (json['questions'] as List? ?? [])
          .map(
            (e) => QuizQuestion.fromJson(Map<String, dynamic>.from(e as Map)),
          )
          .toList(),
    );
  }
}

/// What the client should do after submitting — decided server-side.
class NextAction {
  const NextAction({required this.action, required this.route, this.payload});

  final String action;
  final String route;
  final String? payload;

  bool get isRemedial => action == 'remedial';
  bool get isRetry => action == 'retry';

  factory NextAction.fromJson(Map<String, dynamic> json) => NextAction(
    action: (json['action'] as String?) ?? 'continue',
    route: (json['route'] as String?) ?? '/student/home',
    payload: (json['assignment'] ?? json['quiz']) as String?,
  );
}

class QuizResult {
  const QuizResult({
    required this.submission,
    required this.percentage,
    required this.passingPercentage,
    required this.passed,
    required this.nextAction,
    this.score = 0,
    this.scoreOutOf = 0,
    this.attemptNo = 1,
    this.remedialAssignment,
    this.review = const [],
  });

  final String submission;
  final double percentage;
  final int passingPercentage;
  final bool passed;
  final NextAction nextAction;
  final double score;
  final double scoreOutOf;
  final int attemptNo;
  final String? remedialAssignment;
  final List<ReviewItem> review;

  factory QuizResult.fromJson(Map<String, dynamic> json) => QuizResult(
    submission: json['submission'] as String,
    percentage: asDouble(json['percentage']),
    passingPercentage: json['passing_percentage'] == null
        ? 80
        : asInt(json['passing_percentage']),
    passed: asBool(json['passed']),
    score: asDouble(json['score']),
    scoreOutOf: asDouble(json['score_out_of']),
    attemptNo: json['attempt_no'] == null ? 1 : asInt(json['attempt_no']),
    remedialAssignment: json['remedial_assignment'] as String?,
    nextAction: NextAction.fromJson(
      Map<String, dynamic>.from(json['next_action'] as Map? ?? {}),
    ),
    review: (json['review'] as List? ?? [])
        .map((e) => ReviewItem.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList(),
  );
}

/// A correct option plus the worked method behind it.
class CorrectOption {
  const CorrectOption({required this.text, this.explanation});

  final String text;
  final String? explanation;

  factory CorrectOption.fromJson(Map<String, dynamic> json) => CorrectOption(
    text: json['text']?.toString() ?? '',
    explanation: json['explanation'] as String?,
  );
}

class ReviewItem {
  const ReviewItem({
    required this.question,
    required this.isCorrect,
    this.yourAnswer,
    this.yourExplanation,
    this.correctOptions = const [],
  });

  final String question;
  final bool isCorrect;
  final String? yourAnswer;

  /// Why the option the student picked was wrong — the misconception, named.
  final String? yourExplanation;
  final List<CorrectOption> correctOptions;

  String get correctText => correctOptions.map((o) => o.text).join('، ');

  /// The method behind the right answer, when the server sent one.
  String? get correctExplanation => correctOptions
      .map((o) => o.explanation)
      .firstWhere((e) => (e ?? '').trim().isNotEmpty, orElse: () => null);

  factory ReviewItem.fromJson(Map<String, dynamic> json) => ReviewItem(
    question: (json['question'] as String?) ?? '',
    isCorrect: asBool(json['is_correct']),
    yourAnswer: json['your_answer'] as String?,
    yourExplanation: json['your_explanation'] as String?,
    correctOptions: (json['correct_options'] as List? ?? [])
        .map((e) => CorrectOption.fromJson(Map<String, dynamic>.from(e as Map)))
        .where((o) => o.text.isNotEmpty)
        .toList(),
  );
}

/// One question's answer, built up as the student works through the paper.
class QuizAnswer {
  const QuizAnswer({required this.question, this.selected = const [], this.text});

  final String question;
  final List<int> selected;
  final String? text;

  bool get isAnswered => selected.isNotEmpty || (text?.trim().isNotEmpty ?? false);

  Map<String, dynamic> toJson() => {
    'question': question,
    if (selected.isNotEmpty) 'selected': selected,
    if (text != null && text!.trim().isNotEmpty) 'text': text!.trim(),
  };

  QuizAnswer copyWith({List<int>? selected, String? text}) => QuizAnswer(
    question: question,
    selected: selected ?? this.selected,
    text: text ?? this.text,
  );
}
