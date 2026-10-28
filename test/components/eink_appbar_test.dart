import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:venera_next/components/appbar.dart';
import 'package:venera_next/main.dart' show getTheme;

void main() {
  for (final eink in [true, false]) {
    testWidgets('appbar background opacity, eink=$eink', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: getTheme(
            Colors.blue,
            null,
            null,
            Brightness.light,
            eink: eink,
          ),
          home: const Scaffold(body: Appbar(title: Text('title'))),
        ),
      );
      final box = tester.widget<Container>(
        find
            .ancestor(of: find.text('title'), matching: find.byType(Container))
            .last,
      );
      final color = (box.decoration! as BoxDecoration).color!;
      // Content scrolled under a translucent bar shows through as gray on E-Ink.
      expect(color.a, eink ? 1.0 : closeTo(0.86, 0.01));
    });
  }
}
