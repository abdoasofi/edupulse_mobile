/// Models mirroring `edupulse_core.api.v1.teacher.get_executive_kpis`
/// and the `licence` block of `auth.bootstrap`.
library;

import 'package:flutter/material.dart';

import '../../student/domain/student_models.dart' show asBool, asDouble, asInt;

class StudentEngagement {
  const StudentEngagement({
    this.total = 0,
    this.active = 0,
    this.engagementRate = 0,
  });

  final int total;
  final int active;
  final double engagementRate;

  factory StudentEngagement.fromJson(Map<String, dynamic> json) =>
      StudentEngagement(
        total: asInt(json['total']),
        active: asInt(json['active']),
        engagementRate: asDouble(json['engagement_rate']),
      );
}

class QuizStats {
  const QuizStats({
    this.attempts = 0,
    this.attemptsPassed = 0,
    this.attemptPassRate = 0,
    this.avgScore = 0,
  });

  final int attempts;
  final int attemptsPassed;

  /// Attempt-level, not student-level. Every deliberate retry on the way to
  /// mastery counts as a failure here, so this number is *supposed* to look
  /// low — see [MasteryStats] for what the school actually achieved.
  final double attemptPassRate;
  final double avgScore;

  factory QuizStats.fromJson(Map<String, dynamic> json) => QuizStats(
    attempts: asInt(json['attempts']),
    attemptsPassed: asInt(json['attempts_passed']),
    attemptPassRate: asDouble(json['attempt_pass_rate']),
    avgScore: asDouble(json['avg_score']),
  );
}

class MasteryStats {
  const MasteryStats({
    this.pre = 0,
    this.post = 0,
    this.gain = 0,
    this.measured = 0,
    this.mastered = 0,
    this.masteryRate = 0,
    this.firstTime = 0,
    this.firstTimeRate = 0,
    this.recovered = 0,
    this.recoveryRate = 0,
  });

  final double pre;
  final double post;
  final double gain;
  final int measured;
  final int mastered;
  final double masteryRate;

  /// Mastered on the first attempt — no help needed.
  final int firstTime;
  final double firstTimeRate;

  /// Failed first, mastered after the remedial loop. This is the number that
  /// only exists because the platform is there.
  final int recovered;
  final double recoveryRate;

  factory MasteryStats.fromJson(Map<String, dynamic> json) => MasteryStats(
    pre: asDouble(json['pre']),
    post: asDouble(json['post']),
    gain: asDouble(json['gain']),
    measured: asInt(json['measured']),
    mastered: asInt(json['mastered']),
    masteryRate: asDouble(json['mastery_rate']),
    firstTime: asInt(json['first_time']),
    firstTimeRate: asDouble(json['first_time_rate']),
    recovered: asInt(json['recovered']),
    recoveryRate: asDouble(json['recovery_rate']),
  );
}

class RemedialStats {
  const RemedialStats({
    this.triggered = 0,
    this.resolved = 0,
    this.escalated = 0,
    this.effectiveness = 0,
    this.avgGain = 0,
  });

  final int triggered;
  final int resolved;
  final int escalated;
  final double effectiveness;
  final double avgGain;

  factory RemedialStats.fromJson(Map<String, dynamic> json) => RemedialStats(
    triggered: asInt(json['triggered']),
    resolved: asInt(json['resolved']),
    escalated: asInt(json['escalated']),
    effectiveness: asDouble(json['effectiveness']),
    avgGain: asDouble(json['avg_gain']),
  );
}

class ExecutiveKpis {
  const ExecutiveKpis({
    required this.periodDays,
    required this.students,
    required this.quizzes,
    required this.mastery,
    required this.remedial,
  });

  final int periodDays;
  final StudentEngagement students;
  final QuizStats quizzes;
  final MasteryStats mastery;
  final RemedialStats remedial;

  bool get hasData => mastery.measured > 0;

  factory ExecutiveKpis.fromJson(Map<String, dynamic> json) {
    Map<String, dynamic> block(String key) =>
        Map<String, dynamic>.from(json[key] as Map? ?? {});

    return ExecutiveKpis(
      periodDays: json['period_days'] == null ? 30 : asInt(json['period_days']),
      students: StudentEngagement.fromJson(block('students')),
      quizzes: QuizStats.fromJson(block('quizzes')),
      mastery: MasteryStats.fromJson(block('mastery')),
      remedial: RemedialStats.fromJson(block('remedial')),
    );
  }
}

/// Mirrors `edupulse_core.licence`. Non-admin personas receive only `state`
/// and `blocking`, so every other field must tolerate being absent.
enum LicenceState {
  active('active', 'نشط'),
  expiring('expiring', 'يقترب الانتهاء'),
  grace('grace', 'مهلة سماح'),
  expired('expired', 'منتهٍ'),
  suspended('suspended', 'موقوف'),
  unknown('', '—');

  const LicenceState(this.wire, this.label);

  final String wire;
  final String label;

  static LicenceState fromWire(String? value) => LicenceState.values.firstWhere(
    (s) => s.wire == value,
    orElse: () => LicenceState.unknown,
  );

  Color get colour => switch (this) {
    LicenceState.active => const Color(0xFF10B981),
    LicenceState.expiring => const Color(0xFFF59E0B),
    LicenceState.grace => const Color(0xFFF97316),
    LicenceState.expired || LicenceState.suspended => const Color(0xFFDC2626),
    LicenceState.unknown => const Color(0xFF94A3B8),
  };
}

class Seats {
  const Seats({this.used = 0, this.total = 0, this.unlimited = true});

  final int used;
  final int total;
  final bool unlimited;

  int get available => unlimited ? 0 : (total - used);

  double get fraction =>
      (unlimited || total == 0) ? 0 : (used / total).clamp(0.0, 1.0);

  factory Seats.fromJson(Map<String, dynamic> json) => Seats(
    used: asInt(json['used']),
    total: asInt(json['total']),
    unlimited: asBool(json['unlimited']),
  );
}

class Licence {
  const Licence({
    required this.state,
    this.plan,
    this.expiresOn,
    this.daysLeft,
    this.warning,
    this.seats,
    this.blocking = false,
  });

  final LicenceState state;
  final String? plan;
  final String? expiresOn;
  final int? daysLeft;
  final String? warning;

  /// Admin-only. Null for every other persona.
  final Seats? seats;
  final bool blocking;

  bool get needsAttention => state != LicenceState.active;

  factory Licence.fromJson(Map<String, dynamic> json) => Licence(
    state: LicenceState.fromWire(json['state'] as String?),
    plan: json['plan'] as String?,
    expiresOn: json['expires_on'] as String?,
    daysLeft: json['days_left'] == null ? null : asInt(json['days_left']),
    warning: json['warning'] as String?,
    blocking: asBool(json['blocking']),
    seats: json['seats'] == null
        ? null
        : Seats.fromJson(Map<String, dynamic>.from(json['seats'] as Map)),
  );
}
