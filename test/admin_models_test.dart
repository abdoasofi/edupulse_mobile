import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:edupulse_mobile/features/admin/domain/admin_models.dart';

/// Parsed against a payload captured from the live site.
///
/// The executive screen is what a head of school is shown before signing.
/// A number that parses to zero because a key moved, or a licence banner that
/// fails to appear because `seats` was absent for a supervisor, would both
/// render as a perfectly normal-looking dashboard.
void main() {
  final raw =
      jsonDecode(File('test/fixtures/admin_payloads.json').readAsStringSync())
          as Map<String, dynamic>;

  final kpis = ExecutiveKpis.fromJson(
    Map<String, dynamic>.from(raw['kpis'] as Map),
  );

  group('ExecutiveKpis', () {
    test('every block parses with real figures', () {
      expect(kpis.periodDays, 30);
      expect(kpis.students.total, greaterThan(0));
      expect(kpis.mastery.measured, greaterThan(0));
      expect(kpis.remedial.triggered, greaterThan(0));
      expect(kpis.quizzes.attempts, greaterThan(0));
    });

    test('gain is consistent with pre and post', () {
      expect(kpis.mastery.gain, closeTo(kpis.mastery.post - kpis.mastery.pre, 0.11));
    });

    test('the attempt rate is far below the student-level rate', () {
      // Not a coincidence — it is the whole reason the screen shows three
      // numbers instead of one. If these ever converge, the narrative on the
      // screen stops matching the data behind it.
      expect(
        kpis.quizzes.attemptPassRate,
        lessThan(kpis.mastery.masteryRate),
        reason: 'نسبة نجاح المحاولات يجب أن تكون أدنى بكثير من نسبة الإتقان',
      );
    });

    test('first-time and recovered together account for the mastered', () {
      expect(
        kpis.mastery.firstTime + kpis.mastery.recovered,
        lessThanOrEqualTo(kpis.mastery.measured),
      );
      expect(kpis.mastery.recovered, greaterThan(0));
    });

    test('an empty tenant reports no data rather than zeroes', () {
      final empty = ExecutiveKpis.fromJson(const {});

      expect(empty.hasData, isFalse);
      expect(empty.periodDays, 30);
      expect(empty.mastery.pre, 0);
    });
  });

  group('Licence', () {
    test('an admin payload carries plan and seats', () {
      final licence = Licence.fromJson(
        Map<String, dynamic>.from(raw['licence'] as Map),
      );

      expect(licence.seats, isNotNull);
      expect(licence.seats!.total, greaterThan(0));
      expect(licence.plan, isNotNull);
    });

    test('a non-admin payload parses without plan or seats', () {
      // Students and teachers are sent only these two keys. Assuming the rest
      // would crash the very first screen a teacher opens.
      final licence = Licence.fromJson(const {
        'state': 'active',
        'blocking': false,
      });

      expect(licence.state, LicenceState.active);
      expect(licence.seats, isNull);
      expect(licence.plan, isNull);
      expect(licence.needsAttention, isFalse);
    });

    test('states map to their wire values', () {
      for (final state in LicenceState.values) {
        if (state == LicenceState.unknown) continue;
        expect(LicenceState.fromWire(state.wire), state);
      }
      expect(LicenceState.fromWire('nonsense'), LicenceState.unknown);
    });

    test('seat fraction stays in range and survives an unlimited plan', () {
      const unlimited = Seats(used: 900, total: 0, unlimited: true);
      expect(unlimited.fraction, 0);

      const full = Seats(used: 600, total: 500, unlimited: false);
      expect(full.fraction, 1.0, reason: 'تجاوز الحد لا يتجاوز الشريط');
      expect(full.available, lessThan(0));
    });
  });
}
