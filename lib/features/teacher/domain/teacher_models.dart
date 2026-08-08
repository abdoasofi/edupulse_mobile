/// Models mirroring `edupulse_core.api.v1.teacher`.
library;

import 'package:flutter/material.dart';

import '../../student/domain/student_models.dart' show asDouble, asInt;

/// One student's roll-up across every skill in the class.
class StudentMastery {
  const StudentMastery({
    required this.student,
    required this.studentName,
    required this.avgMastery,
    required this.avgBaseline,
    required this.gain,
    required this.mastered,
    required this.flagged,
    required this.skills,
  });

  final String student;
  final String studentName;
  final double avgMastery;
  final double avgBaseline;
  final double gain;
  final int mastered;
  final int flagged;
  final int skills;

  bool get isStruggling => flagged > 0;

  factory StudentMastery.fromJson(Map<String, dynamic> json) => StudentMastery(
    student: (json['student'] as String?) ?? '',
    studentName:
        (json['student_name'] as String?) ?? (json['student'] as String?) ?? '',
    avgMastery: asDouble(json['avg_mastery']),
    avgBaseline: asDouble(json['avg_baseline']),
    gain: asDouble(json['gain']),
    // SUM() comes back as a float from MariaDB — 4.0, not 4.
    mastered: asInt(json['mastered']),
    flagged: asInt(json['flagged']),
    skills: asInt(json['skills']),
  );
}

class ClassStats {
  const ClassStats({
    this.count = 0,
    this.avgMastery = 0,
    this.avgGain = 0,
    this.struggling = 0,
  });

  final int count;
  final double avgMastery;
  final double avgGain;
  final int struggling;

  factory ClassStats.fromJson(Map<String, dynamic> json) => ClassStats(
    count: asInt(json['count']),
    avgMastery: asDouble(json['avg_mastery']),
    avgGain: asDouble(json['avg_gain']),
    struggling: asInt(json['struggling']),
  );
}

class ClassOverview {
  const ClassOverview({
    required this.students,
    required this.stats,
    this.course,
  });

  final List<StudentMastery> students;
  final ClassStats stats;
  final String? course;

  factory ClassOverview.fromJson(Map<String, dynamic> json) => ClassOverview(
    course: json['course'] as String?,
    stats: ClassStats.fromJson(
      Map<String, dynamic>.from(json['class_stats'] as Map? ?? {}),
    ),
    students: (json['students'] as List? ?? [])
        .map((e) => StudentMastery.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList(),
  );
}

/// How urgent a flagged student is — the teacher's triage.
///
/// The distinction that matters is not "how low is the score" but **whether
/// the automated remedial loop has already been tried**. A student the system
/// has not helped yet needs no teacher; a student it helped twice and who is
/// still failing is precisely where a human has to step in. A flat list sorted
/// by score hides that difference completely.
enum Triage {
  /// The engine has not intervened yet — it will, on its own.
  automatic('المعالجة الآلية ستُسند تلقائياً', Color(0xFF3B82F6)),

  /// One remedial cycle ran and the student is still flagged.
  watch('دورة علاجية جرت — تحتاج متابعة', Color(0xFFF59E0B)),

  /// The engine has tried repeatedly and failed. This is the teacher's queue.
  intervene('المعالجة الآلية لم تكفِ — تدخّل بشري', Color(0xFFDC2626));

  const Triage(this.label, this.colour);

  final String label;
  final Color colour;

  static Triage of(int remedialCount) => switch (remedialCount) {
    0 => Triage.automatic,
    1 => Triage.watch,
    _ => Triage.intervene,
  };
}

class StrugglingEntry {
  const StrugglingEntry({
    required this.student,
    required this.studentName,
    required this.skill,
    required this.skillName,
    required this.currentMastery,
    required this.consecutiveFailures,
    required this.remedialCount,
    this.subject,
    this.lastAttemptOn,
  });

  final String student;
  final String studentName;
  final String skill;
  final String skillName;
  final double currentMastery;
  final int consecutiveFailures;
  final int remedialCount;
  final String? subject;
  final DateTime? lastAttemptOn;

  Triage get triage => Triage.of(remedialCount);

  factory StrugglingEntry.fromJson(Map<String, dynamic> json) =>
      StrugglingEntry(
        student: (json['student'] as String?) ?? '',
        studentName:
            (json['student_name'] as String?) ??
            (json['student'] as String?) ??
            '',
        skill: (json['skill'] as String?) ?? '',
        // Arabic name when the skill has one; the code is a last resort so a
        // half-configured tenant still shows something identifiable.
        skillName:
            (json['skill_name_ar'] as String?) ??
            (json['skill_name'] as String?) ??
            (json['skill'] as String?) ??
            '',
        subject: json['subject'] as String?,
        currentMastery: asDouble(json['current_mastery']),
        consecutiveFailures: asInt(json['consecutive_failures']),
        remedialCount: asInt(json['remedial_count']),
        lastAttemptOn: DateTime.tryParse(
          (json['last_attempt_on'] as String?) ?? '',
        ),
      );
}

class ImpactRow {
  const ImpactRow({
    required this.skill,
    required this.skillName,
    required this.students,
    required this.preMastery,
    required this.postMastery,
    required this.gain,
    required this.masteryRate,
    required this.mastered,
    required this.remedialCycles,
  });

  final String skill;
  final String skillName;
  final int students;
  final double preMastery;
  final double postMastery;
  final double gain;
  final double masteryRate;
  final int mastered;
  final int remedialCycles;

  factory ImpactRow.fromJson(Map<String, dynamic> json) => ImpactRow(
    skill: (json['skill'] as String?) ?? '',
    skillName:
        (json['skill_name_ar'] as String?) ??
        (json['skill_name'] as String?) ??
        (json['skill'] as String?) ??
        '',
    students: asInt(json['students']),
    preMastery: asDouble(json['pre_mastery']),
    postMastery: asDouble(json['post_mastery']),
    gain: asDouble(json['gain']),
    masteryRate: asDouble(json['mastery_rate']),
    mastered: asInt(json['mastered']),
    remedialCycles: asInt(json['remedial_cycles']),
  );
}

class MasteryImpact {
  const MasteryImpact({
    required this.rows,
    this.pre = 0,
    this.post = 0,
    this.gain = 0,
  });

  final List<ImpactRow> rows;
  final double pre;
  final double post;
  final double gain;

  factory MasteryImpact.fromJson(Map<String, dynamic> json) {
    final overall = Map<String, dynamic>.from(json['overall'] as Map? ?? {});

    return MasteryImpact(
      pre: asDouble(overall['pre']),
      post: asDouble(overall['post']),
      gain: asDouble(overall['gain']),
      rows: (json['rows'] as List? ?? [])
          .map((e) => ImpactRow.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList(),
    );
  }
}

// --------------------------------------------------------------- تأليف الفيديو
/// How this school expects a video to be attached.
///
/// The authoring UI renders from [strategy] alone and never learns a provider
/// name. That is the whole point of the video-delivery layer: adding a sixth
/// provider is a handler on the server, not a change to this screen.
enum UploadStrategy {
  /// Upload the file to the site itself.
  siteFile('site_file'),

  /// Paste a link — YouTube, or a URL the school already hosts.
  externalUrl('external_url'),

  /// Presigned PUT straight to the provider. No provider ships this yet.
  directPost('direct_post'),

  /// A strategy this build predates. Offer nothing rather than the wrong form.
  unknown('');

  const UploadStrategy(this.wire);

  final String wire;

  static UploadStrategy fromWire(String? value) => UploadStrategy.values
      .firstWhere((s) => s.wire == value, orElse: () => UploadStrategy.unknown);
}

class UploadTarget {
  const UploadTarget({
    required this.provider,
    required this.providerLabel,
    required this.strategy,
    required this.hint,
    required this.accepts,
    required this.available,
    required this.offlineAllowed,
  });

  final String provider;
  final String providerLabel;
  final UploadStrategy strategy;
  final String hint;
  final List<String> accepts;

  /// False for a provider whose handler is not written yet. The form is shown
  /// disabled rather than hidden: a teacher who cannot find the upload button
  /// files a bug, one who is told the school's provider is not ready yet does
  /// something about it.
  final bool available;
  final bool offlineAllowed;

  bool get canUpload => available && strategy != UploadStrategy.unknown;

  factory UploadTarget.fromJson(Map<String, dynamic> json) => UploadTarget(
    provider: (json['provider'] as String?) ?? '',
    providerLabel: (json['provider_label'] as String?) ?? '',
    strategy: UploadStrategy.fromWire(json['strategy'] as String?),
    hint: (json['hint_ar'] as String?) ?? '',
    accepts: ((json['accepts'] as List?) ?? const [])
        .map((e) => e.toString())
        .toList(),
    available: json['available'] == true,
    offlineAllowed: json['offline_allowed'] == true,
  );
}

/// One row of the authoring list: a lesson and whatever video it already has.
class AuthoringLesson {
  const AuthoringLesson({
    required this.lesson,
    required this.title,
    required this.course,
    required this.courseTitle,
    required this.skill,
    required this.isRemedial,
    required this.hasVideo,
    required this.provider,
    required this.providerLabel,
    required this.duration,
  });

  final String lesson;
  final String title;
  final String course;
  final String courseTitle;
  final String? skill;
  final bool isRemedial;
  final bool hasVideo;

  /// The lesson's own stamp, not the school's current default. A library
  /// uploaded to YouTube and then re-pointed at Drive still plays from
  /// YouTube, and this is what says so.
  final String? provider;
  final String? providerLabel;
  final int duration;

  factory AuthoringLesson.fromJson(Map<String, dynamic> json) =>
      AuthoringLesson(
        lesson: (json['lesson'] as String?) ?? '',
        title: (json['title'] as String?) ?? '',
        course: (json['course'] as String?) ?? '',
        courseTitle: (json['course_title'] as String?) ?? '',
        skill: json['skill'] as String?,
        isRemedial: asInt(json['is_remedial']) == 1,
        hasVideo: json['has_video'] == true,
        provider: json['provider'] as String?,
        providerLabel: json['provider_label'] as String?,
        duration: asInt(json['duration']),
      );
}
