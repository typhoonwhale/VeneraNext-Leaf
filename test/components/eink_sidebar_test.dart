import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:venera_next/components/side_bar.dart';
import 'package:venera_next/foundation/eink_theme.dart';
import 'package:venera_next/main.dart' show getTheme;

void main() {
  for (final eink in [true, false]) {
    testWidgets('sidebar corner radius, eink=$eink', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1000, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      late BuildContext context;
      await tester.pumpWidget(
        MaterialApp(
          theme: getTheme(
            Colors.blue,
            null,
            null,
            Brightness.light,
            eink: eink,
          ),
          home: Builder(
            builder: (c) {
              context = c;
              return const SizedBox();
            },
          ),
        ),
      );
      Navigator.of(context).push(
        SideBarRoute<void>(const Text('panel'), width: 400),
      );
      await tester.pumpAndSettle();
      final box = tester.widget<Container>(
        find
            .ancestor(of: find.text('panel'), matching: find.byType(Container))
            .last,
      );
      final decoration = box.decoration! as BoxDecoration;
      if (eink) {
        expect(decoration.borderRadius, isNull);
        final border = decoration.border! as Border;
        expect(border.left.width, EInkStyle.strokeWidth);
      } else {
        expect(
          decoration.borderRadius,
          const BorderRadius.horizontal(left: Radius.circular(16)),
        );
      }
    });
  }
}
