import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:edupulse_mobile/features/teacher/domain/teacher_models.dart';

/// Parsed against payloads captured from a live site, not hand-written ones.
///
/// Hand-written fixtures only prove the models agree with whatever the author
/// imagined. The traps here are real and were all present in the capture:
/// MariaDB returns `SUM()` as a float, `skill_name` is English while
/// `skill_name_ar` is the one to show, and datetimes come back space-separated
/// rather than ISO-8601.
void main() {
  final raw = jsonDecode(
    File('test/fixtures/teacher_payloads.json').readAsStringSync(),
  ) as Map<String, dynamic>;

  group('ClassOverview', () {
    final overview = ClassOverview.fromJson(
      Map<String, dynamic>.from(raw['overview'] as Map),
    );

    test('parses the roster and its stats', () {
      expect(overview.students, hasLength(24));
      expect(overview.stats.count, 24);
      expect(overview.stats.avgMastery, 87.4);
      expect(overview.stats.struggling, 8);
    });

    test('coerces SUM() floats to counts', () {
      // `mastered` and `flagged` arrive as 1.0 / 4.0 — an `as int` cast would
      // throw at runtime on the first student.
      for (final s in overview.students) {
        expect(s.mastered, isA<int>());
        expect(s.flagged, isA<int>());
      }
      expect(overview.students.every((s) => s.skills > 0), isTrue);
    });

    test('gain is consistent with baseline and current', () {
      for (final s in overview.students) {
        expect(s.gain, closeTo(s.avgMastery - s.avgBaseline, 0.11));
      }
    });
  });

  group('StrugglingEntry', () {
    final rows = (raw['struggling'] as List)
        .map((e) => StrugglingEntry.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();

    test('prefers the Arabic skill name', () {
      expect(rows.first.skillName, 'جمع الكسور');
      expect(rows.every((r) => r.skillName.isNotEmpty), isTrue);
    });

    test('parses the space-separated datetime Frappe sends', () {
      expect(rows.first.lastAttemptOn, isNotNull);
      expect(rows.first.lastAttemptOn!.year, 2026);
    });

    test('triage escalates with remedial cycles, not with score', () {
      expect(Triage.of(0), Triage.automatic);
      expect(Triage.of(1), Triage.watch);
      expect(Triage.of(2), Triage.intervene);
      expect(Triage.of(9), Triage.intervene);

      // A student the engine already tried to help is a teacher's problem
      // even while their score is not the lowest in the class.
      expect(rows.first.remedialCount, greaterThan(0));
      expect(rows.first.triage, isNot(Triage.automatic));
    });
  });

  group('MasteryImpact', () {
    final impact = MasteryImpact.fromJson(
      Map<String, dynamic>.from(raw['impact'] as Map),
    );

    test('parses rows and the overall summary', () {
      expect(impact.rows, hasLength(4));
      expect(impact.gain, closeTo(impact.post - impact.pre, 0.11));
      expect(impact.rows.first.skillName, isNot(startsWith('MATH-')));
    });

    test('every row has a measurable cohort behind it', () {
      for (final row in impact.rows) {
        expect(row.students, greaterThan(0));
        expect(row.masteryRate, inInclusiveRange(0, 100));
        expect(row.gain, closeTo(row.postMastery - row.preMastery, 0.11));
      }
    });
  });
}
