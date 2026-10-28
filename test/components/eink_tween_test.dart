import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:venera_next/components/button.dart';
import 'package:venera_next/components/consts.dart';
import 'package:venera_next/components/select.dart';

Future<void> _pump(
  WidgetTester tester,
  Widget child, {
  required bool disableAnimations,
}) => tester.pumpWidget(
  MaterialApp(
    builder: (context, app) => MediaQuery(
      data: MediaQuery.of(
        context,
      ).copyWith(disableAnimations: disableAnimations),
      child: app!,
    ),
    home: Material(child: Center(child: child)),
  ),
);

void main() {
  for (final disabled in [true, false]) {
    final expected = disabled ? Duration.zero : fastAnimationDuration;
    testWidgets(
      'component tweens last $expected (disableAnimations=$disabled)',
      (tester) async {
        await _pump(
          tester,
          Column(
            children: [
              FilterChipFixedWidth(
                label: const Text('chip'),
                selected: true,
                onSelected: (_) {},
              ),
              OptionChip(text: 'opt', isSelected: true, onTap: () {}),
              Button.outlined(onPressed: () {}, child: const Text('b')),
            ],
          ),
          disableAnimations: disabled,
        );
        await tester.pump();
        await tester.pump();
        for (final c in tester.widgetList<AnimatedContainer>(
          find.byType(AnimatedContainer),
        )) {
          expect(c.duration, expected);
        }
        expect(
          tester
              .widget<AnimatedPositioned>(find.byType(AnimatedPositioned))
              .duration,
          expected,
        );
        expect(
          tester.widget<AnimatedSize>(find.byType(AnimatedSize)).duration,
          expected,
        );
        if (disabled) {
          // The check icon is fully drawn on its first frame and nothing keeps
          // scheduling frames.
          expect(tester.binding.hasScheduledFrame, isFalse);
          final check = tester.widget<AnimatedCheckWidget>(
            find.byType(AnimatedCheckWidget),
          );
          expect((check.listenable as Animation<double>).value, 1);
        } else {
          await tester.pumpAndSettle();
        }
      },
    );
  }
}
