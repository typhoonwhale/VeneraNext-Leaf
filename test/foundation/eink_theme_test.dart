import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:venera_next/components/effects.dart';
import 'package:venera_next/components/navigation_bar.dart';
import 'package:venera_next/components/select.dart';
import 'package:venera_next/components/summary_header.dart';
import 'package:venera_next/foundation/context.dart';
import 'package:venera_next/foundation/eink_theme.dart';
import 'package:venera_next/main.dart' show getTheme;

double _contrast(Color a, Color b) {
  final la = a.computeLuminance(), lb = b.computeLuminance();
  final hi = la > lb ? la : lb, lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}

ThemeData _theme({required bool eink, Brightness b = Brightness.light}) =>
    getTheme(Colors.blue, null, null, b, eink: eink);

Future<BuildContext> _context(
  WidgetTester tester,
  ThemeData theme, {
  Widget Function(BuildContext)? child,
}) async {
  late BuildContext captured;
  await tester.pumpWidget(
    MaterialApp(
      theme: theme,
      home: Builder(
        builder: (context) {
          captured = context;
          return child?.call(context) ?? const SizedBox();
        },
      ),
    ),
  );
  await tester.pumpAndSettle();
  return captured;
}

void main() {
  test('T1 monochrome scheme keeps high contrast pairs', () {
    final s = einkColorScheme();
    final pairs = {
      'primary': (s.primary, s.onPrimary),
      'primaryContainer': (s.primaryContainer, s.onPrimaryContainer),
      'secondary': (s.secondary, s.onSecondary),
      'secondaryContainer': (s.secondaryContainer, s.onSecondaryContainer),
      'tertiary': (s.tertiary, s.onTertiary),
      'tertiaryContainer': (s.tertiaryContainer, s.onTertiaryContainer),
      'error': (s.error, s.onError),
      'errorContainer': (s.errorContainer, s.onErrorContainer),
      'surface': (s.surface, s.onSurface),
      'surfaceVariant': (s.surface, s.onSurfaceVariant),
      'inverseSurface': (s.inverseSurface, s.onInverseSurface),
    };
    for (final entry in pairs.entries) {
      expect(
        _contrast(entry.value.$1, entry.value.$2),
        greaterThanOrEqualTo(7),
        reason: entry.key,
      );
    }
    expect(_contrast(s.surface, s.outline), greaterThanOrEqualTo(4.5));
    expect(_contrast(s.surface, s.outlineVariant), greaterThanOrEqualTo(4.5));
    expect(s.shadow.a, 0);
    expect(s.surfaceTint.a, 0);
    for (final c in [
      s.surfaceDim,
      s.surfaceBright,
      s.surfaceContainerLowest,
      s.surfaceContainerLow,
      s.surfaceContainer,
      s.surfaceContainerHigh,
      s.surfaceContainerHighest,
    ]) {
      expect(c, Colors.white);
    }
  });

  test('T2 E-Ink theme turns off splash, scrim and route transitions', () {
    final theme = _theme(eink: true);
    expect(theme.splashFactory, NoSplash.splashFactory);
    expect(theme.dialogTheme.barrierColor, Colors.transparent);
    expect(theme.extension<EInkStyle>()?.enabled, isTrue);
    expect(theme.colorScheme.primaryContainer, Colors.white);
    expect(theme.cardTheme.elevation, 0);
    expect(theme.popupMenuTheme.elevation, 0);
    expect(theme.snackBarTheme.elevation, 0);
    for (final platform in TargetPlatform.values) {
      expect(
        theme.pageTransitionsTheme.builders[platform].runtimeType.toString(),
        '_NoTransitionsBuilder',
        reason: '$platform',
      );
    }
    final regular = _theme(eink: false);
    expect(regular.extension<EInkStyle>(), isNull);
    expect(regular.splashFactory, isNot(NoSplash.splashFactory));
    expect(regular.dialogTheme.barrierColor, isNull);
  });

  testWidgets('T2 material routes switch instantly with the E-Ink theme', (
    tester,
  ) async {
    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigator,
        theme: _theme(eink: true),
        home: const Text('first'),
      ),
    );
    navigator.currentState!.push(
      MaterialPageRoute<void>(builder: (_) => const Text('second')),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1));
    expect(find.text('second').hitTestable(), findsOneWidget);
    final transform = find.ancestor(
      of: find.text('second'),
      matching: find.byType(SlideTransition),
    );
    expect(transform, findsNothing);
  });

  testWidgets('T3 colored helpers collapse to black and white in E-Ink', (
    tester,
  ) async {
    final eink = await _context(tester, _theme(eink: true));
    for (final color in [Colors.red, Colors.blue, Colors.green]) {
      expect(eink.useBackgroundColor(color), Colors.white);
      expect(eink.useTextColor(color), Colors.black);
    }
    expect(eink.isEInk, isTrue);
    final light = await _context(tester, _theme(eink: false));
    expect(light.isEInk, isFalse);
    expect(light.useBackgroundColor(Colors.red), Colors.red[100]);
    expect(light.useTextColor(Colors.red), Colors.red[800]);
    final dark = await _context(
      tester,
      _theme(eink: false, b: Brightness.dark),
    );
    expect(dark.useBackgroundColor(Colors.red), Colors.red[800]);
    expect(dark.useTextColor(Colors.red), Colors.red[100]);
  });

  testWidgets('T3 blur is dropped in E-Ink only', (tester) async {
    Widget build(bool eink) => MaterialApp(
      theme: _theme(eink: eink),
      home: const BlurEffect(child: Text('child')),
    );
    await tester.pumpWidget(build(false));
    expect(find.byType(BackdropFilter), findsOneWidget);
    await tester.pumpWidget(build(true));
    await tester.pumpAndSettle();
    expect(find.byType(BackdropFilter), findsNothing);
    expect(find.text('child'), findsOneWidget);
  });

  group('T4 selected states', () {
    Future<void> pump(WidgetTester tester, Widget child, {bool eink = true}) =>
        tester.pumpWidget(
          MaterialApp(
            theme: _theme(eink: eink),
            home: Scaffold(body: Center(child: child)),
          ),
        );

    testWidgets('OptionChip fills black with white text when selected', (
      tester,
    ) async {
      await pump(
        tester,
        Column(
          children: [
            OptionChip(text: 'on', isSelected: true, onTap: () {}),
            OptionChip(text: 'off', isSelected: false, onTap: () {}),
          ],
        ),
      );
      await tester.pumpAndSettle();
      BoxDecoration deco(String text) =>
          tester
                  .widget<AnimatedContainer>(
                    find.ancestor(
                      of: find.text(text),
                      matching: find.byType(AnimatedContainer),
                    ),
                  )
                  .decoration!
              as BoxDecoration;
      expect(deco('on').color, Colors.black);
      expect(deco('off').color, Colors.white);
      expect(tester.widget<Text>(find.text('on')).style?.color, Colors.white);
      expect(
        tester.widget<Text>(find.text('off')).style?.color,
        isNot(Colors.white),
      );
      final border = deco('off').border! as Border;
      expect(border.top.color, Colors.black);
      expect(border.top.width, 1.5);
    });

    testWidgets(
      'FilterChipFixedWidth selected chip is black with white label',
      (tester) async {
        await pump(
          tester,
          FilterChipFixedWidth(
            label: const Text('tag'),
            selected: true,
            onSelected: (_) {},
          ),
        );
        await tester.pumpAndSettle();
        final box = tester.widget<AnimatedContainer>(
          find.byType(AnimatedContainer).first,
        );
        expect((box.decoration! as BoxDecoration).color, Colors.black);
        final style = DefaultTextStyle.of(tester.element(find.text('tag')));
        expect(style.style.color, Colors.white);
      },
    );

    testWidgets('summary badge is outlined black on white', (tester) async {
      await pump(tester, const SummaryHeader(title: 'Local', count: 3));
      final badge = tester.widget<Container>(
        find.ancestor(of: find.text('3'), matching: find.byType(Container)),
      );
      final deco = badge.decoration! as BoxDecoration;
      expect(deco.color, Colors.white);
      expect((deco.border! as Border).top.color, Colors.black);
      final text = tester.widget<Text>(find.text('3'));
      final color =
          (text.style?.color ??
          DefaultTextStyle.of(tester.element(find.text('3'))).style.color)!;
      expect(_contrast(deco.color!, color), greaterThanOrEqualTo(7));
      await pump(
        tester,
        const SummaryHeader(title: 'Local', count: 3),
        eink: false,
      );
      await tester.pumpAndSettle();
      final regular = tester.widget<Container>(
        find.ancestor(of: find.text('3'), matching: find.byType(Container)),
      );
      expect((regular.decoration! as BoxDecoration).border, isNull);
    });

    for (final width in [400.0, 1000.0]) {
      testWidgets('navigation selection is black with white icon at $width', (
        tester,
      ) async {
        await tester.binding.setSurfaceSize(Size(width, 800));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final key = GlobalKey<NavigatorState>();
        final observer = NaviObserver();
        await tester.pumpWidget(
          MaterialApp(
            theme: _theme(eink: true),
            home: NaviPane(
              paneItems: [
                PaneItemEntry(
                  label: 'A',
                  icon: Icons.home_outlined,
                  activeIcon: Icons.home,
                ),
                PaneItemEntry(
                  label: 'B',
                  icon: Icons.settings_outlined,
                  activeIcon: Icons.settings,
                ),
              ],
              paneActions: const [],
              pageBuilder: (_) => const SizedBox(),
              observer: observer,
              navigatorKey: key,
            ),
          ),
        );
        await tester.pumpAndSettle();
        final selected = tester.widget<Icon>(find.byIcon(Icons.home));
        final other = tester.widget<Icon>(find.byIcon(Icons.settings_outlined));
        expect(selected.color, Colors.white);
        expect(other.color, isNull);
        final bg = find.ancestor(
          of: find.byIcon(Icons.home),
          matching: find.byWidgetPredicate(
            (w) =>
                w is DecoratedBox &&
                (w.decoration as BoxDecoration).color == Colors.black,
          ),
        );
        expect(bg, findsOneWidget);
      });
    }
  });
}
