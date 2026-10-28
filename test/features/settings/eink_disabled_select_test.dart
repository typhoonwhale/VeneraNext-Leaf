import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:venera_next/features/settings/setting_components.dart';
import 'package:venera_next/foundation/appdata.dart';
import 'package:venera_next/foundation/eink_theme.dart';
import 'package:venera_next/foundation/preferences.dart';
import 'package:venera_next/main.dart' show getTheme;

Future<void> _pump(WidgetTester tester, double width, {required bool eink}) {
  appdata.settings['initialPage'] = '0';
  appdata.settings['disableSyncFields'] = '';
  return tester.pumpWidget(
    MaterialApp(
      theme: getTheme(Colors.blue, null, null, Brightness.light, eink: eink),
      home: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: width,
            child: SelectSetting.preference(
              title: 'Title',
              subtitle: 'Sub',
              enabled: false,
              preference: const StringPreference('initialPage', '0'),
              optionTranslation: const {'0': 'Zero'},
            ),
          ),
        ),
      ),
    ),
  );
}

void main() {
  // The narrow layout (< 450) and the wide one must both mark a disabled
  // selector with a black outline, hatch lines and a white halo.
  for (final width in [360.0, 600.0]) {
    testWidgets('disabled selector is outlined and hatched at $width', (
      tester,
    ) async {
      await _pump(tester, width, eink: true);
      await tester.pumpAndSettle();
      expect(find.byType(EInkHatch), findsOneWidget);
      final decorated = find
          .ancestor(
            of: find.byType(EInkHatch),
            matching: find.byType(DecoratedBox),
          )
          .evaluate()
          .map((e) => (e.widget as DecoratedBox).decoration)
          .whereType<BoxDecoration>()
          .where((d) => d.border != null);
      expect(decorated, isNotEmpty);
      final side = (decorated.first.border as Border).top;
      expect(side.color, Colors.black);
      expect(side.width, EInkStyle.strokeWidth);
      if (width < 450) {
        // Title, subtitle and arrow each have a halo copy under them.
        expect(find.text('Title'), findsNWidgets(2));
        expect(find.text('Sub'), findsNWidgets(2));
        expect(find.byIcon(Icons.arrow_drop_down), findsNWidgets(2));
        final e = tester.element(find.text('Title').first);
        final style = DefaultTextStyle.of(e).style;
        expect(style.foreground!.color, Colors.white);
        final top = tester.element(find.text('Title').last);
        expect(DefaultTextStyle.of(top).style.color, Colors.black);
      }
    });
  }

  testWidgets('regular theme keeps the plain disabled tile', (tester) async {
    await _pump(tester, 360, eink: false);
    await tester.pumpAndSettle();
    expect(find.byType(EInkHatch), findsNothing);
    expect(find.text('Title'), findsOneWidget);
  });
}
