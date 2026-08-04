/// Models mirroring `edupulse_core.api.v1.student` responses.
library;

/// Frappe serialises the same logical flag as `true`, `1` or `"1"` depending
/// on whether it came from a Python bool, a Check field, or the DB layer.
/// Parse defensively — a `bool as num` cast is a hard crash, not a null.
bool asBool(Object? value) => switch (value) {
  bool b => b,
  num n => n != 0,
  String s => s == '1' || s.toLowerCase() == 'true',
  _ => false,
};

double asDouble(Object? value) => switch (value) {
  num n => n.toDouble(),
  String s => double.tryParse(s) ?? 0,
  _ => 0,
};

int asInt(Object? value) => switch (value) {
  num n => n.toInt(),
  String s => int.tryParse(s) ?? 0,
  _ => 0,
};

enum LessonState {
  locked,
  unlocked,
  completed;

  static LessonState fromWire(String? value) => switch (value) {
    'completed' => LessonState.completed,
    'unlocked' => LessonState.unlocked,
    _ => LessonState.locked,
  };
}

/// How a lesson's video should be played. Mirrors `pedagogy/video_source.py`,
/// so swapping CDN on the server needs no change here.
enum VideoKind {
  hls,
  mp4,
  youtube,
  none;

  static VideoKind fromWire(String? value) => switch (value) {
    'hls' => VideoKind.hls,
    'mp4' => VideoKind.mp4,
    'youtube' => VideoKind.youtube,
    _ => VideoKind.none,
  };
}

class VideoDescriptor {
  const VideoDescriptor({
    required this.kind,
    this.url,
    this.duration = 0,
    this.minWatchPercentage = 90,
    this.watchedPercentage = 0,
    this.resumeAt = 0,
    this.completed = false,
    this.poster,
  });

  final VideoKind kind;
  final String? url;
  final int duration;
  final int minWatchPercentage;
  final double watchedPercentage;
  final double resumeAt;
  final bool completed;
  final String? poster;

  bool get playable => kind != VideoKind.none && (url?.isNotEmpty ?? false);

  double get progress =>
      duration == 0 ? 0 : (watchedPercentage / 100).clamp(0, 1).toDouble();

  factory VideoDescriptor.fromJson(Map<String, dynamic> json) =>
      VideoDescriptor(
        kind: VideoKind.fromWire(json['kind'] as String?),
        url: json['url'] as String?,
        duration: asInt(json['duration']),
        minWatchPercentage: json['min_watch_percentage'] == null
            ? 90
            : asInt(json['min_watch_percentage']),
        watchedPercentage: asDouble(json['watched_percentage']),
        resumeAt: asDouble(json['resume_at']),
        completed: asBool(json['completed']),
        poster: json['poster'] as String?,
      );
}

class QuizGate {
  const QuizGate({
    required this.quiz,
    this.passingPercentage = 80,
    this.attemptsUsed = 0,
    this.maxAttempts,
    this.attemptsLeft,
    this.bestPercentage = 0,
    this.passed = false,
  });

  final String quiz;
  final int passingPercentage;
  final int attemptsUsed;
  final int? maxAttempts;
  final int? attemptsLeft;
  final double bestPercentage;
  final bool passed;

  bool get exhausted =>
      !passed && attemptsLeft != null && attemptsLeft! <= 0;

  factory QuizGate.fromJson(Map<String, dynamic> json) => QuizGate(
    quiz: json['quiz'] as String,
    passingPercentage: json['passing_percentage'] == null
        ? 80
        : asInt(json['passing_percentage']),
    attemptsUsed: asInt(json['attempts_used']),
    maxAttempts: json['max_attempts'] == null ? null : asInt(json['max_attempts']),
    attemptsLeft: json['attempts_left'] == null
        ? null
        : asInt(json['attempts_left']),
    bestPercentage: asDouble(json['best_percentage']),
    passed: asBool(json['passed']),
  );
}

class LessonNode {
  const LessonNode({
    required this.lesson,
    required this.title,
    required this.state,
    required this.video,
    this.chapter,
    this.skill,
    this.quiz,
  });

  final String lesson;
  final String title;
  final LessonState state;
  final VideoDescriptor video;
  final String? chapter;
  final String? skill;
  final QuizGate? quiz;

  bool get isLocked => state == LessonState.locked;

  factory LessonNode.fromJson(Map<String, dynamic> json) {
    final quizJson = json['quiz'];

    return LessonNode(
      lesson: json['lesson'] as String,
      title: (json['title'] as String?) ?? '',
      state: LessonState.fromWire(json['state'] as String?),
      chapter: json['chapter'] as String?,
      skill: json['skill'] as String?,
      video: VideoDescriptor.fromJson(
        Map<String, dynamic>.from(json['video'] as Map? ?? {}),
      ),
      quiz: (quizJson is Map && quizJson['quiz'] != null)
          ? QuizGate.fromJson(Map<String, dynamic>.from(quizJson))
          : null,
    );
  }
}

class CourseMastery {
  const CourseMastery({
    this.mastery = 0,
    this.skills = 0,
    this.mastered = 0,
    this.flagged = 0,
  });

  final double mastery;
  final int skills;
  final int mastered;
  final int flagged;

  factory CourseMastery.fromJson(Map<String, dynamic> json) => CourseMastery(
    mastery: asDouble(json['mastery']),
    skills: asInt(json['skills']),
    mastered: asInt(json['mastered']),
    flagged: asInt(json['flagged']),
  );
}

class LearningPath {
  const LearningPath({
    required this.course,
    required this.title,
    required this.path,
    required this.mastery,
    this.nextLesson,
  });

  final String course;
  final String title;
  final List<LessonNode> path;
  final CourseMastery mastery;
  final String? nextLesson;

  factory LearningPath.fromJson(Map<String, dynamic> json) => LearningPath(
    course: json['course'] as String,
    title: (json['title'] as String?) ?? '',
    nextLesson: json['next_lesson'] as String?,
    path: (json['path'] as List? ?? [])
        .map((e) => LessonNode.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList(),
    mastery: CourseMastery.fromJson(
      Map<String, dynamic>.from(json['mastery'] as Map? ?? {}),
    ),
  );
}

class EnrolledCourse {
  const EnrolledCourse({
    required this.course,
    required this.title,
    this.progress = 0,
    this.mastery = 0,
    this.currentLesson,
  });

  final String course;
  final String title;
  final double progress;
  final double mastery;
  final String? currentLesson;

  factory EnrolledCourse.fromJson(Map<String, dynamic> json) => EnrolledCourse(
    course: json['course'] as String,
    title: (json['title'] as String?) ?? '',
    progress: asDouble(json['progress']),
    mastery: asDouble(json['mastery']),
    currentLesson: json['current_lesson'] as String?,
  );
}

class FlaggedSkill {
  const FlaggedSkill({
    required this.skill,
    this.currentMastery = 0,
    this.consecutiveFailures = 0,
    this.status = '',
  });

  final String skill;
  final double currentMastery;
  final int consecutiveFailures;
  final String status;

  factory FlaggedSkill.fromJson(Map<String, dynamic> json) => FlaggedSkill(
    skill: json['skill'] as String,
    currentMastery: asDouble(json['current_mastery']),
    consecutiveFailures: asInt(json['consecutive_failures']),
    status: (json['status'] as String?) ?? '',
  );
}

class RemedialSummary {
  const RemedialSummary({
    required this.name,
    required this.skill,
    required this.status,
    this.course,
    this.dueOn,
    this.cycleNo = 1,
  });

  final String name;
  final String skill;
  final String status;
  final String? course;
  final String? dueOn;
  final int cycleNo;

  factory RemedialSummary.fromJson(Map<String, dynamic> json) =>
      RemedialSummary(
        name: json['name'] as String,
        skill: (json['skill'] as String?) ?? '',
        status: (json['status'] as String?) ?? '',
        course: json['course'] as String?,
        dueOn: json['due_on'] as String?,
        cycleNo: json['cycle_no'] == null ? 1 : asInt(json['cycle_no']),
      );
}

class StudentDashboard {
  const StudentDashboard({
    required this.courses,
    required this.remedialPending,
    required this.flaggedSkills,
    this.streak = 0,
    this.avgMastery = 0,
  });

  final List<EnrolledCourse> courses;
  final List<RemedialSummary> remedialPending;
  final List<FlaggedSkill> flaggedSkills;
  final int streak;
  final double avgMastery;

  factory StudentDashboard.fromJson(Map<String, dynamic> json) {
    final summary = Map<String, dynamic>.from(json['summary'] as Map? ?? {});

    return StudentDashboard(
      streak: asInt(json['streak']),
      avgMastery: asDouble(summary['avg_mastery']),
      courses: (json['courses'] as List? ?? [])
          .map(
            (e) => EnrolledCourse.fromJson(Map<String, dynamic>.from(e as Map)),
          )
          .toList(),
      remedialPending: (json['remedial_pending'] as List? ?? [])
          .map(
            (e) =>
                RemedialSummary.fromJson(Map<String, dynamic>.from(e as Map)),
          )
          .toList(),
      flaggedSkills: (json['flagged_skills'] as List? ?? [])
          .map(
            (e) => FlaggedSkill.fromJson(Map<String, dynamic>.from(e as Map)),
          )
          .toList(),
    );
  }
}

class LessonDetail {
  const LessonDetail({
    required this.lesson,
    required this.title,
    required this.video,
    this.course,
    this.body,
    this.skill,
    this.instructor,
    this.gateQuiz,
  });

  final String lesson;
  final String title;
  final VideoDescriptor video;
  final String? course;
  final String? body;
  final String? skill;
  final String? instructor;
  final String? gateQuiz;

  factory LessonDetail.fromJson(Map<String, dynamic> json) => LessonDetail(
    lesson: json['lesson'] as String,
    title: (json['title'] as String?) ?? '',
    course: json['course'] as String?,
    body: json['body'] as String?,
    skill: json['skill'] as String?,
    instructor: json['instructor'] as String?,
    gateQuiz: json['gate_quiz'] as String?,
    video: VideoDescriptor.fromJson(
      Map<String, dynamic>.from(json['video'] as Map? ?? {}),
    ),
  );
}
