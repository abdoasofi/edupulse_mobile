/// Models mirroring `edupulse_core.api.v1.student.get_remedial_path`.
library;

import 'package:flutter/material.dart';

import '../../student/domain/student_models.dart' show asBool, asDouble, asInt;

/// Resource kinds the remedial engine can assign. Mirrors the Select options
/// on `EduPulse Remedial Resource`.
enum RemedialResourceType {
  alternativeVideo('Alternative Video'),
  boosterExercise('Booster Exercise'),
  summary('Summary'),
  mindMap('Mind Map'),
  questionBank('Question Bank'),
  liveSession('Live Session'),
  unknown('');

  const RemedialResourceType(this.wire);

  final String wire;

  static RemedialResourceType fromWire(String? value) =>
      RemedialResourceType.values.firstWhere(
        (t) => t.wire == value,
        orElse: () => RemedialResourceType.unknown,
      );

  String get label => switch (this) {
    RemedialResourceType.alternativeVideo => 'شرح بمعلّم آخر',
    RemedialResourceType.boosterExercise => 'تمارين داعمة',
    RemedialResourceType.summary => 'ملخص',
    RemedialResourceType.mindMap => 'خريطة ذهنية',
    RemedialResourceType.questionBank => 'بنك أسئلة',
    RemedialResourceType.liveSession => 'جلسة مباشرة',
    RemedialResourceType.unknown => 'مورد',
  };

  IconData get icon => switch (this) {
    RemedialResourceType.alternativeVideo => Icons.switch_account,
    RemedialResourceType.boosterExercise => Icons.fitness_center,
    RemedialResourceType.summary => Icons.article_outlined,
    RemedialResourceType.mindMap => Icons.account_tree_outlined,
    RemedialResourceType.questionBank => Icons.quiz_outlined,
    RemedialResourceType.liveSession => Icons.videocam_outlined,
    RemedialResourceType.unknown => Icons.circle_outlined,
  };
}

class RemedialResource {
  const RemedialResource({
    required this.idx,
    required this.type,
    required this.isCompleted,
    this.lesson,
    this.quiz,
    this.libraryItem,
    this.instructor,
    this.instructorName,
  });

  final int idx;
  final RemedialResourceType type;
  final bool isCompleted;
  final String? lesson;
  final String? quiz;
  final String? libraryItem;
  final String? instructor;
  final String? instructorName;

  /// Where tapping this resource should take the student.
  String? get route {
    if (lesson != null) return '/student/home/lesson/$lesson';
    if (quiz != null) return '/student/home/quiz/$quiz';
    return null;
  }

  bool get isOpenable => route != null;

  factory RemedialResource.fromJson(Map<String, dynamic> json) =>
      RemedialResource(
        idx: asInt(json['idx']),
        type: RemedialResourceType.fromWire(json['type'] as String?),
        isCompleted: asBool(json['is_completed']),
        lesson: json['lesson'] as String?,
        quiz: json['quiz'] as String?,
        libraryItem: json['library_item'] as String?,
        instructor: json['instructor'] as String?,
        instructorName: json['instructor_name'] as String?,
      );
}

enum RemedialStatus {
  // No damma on the meem — at labelSmall the diacritic collides with the
  // letter and the chip reads as "فسند".
  assigned('Assigned', 'مسند'),
  inProgress('In Progress', 'قيد التنفيذ'),
  reassessmentPending('Re-Assessment Pending', 'بانتظار إعادة التقييم'),
  mastered('Mastered', 'متقن'),
  escalated('Escalated', 'مُصعَّد'),
  cancelled('Cancelled', 'ملغى');

  const RemedialStatus(this.wire, this.label);

  final String wire;
  final String label;

  static RemedialStatus fromWire(String? value) => RemedialStatus.values
      .firstWhere((s) => s.wire == value, orElse: () => RemedialStatus.assigned);
}

class RemedialPath {
  const RemedialPath({
    required this.name,
    required this.skill,
    required this.skillName,
    required this.status,
    required this.resources,
    required this.allResourcesDone,
    this.course,
    this.dueOn,
    this.cycleNo = 1,
    this.preScore = 0,
    this.reassessmentQuiz,
  });

  final String name;
  final String skill;
  final String skillName;
  final RemedialStatus status;
  final List<RemedialResource> resources;
  final bool allResourcesDone;
  final String? course;
  final String? dueOn;
  final int cycleNo;
  final double preScore;
  final String? reassessmentQuiz;

  int get completedCount => resources.where((r) => r.isCompleted).length;

  double get progress =>
      resources.isEmpty ? 0 : completedCount / resources.length;

  /// The re-assessment opens only once every resource is done — the same rule
  /// the server enforces when it flips status to `Re-Assessment Pending`.
  bool get canReassess => allResourcesDone && reassessmentQuiz != null;

  bool get isOverdue {
    if (dueOn == null) return false;
    final due = DateTime.tryParse(dueOn!);
    return due != null && DateTime.now().isAfter(due);
  }

  factory RemedialPath.fromJson(Map<String, dynamic> json) => RemedialPath(
    name: json['name'] as String,
    skill: (json['skill'] as String?) ?? '',
    skillName: (json['skill_name'] as String?) ?? (json['skill'] as String?) ?? '',
    status: RemedialStatus.fromWire(json['status'] as String?),
    course: json['course'] as String?,
    dueOn: json['due_on'] as String?,
    cycleNo: json['cycle_no'] == null ? 1 : asInt(json['cycle_no']),
    preScore: asDouble(json['pre_score']),
    reassessmentQuiz: json['reassessment_quiz'] as String?,
    allResourcesDone: asBool(json['all_resources_done']),
    resources: (json['resources'] as List? ?? [])
        .map(
          (e) => RemedialResource.fromJson(Map<String, dynamic>.from(e as Map)),
        )
        .toList(),
  );
}
