import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:edupulse_mobile/features/teacher/domain/teacher_models.dart';

/// The home preview collapses the queue to one row per student.
///
/// Without it a student flagged in four skills fills all four preview slots,
/// and a teacher reads "one student is struggling" off a screen that is
/// actually reporting eight. The collapse must keep each student's *worst*
/// case, since that is what decides whether the teacher is needed at all.
void main() {
  test('collapses to distinct students, keeping the worst case', () {
    final rows = [
      _entry('a@x', 'ADD', remedial: 1, failures: 4),
      _entry('a@x', 'MUL', remedial: 1, failures: 6),
      _entry('a@x', 'DIV', remedial: 3, failures: 5), // worst: intervene
      _entry('b@x', 'ADD', remedial: 0, failures: 3),
      _entry('c@x', 'SIM', remedial: 2, failures: 7),
    ];

    final collapsed = _collapse(rows);

    expect(collapsed.map((e) => e.student), ['c@x', 'a@x', 'b@x']);
    expect(
      collapsed.first.triage,
      Triage.intervene,
      reason: 'الأعجل أولاً',
    );
    expect(
      collapsed[1].skill,
      'DIV',
      reason: 'يُحتفظ بأسوأ مهارة للطالب لا بأولها',
    );
  });

  test('real payload: no student appears twice in the preview', () {
    final raw =
        jsonDecode(
              File('test/fixtures/teacher_payloads.json').readAsStringSync(),
            )
            as Map<String, dynamic>;

    final rows = (raw['struggling'] as List)
        .map(
          (e) => StrugglingEntry.fromJson(Map<String, dynamic>.from(e as Map)),
        )
        .toList();

    final collapsed = _collapse(rows);
    final names = collapsed.map((e) => e.student).toList();

    expect(names.toSet(), hasLength(names.length));
    expect(collapsed.length, lessThanOrEqualTo(rows.length));
  });
}

/// Mirrors the ordering and collapse in `_InterventionQueue`.
List<StrugglingEntry> _collapse(List<StrugglingEntry> rows) {
  final sorted = [...rows]
    ..sort((a, b) {
      final byTriage = b.triage.index.compareTo(a.triage.index);
      if (byTriage != 0) return byTriage;
      return b.consecutiveFailures.compareTo(a.consecutiveFailures);
    });

  final worst = <String, StrugglingEntry>{};
  for (final entry in sorted) {
    worst.putIfAbsent(entry.student, () => entry);
  }

  return worst.values.toList();
}

StrugglingEntry _entry(
  String student,
  String skill, {
  required int remedial,
  required int failures,
}) => StrugglingEntry(
  student: student,
  studentName: student,
  skill: skill,
  skillName: skill,
  currentMastery: 60,
  consecutiveFailures: failures,
  remedialCount: remedial,
);
