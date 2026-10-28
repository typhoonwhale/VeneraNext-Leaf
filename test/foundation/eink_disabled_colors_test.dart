import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:venera_next/components/button.dart';
import 'package:venera_next/components/select.dart';
import 'package:venera_next/foundation/eink_theme.dart';

Future<void> _pumpDisabled(WidgetTester tester, ThemeData theme) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: theme,
      home: const Scaffold(
        body: Column(
          children: [
            ListTile(
              enabled: false,
              title: Text('title'),
              subtitle: Text('subtitle'),
              leading: Icon(Icons.add),
              trailing: Icon(Icons.remove),
            ),
            IconButton(onPressed: null, icon: Icon(Icons.home)),
            TextField(
              enabled: false,
              decoration: InputDecoration(
                labelText: 'label',
                helperText: 'helper',
                prefixIcon: Icon(Icons.search),
              ),
            ),
          ],
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Color? _textColor(WidgetTester tester, String text) {
  final e = tester.element(find.text(text));
  return DefaultTextStyle.of(e).style.merge((e.widget as Text).style).color;
}

Color? _iconColor(WidgetTester tester, IconData icon) => tester
    .widget<RichText>(
      find.descendant(of: find.byIcon(icon), matching: find.byType(RichText)),
    )
    .text
    .style
    ?.color;

void main() {
  testWidgets('disabled text and icons stay solid black in E-Ink', (
    tester,
  ) async {
    await _pumpDisabled(tester, applyEInkTheme(ThemeData.light()));
    for (final t in ['title', 'subtitle', 'label', 'helper']) {
      expect(_textColor(tester, t), Colors.black, reason: t);
    }
    for (final i in [Icons.add, Icons.remove, Icons.home, Icons.search]) {
      expect(_iconColor(tester, i), Colors.black, reason: '$i');
    }
  });

  testWidgets('the regular theme keeps the grey disabled color', (
    tester,
  ) async {
    await _pumpDisabled(tester, ThemeData.light());
    expect(_textColor(tester, 'title'), ThemeData.light().disabledColor);
    expect(_iconColor(tester, Icons.home)!.a, lessThan(1));
  });

  test('disabled checkbox and slider are not grey in E-Ink', () {
    final t = applyEInkTheme(ThemeData.light());
    const disabled = {WidgetState.disabled};
    expect(t.checkboxTheme.fillColor!.resolve(disabled), Colors.white);
    expect(
      t.checkboxTheme.fillColor!.resolve({...disabled, WidgetState.selected}),
      Colors.black,
    );
    expect(t.checkboxTheme.side!.color, Colors.black);
    expect(t.sliderTheme.disabledActiveTrackColor, Colors.black);
    expect(t.sliderTheme.disabledInactiveTrackColor, Colors.white);
    expect(t.sliderTheme.disabledThumbColor, Colors.black);
  });

  testWidgets('enabled Select outline is strokeWidth in E-Ink, 1 otherwise', (
    tester,
  ) async {
    Future<double> outline(ThemeData theme) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: theme,
          home: const Material(
            child: Select(current: 'a', values: ['a']),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final box = tester
          .widgetList<Container>(find.byType(Container))
          .map((c) => c.decoration)
          .whereType<BoxDecoration>()
          .firstWhere((d) => d.border != null);
      return (box.border as Border).top.width;
    }

    expect(
      await outline(applyEInkTheme(ThemeData.light())),
      EInkStyle.strokeWidth,
    );
    await tester.pumpWidget(const SizedBox());
    expect(await outline(ThemeData.light()), 1);
  });

  testWidgets('fixed-size Button keeps the requested size in E-Ink', (
    tester,
  ) async {
    Future<Size> size(ThemeData theme, Widget button) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: theme,
          home: Material(child: Center(child: button)),
        ),
      );
      await tester.pumpAndSettle();
      return tester.getSize(find.byType(Button));
    }

    final eink = applyEInkTheme(ThemeData.light());
    for (final make in <Widget Function()>[
      () => Button.outlined(
        width: 120,
        height: 48,
        onPressed: () {},
        child: const Text('x'),
      ),
      () => Button.text(
        width: 120,
        height: 48,
        onPressed: () {},
        child: const Text('x'),
      ),
      () => Button.normal(
        width: 120,
        height: 48,
        onPressed: () {},
        child: const Text('x'),
      ),
      () => Button.filled(
        width: 120,
        height: 48,
        onPressed: () {},
        child: const Text('x'),
      ),
    ]) {
      expect(await size(eink, make()), const Size(120, 48));
    }
    // The regular theme is untouched: outlined keeps its 0.6px border extra.
    expect(
      await size(
        ThemeData.light(),
        Button.outlined(
          width: 120,
          height: 48,
          onPressed: () {},
          child: const Text('x'),
        ),
      ),
      const Size(121.2, 49.2),
    );
  });
}
