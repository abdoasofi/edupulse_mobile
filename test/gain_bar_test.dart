import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:edupulse_mobile/features/teacher/presentation/teacher_widgets.dart';

/// The gain bar is the only chart in the staff portal, and it is read in RTL.
///
/// Geometry, not pixels: the grey baseline segment must hug the *right* edge
/// (where an Arabic reader starts), and the green gain must sit immediately to
/// its left. Get the direction wrong and every student on the screen is
/// misreported — silently, because the bar still looks plausible.
void main() {
  const width = 200.0;
  const barColour = Color(0xFF10B981);

  Future<List<Rect>> render(
    WidgetTester tester, {
    required double baseline,
    required double current,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: Center(
            child: SizedBox(
              width: width,
              child: GainBar(baseline: baseline, current: current),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final root = tester.getRect(find.byType(GainBar));

    // Every painted segment, as an offset from the right edge of the track.
    return find
        .byType(Container)
        .evaluate()
        .map((e) => tester.getRect(find.byWidget(e.widget)))
        .map((r) => Rect.fromLTRB(root.right - r.right, 0, root.right - r.left, 6))
        .toList();
  }

  Rect greenSegment(WidgetTester tester, Rect root) {
    final green = find.byWidgetPredicate((w) {
      if (w is! Container) return false;
      final decoration = w.decoration;
      return decoration is BoxDecoration && decoration.color == barColour;
    });

    final rect = tester.getRect(green);
    return Rect.fromLTRB(root.right - rect.right, 0, root.right - rect.left, 6);
  }

  testWidgets('grey baseline starts at the right edge in RTL', (tester) async {
    await render(tester, baseline: 60, current: 90);

    final root = tester.getRect(find.byType(GainBar));
    final green = greenSegment(tester, root);

    // Baseline 60% of 200 = 120 from the right; gain runs 120 → 180.
    expect(green.left, closeTo(120, 0.5), reason: 'الأخضر يبدأ حيث ينتهي الأساس');
    expect(green.right, closeTo(180, 0.5), reason: 'الأخضر ينتهي عند الإتقان الحالي');
  });

  testWidgets('a small gain paints a small band, not a centred one', (
    tester,
  ) async {
    await render(tester, baseline: 63, current: 81);

    final root = tester.getRect(find.byType(GainBar));
    final green = greenSegment(tester, root);

    expect(green.width, closeTo(36, 0.5), reason: '18٪ من 200');
    expect(green.left, closeTo(126, 0.5));
  });

  testWidgets('a student who has not moved shows no green at all', (
    tester,
  ) async {
    await render(tester, baseline: 70, current: 70);

    final green = find.byWidgetPredicate((w) {
      if (w is! Container) return false;
      final decoration = w.decoration;
      return decoration is BoxDecoration && decoration.color == barColour;
    });

    expect(green, findsNothing);
  });
}
