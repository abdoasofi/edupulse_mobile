/// Counted nouns in Arabic.
///
/// Not a typographic nicety. Arabic agreement is a *grammatical* property of
/// the number, and getting it wrong produces text a reader trips over:
/// «١ مهارات» and «٣ مهارة» are both plainly broken, and both shipped on the
/// parent portal's first run.
///
/// The rule, for the counts an app like this actually shows:
///
///   1        مهارة          singular alone, no numeral
///   2        مهارتان        dual, no numeral
///   3–10     ٣ مهارات       numeral + plural
///   11+      ١١ مهارة       numeral + accusative singular
///
/// and, past 100, the cycle repeats on the last two digits — ١٠٣ مهارات.
library;

class ArabicNoun {
  const ArabicNoun({
    required this.one,
    required this.two,
    required this.few,
    required this.many,
    this.none,
  });

  /// مهارة — used alone for exactly one.
  final String one;

  /// مهارتان — the dual, used alone for exactly two.
  final String two;

  /// مهارات — the plural, after 3–10.
  final String few;

  /// مهارة — the accusative singular, after 11 and above.
  final String many;

  /// «لا مهارات» reads as an answer; «٠ مهارة» reads as a broken field.
  final String? none;

  String get zero => none ?? 'لا $few';
}

const skills = ArabicNoun(
  one: 'مهارة واحدة',
  two: 'مهارتان',
  few: 'مهارات',
  many: 'مهارة',
);

const lessons = ArabicNoun(
  one: 'درس واحد',
  two: 'درسان',
  few: 'دروس',
  many: 'درساً',
);

const children = ArabicNoun(
  one: 'ابن واحد',
  two: 'ابنان',
  few: 'أبناء',
  many: 'ابناً',
);

String counted(int n, ArabicNoun noun) {
  final value = n.abs();

  if (value == 0) return noun.zero;
  if (value == 1) return noun.one;
  if (value == 2) return noun.two;

  final tail = value % 100;

  return tail >= 3 && tail <= 10 ? '$value ${noun.few}' : '$value ${noun.many}';
}

/// Force a number and its sign to read left-to-right.
///
/// «+١٠٠» inside an Arabic paragraph renders as «١٠٠+»: the sign is a neutral
/// character, so the bidi algorithm hands it to the surrounding right-to-left
/// run rather than to the digits it belongs to. The mark pins it to them.
String ltr(String value) => '‎$value‎';

/// A signed figure that stays signed on the correct side.
String signed(num value) =>
    ltr(value > 0 ? '+${value.round()}' : '${value.round()}');
