import 'package:edupulse_mobile/shared/arabic.dart';
import 'package:flutter_test/flutter_test.dart';

/// Arabic agreement is grammar, not formatting. «١ مهارات» and «٣ مهارة» are
/// both broken sentences, and both shipped on the parent portal's first run —
/// on a screen whose whole job is to be read calmly by a worried parent.
void main() {
  group('counted', () {
    test('one and two take their own forms, without a numeral', () {
      expect(counted(1, skills), 'مهارة واحدة');
      expect(counted(2, skills), 'مهارتان');

      for (final text in [counted(1, skills), counted(2, skills)]) {
        expect(text, isNot(contains('1')));
        expect(text, isNot(contains('2')));
      }
    });

    test('three to ten take the plural', () {
      expect(counted(3, skills), '3 مهارات');
      expect(counted(10, skills), '10 مهارات');
    });

    test('eleven and above take the singular again', () {
      expect(counted(11, skills), '11 مهارة');
      expect(counted(99, skills), '99 مهارة');
    });

    test('the cycle restarts past a hundred', () {
      expect(counted(103, skills), '103 مهارات');
      expect(counted(111, skills), '111 مهارة');
    });

    test('zero is an answer, not an empty field', () {
      expect(counted(0, skills), 'لا مهارات');
      expect(counted(0, skills), isNot(contains('0')));
    });
  });

  group('signed', () {
    test('a gain keeps its sign on the left of the digits', () {
      // The bug: '+100' inside an Arabic paragraph renders as '100+', because
      // the sign is bidi-neutral and drifts to the right-to-left run.
      final text = signed(100);

      expect(text, contains('+100'));
      expect(text.indexOf('+'), lessThan(text.indexOf('1')));
      expect(text.codeUnits, contains(0x200E)); // the mark that pins it
    });

    test('a loss is rendered without inventing a plus', () {
      expect(signed(-5), contains('-5'));
      expect(signed(-5), isNot(contains('+')));
    });

    test('a rounded zero carries no sign', () {
      expect(signed(0), isNot(contains('+')));
    });
  });
}
