/// Models mirroring `edupulse_core.api.v1.parent`.
///
/// The portal is read-only by design, so nothing here carries a mutation. What
/// it does carry is the one judgement the API leaves to the client: whether a
/// child needs the guardian's attention today, and why.
library;

import '../../student/domain/student_models.dart' show asDouble, asInt;

/// Why a child is surfaced to their guardian, in the order a parent cares.
///
/// A parent opening this app is not auditing a dashboard — they are asking
/// "is my child alright?". Ranking is how the answer fits on one screen.
enum ChildState {
  /// The engine has flagged skills it could not fix on its own.
  needsHelp,

  /// Below the mastery a school expects, but nothing flagged yet.
  behind,

  /// Nothing to raise.
  fine;

  static ChildState of({required int flagged, required double mastery}) {
    if (flagged > 0) return ChildState.needsHelp;
    // Deliberately generous. This decides whether a parent is worried, and a
    // false alarm about a child who is coping costs more trust than it buys.
    if (mastery > 0 && mastery < 50) return ChildState.behind;
    return ChildState.fine;
  }
}

/// One child on the guardian's home screen.
class Child {
  const Child({
    required this.student,
    required this.name,
    required this.avgMastery,
    required this.flaggedCount,
    this.avatar,
    this.gradeLevel,
    this.schoolClass,
    this.relationship,
  });

  final String student;
  final String name;
  final double avgMastery;
  final int flaggedCount;
  final String? avatar;
  final String? gradeLevel;
  final String? schoolClass;
  final String? relationship;

  ChildState get state =>
      ChildState.of(flagged: flaggedCount, mastery: avgMastery);

  /// The class line under the name, or null when the school records neither.
  String? get classLine {
    final parts = [
      if (gradeLevel != null && gradeLevel!.isNotEmpty) gradeLevel!,
      if (schoolClass != null && schoolClass!.isNotEmpty) schoolClass!,
    ];
    return parts.isEmpty ? null : parts.join(' · ');
  }

  factory Child.fromJson(Map<String, dynamic> json) => Child(
    student: (json['student'] as String?) ?? '',
    name:
        (json['name'] as String?)?.trim().isNotEmpty == true
        ? (json['name'] as String).trim()
        : (json['student'] as String?) ?? '',
    avgMastery: asDouble(json['avg_mastery']),
    flaggedCount: asInt(json['flagged_count']),
    avatar: json['avatar'] as String?,
    gradeLevel: json['grade_level'] as String?,
    schoolClass: json['school_class'] as String?,
    relationship: json['relationship'] as String?,
  );
}

/// A lesson the child opened inside the reporting window.
class RecentLesson {
  const RecentLesson({
    required this.lesson,
    required this.lessonTitle,
    required this.courseTitle,
    required this.watchedPercentage,
    required this.isCompleted,
    this.lastPlayedOn,
  });

  final String lesson;
  final String lessonTitle;
  final String courseTitle;
  final double watchedPercentage;
  final bool isCompleted;
  final DateTime? lastPlayedOn;

  factory RecentLesson.fromJson(Map<String, dynamic> json) => RecentLesson(
    lesson: (json['lesson'] as String?) ?? '',
    lessonTitle:
        (json['lesson_title'] as String?) ?? (json['lesson'] as String?) ?? '',
    courseTitle: (json['course_title'] as String?) ?? '',
    watchedPercentage: asDouble(json['watched_percentage']),
    isCompleted: asInt(json['is_completed']) == 1,
    lastPlayedOn: DateTime.tryParse((json['last_played_on'] as String?) ?? ''),
  );
}

/// The reporting window's totals — the four numbers on the summary card.
class ChildTotals {
  const ChildTotals({
    this.lessonsCompleted = 0,
    this.watchMinutes = 0,
    this.quizAttempts = 0,
    this.quizzesPassed = 0,
  });

  final int lessonsCompleted;
  final double watchMinutes;
  final int quizAttempts;
  final int quizzesPassed;

  /// True when the child did nothing at all in the window. Worth its own
  /// sentence: zeroes in four boxes read as a broken screen, not as absence.
  bool get isIdle =>
      lessonsCompleted == 0 &&
      watchMinutes == 0 &&
      quizAttempts == 0;

  factory ChildTotals.fromJson(Map<String, dynamic> json) => ChildTotals(
    lessonsCompleted: asInt(json['lessons_completed']),
    watchMinutes: asDouble(json['watch_minutes']),
    quizAttempts: asInt(json['quiz_attempts']),
    quizzesPassed: asInt(json['quizzes_passed']),
  );
}

class ChildSummary {
  const ChildSummary({
    required this.student,
    required this.studentName,
    required this.periodDays,
    required this.totals,
    required this.recentLessons,
  });

  final String student;
  final String studentName;
  final int periodDays;
  final ChildTotals totals;
  final List<RecentLesson> recentLessons;

  factory ChildSummary.fromJson(Map<String, dynamic> json) => ChildSummary(
    student: (json['student'] as String?) ?? '',
    studentName: (json['student_name'] as String?) ?? '',
    periodDays: asInt(json['period_days']),
    totals: ChildTotals.fromJson(
      Map<String, dynamic>.from((json['totals'] as Map?) ?? const {}),
    ),
    recentLessons: ((json['recent_lessons'] as List?) ?? const [])
        .map((e) => RecentLesson.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList(),
  );
}

/// A skill the engine flagged: the parent's action list, one row at a time.
class FlaggedSkill {
  const FlaggedSkill({
    required this.skill,
    required this.skillName,
    required this.currentMastery,
    required this.consecutiveFailures,
    required this.remedialCount,
    this.subject,
    this.status,
  });

  final String skill;
  final String skillName;
  final double currentMastery;
  final int consecutiveFailures;
  final int remedialCount;
  final String? subject;
  final String? status;

  /// The school's own remedial loop has already run and not resolved it. This
  /// is the line between "the platform is handling it" and "someone should
  /// look" — and it is the only thing a guardian can act on.
  bool get engineExhausted => remedialCount > 0 && consecutiveFailures >= 3;

  factory FlaggedSkill.fromJson(Map<String, dynamic> json) => FlaggedSkill(
    skill: (json['skill'] as String?) ?? '',
    skillName: _skillName(json),
    currentMastery: asDouble(json['current_mastery']),
    consecutiveFailures: asInt(json['consecutive_failures']),
    remedialCount: asInt(json['remedial_count']),
    subject: json['subject'] as String?,
    status: json['status'] as String?,
  );
}

class FlaggedSubjects {
  const FlaggedSubjects({
    required this.flagged,
    required this.bySubject,
    required this.openRemedials,
  });

  final List<FlaggedSkill> flagged;

  /// Grouped as the server grouped them; the screen shows subjects, not a flat
  /// list, because "الرياضيات" is what a parent asks the child about.
  final Map<String, List<FlaggedSkill>> bySubject;

  /// How many remedial paths are currently open. A parent seeing a flagged
  /// skill needs to know whether the school is already on it.
  final int openRemedials;

  bool get needsAttention => flagged.isNotEmpty;

  factory FlaggedSubjects.fromJson(Map<String, dynamic> json) {
    final grouped = <String, List<FlaggedSkill>>{};
    final raw = Map<String, dynamic>.from((json['by_subject'] as Map?) ?? {});

    raw.forEach((subject, rows) {
      grouped[subject] = ((rows as List?) ?? const [])
          .map((e) => FlaggedSkill.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
    });

    return FlaggedSubjects(
      flagged: ((json['flagged'] as List?) ?? const [])
          .map((e) => FlaggedSkill.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList(),
      bySubject: grouped,
      openRemedials: ((json['open_remedials'] as List?) ?? const []).length,
    );
  }
}

/// One skill's before-and-after — the "is it working?" row.
class MasteryTrend {
  const MasteryTrend({
    required this.skill,
    required this.skillName,
    required this.baseline,
    required this.current,
    required this.gain,
    required this.remedialCount,
    this.status,
  });

  final String skill;

  /// What the row is labelled with. `skill` is a curriculum code —
  /// MATH-G7-FRAC-ADD — and a guardian reading one learns nothing.
  final String skillName;
  final double baseline;
  final double current;
  final double gain;
  final int remedialCount;
  final String? status;

  /// Only skills the child actually moved on are worth showing a parent. A row
  /// reading 0 → 0 says nothing except that the topic has not started.
  bool get hasMoved => baseline > 0 || current > 0;

  factory MasteryTrend.fromJson(Map<String, dynamic> json) => MasteryTrend(
    skill: (json['skill'] as String?) ?? '',
    skillName: _skillName(json),
    baseline: asDouble(json['baseline_mastery']),
    current: asDouble(json['current_mastery']),
    gain: asDouble(json['mastery_gain']),
    remedialCount: asInt(json['remedial_count']),
    status: json['status'] as String?,
  );
}

/// Arabic name, English name, then the code — in that order, because this
/// screen has no audience but Arabic readers and a code is the last resort
/// rather than the default.
String _skillName(Map<String, dynamic> json) {
  for (final key in ['skill_name_ar', 'skill_name', 'skill']) {
    final value = (json[key] as String?)?.trim();
    if (value != null && value.isNotEmpty) return value;
  }
  return '';
}
