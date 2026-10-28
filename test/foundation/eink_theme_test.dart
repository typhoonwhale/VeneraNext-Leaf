import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:venera_next/components/button.dart';
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
      expect(border.top.width, EInkStyle.strokeWidth);
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

    testWidgets('FAB has no elevation and a black outline', (tester) async {
      final fab = _theme(eink: true).floatingActionButtonTheme;
      expect(fab.elevation, 0);
      expect(fab.focusElevation, 0);
      expect(fab.hoverElevation, 0);
      expect(fab.highlightElevation, 0);
      final side = (fab.shape! as RoundedRectangleBorder).side;
      expect(side.color, Colors.black);
      expect(side.width, EInkStyle.strongStrokeWidth);
      expect(fab.backgroundColor, Colors.white);
      expect(fab.foregroundColor, Colors.black);
      await pump(
        tester,
        FloatingActionButton(onPressed: () {}, child: const Icon(Icons.add)),
      );
      final material = tester.widget<Material>(
        find
            .descendant(
              of: find.byType(FloatingActionButton),
              matching: find.byType(Material),
            )
            .first,
      );
      expect(material.elevation, 0);
    });

    test('segmented button selected state is black on white inverse', () {
      final style = _theme(eink: true).segmentedButtonTheme.style!;
      final on = {WidgetState.selected};
      final bg = style.backgroundColor!.resolve(on)!;
      final fg = style.foregroundColor!.resolve(on)!;
      expect(bg, Colors.black);
      expect(_contrast(bg, fg), greaterThanOrEqualTo(7));
      final offBg = style.backgroundColor!.resolve({})!;
      final offFg = style.foregroundColor!.resolve({})!;
      expect(offBg, Colors.white);
      expect(_contrast(offBg, offFg), greaterThanOrEqualTo(7));
    });

    test('stroke constants are used by the theme', () {
      final t = _theme(eink: true);
      expect(EInkStyle.strokeWidth, 2.0);
      expect(EInkStyle.strongStrokeWidth, 3.0);
      final seg = t.segmentedButtonTheme.style!.side!.resolve({})!;
      expect(seg.width, EInkStyle.strokeWidth);
      expect(
        t.switchTheme.trackOutlineWidth!.resolve({}),
        EInkStyle.strokeWidth,
      );
      expect(t.chipTheme.side!.width, EInkStyle.strokeWidth);
      expect(
        t.outlinedButtonTheme.style!.side!.resolve({})!.width,
        EInkStyle.strokeWidth,
      );
      final dialog = t.dialogTheme.shape! as RoundedRectangleBorder;
      expect(dialog.side.width, EInkStyle.strongStrokeWidth);
    });

    test('text weights: small >= w600, others >= w500, light theme intact', () {
      final eink = _theme(eink: true);
      final light = _theme(eink: false);
      for (final theme in [eink.textTheme, eink.primaryTextTheme]) {
        final styles = [
          theme.displayLarge,
          theme.displayMedium,
          theme.displaySmall,
          theme.headlineLarge,
          theme.headlineMedium,
          theme.headlineSmall,
          theme.titleLarge,
          theme.titleMedium,
          theme.titleSmall,
          theme.bodyLarge,
          theme.bodyMedium,
          theme.bodySmall,
          theme.labelLarge,
          theme.labelMedium,
          theme.labelSmall,
        ];
        for (final s in styles) {
          final min = (s!.fontSize ?? 14) <= 12 ? 600 : 500;
          expect(s.fontWeight!.value, greaterThanOrEqualTo(min));
        }
      }
      expect(
        eink.textTheme.bodySmall!.fontSize,
        light.textTheme.bodySmall!.fontSize,
      );
      expect(
        light.textTheme.bodySmall!.fontWeight,
        anyOf(isNull, FontWeight.w400),
      );
      expect(
        light.textTheme.bodyMedium!.fontWeight,
        anyOf(isNull, FontWeight.w400),
      );
    });

    testWidgets('buttons are stadium with strokeWidth outline in E-Ink only', (
      tester,
    ) async {
      for (final eink in [true, false]) {
        await tester.pumpWidget(
          MaterialApp(
            theme: _theme(eink: eink),
            home: Material(
              child: Column(
                children: [
                  TextButton(onPressed: () {}, child: const Text('text')),
                  OutlinedButton(onPressed: () {}, child: const Text('out')),
                  FilledButton.tonal(
                    onPressed: () {},
                    child: const Text('tonal'),
                  ),
                ],
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        for (final type in [TextButton, OutlinedButton, FilledButton]) {
          final style = tester.widget<ButtonStyleButton>(find.byType(type));
          final theme = Theme.of(tester.element(find.byType(type)));
          final themed = switch (type) {
            const (TextButton) => theme.textButtonTheme.style,
            const (OutlinedButton) => theme.outlinedButtonTheme.style,
            _ => theme.filledButtonTheme.style,
          };
          expect(style, isNotNull);
          final shape = themed?.shape?.resolve({});
          final side = themed?.side?.resolve({});
          if (eink) {
            expect(shape, isA<StadiumBorder>());
            expect(side!.width, EInkStyle.strokeWidth);
            expect(side.color, Colors.black);
          } else {
            expect(shape, isNull);
            expect(side, isNull);
          }
        }
      }
    });

    testWidgets('disabled buttons use black outline, black text and hatch', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: _theme(eink: true),
          home: const Material(
            child: Column(
              children: [
                FilledButton(onPressed: null, child: Text('f')),
                TextButton(onPressed: null, child: Text('t')),
                OutlinedButton(onPressed: null, child: Text('o')),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final t = _theme(eink: true);
      const disabled = {WidgetState.disabled};
      for (final style in [
        t.filledButtonTheme.style!,
        t.textButtonTheme.style!,
        t.outlinedButtonTheme.style!,
      ]) {
        final side = style.side!.resolve(disabled)!;
        expect(side.width, EInkStyle.strokeWidth);
        expect(side.color, Colors.black);
        expect(style.foregroundColor!.resolve(disabled), Colors.black);
        expect(style.shape!.resolve(disabled), isA<StadiumBorder>());
        expect(style.backgroundBuilder, isNotNull);
      }
      expect(
        t.filledButtonTheme.style!.backgroundColor!.resolve(disabled),
        Colors.white,
      );
      expect(find.byType(EInkHatch), findsNWidgets(3));
      for (final type in [FilledButton, TextButton, OutlinedButton]) {
        expect(
          tester.getSize(
            find.descendant(
              of: find.byType(type),
              matching: find.byType(EInkHatch),
            ),
          ),
          tester.getSize(
            find
                .descendant(
                  of: find.byType(type),
                  matching: find.byType(Material),
                )
                .first,
          ),
        );
      }
      final text = tester.widget<DefaultTextStyle>(
        find
            .descendant(
              of: find.byType(FilledButton),
              matching: find.byType(DefaultTextStyle),
            )
            .first,
      );
      expect(text.style.color, Colors.black);
    });

    testWidgets('enabled and regular-theme disabled buttons have no hatch', (
      tester,
    ) async {
      Future<void> pump(bool eink, VoidCallback? onPressed) async {
        await tester.pumpWidget(
          MaterialApp(
            theme: _theme(eink: eink),
            home: Material(
              child: Column(
                children: [
                  FilledButton(onPressed: onPressed, child: const Text('f')),
                  TextButton(onPressed: onPressed, child: const Text('t')),
                  OutlinedButton(onPressed: onPressed, child: const Text('o')),
                ],
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
      }

      await pump(true, () {});
      expect(find.byType(EInkHatch), findsNothing);
      await tester.pumpWidget(const SizedBox());
      await pump(false, null);
      expect(find.byType(EInkHatch), findsNothing);
    });

    testWidgets('disabled Select hatches only on E-Ink', (tester) async {
      Future<void> pump(bool eink) => tester.pumpWidget(
        MaterialApp(
          theme: _theme(eink: eink),
          home: const Material(
            child: Select(current: 'a', values: ['a'], enabled: false),
          ),
        ),
      );
      await pump(true);
      await tester.pumpAndSettle();
      expect(find.byType(EInkHatch), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await pump(false);
      await tester.pumpAndSettle();
      expect(find.byType(EInkHatch), findsNothing);
    });

    test('disabled switch is white with black outline and ring thumb', () {
      final sw = _theme(eink: true).switchTheme;
      const disabled = {WidgetState.disabled};
      expect(sw.trackOutlineColor!.resolve(disabled), Colors.black);
      expect(sw.trackColor!.resolve(disabled), Colors.white);
      expect(sw.thumbIcon!.resolve(disabled), isNotNull);
      expect(sw.thumbIcon!.resolve({}), isNull);
    });

    testWidgets('Button.text is outlined in E-Ink, icon and filled are not', (
      tester,
    ) async {
      Border? borderOf(String label) {
        final box = tester.widget<AnimatedContainer>(
          find.ancestor(
            of: find.text(label),
            matching: find.byType(AnimatedContainer),
          ),
        );
        return (box.decoration! as BoxDecoration).border as Border?;
      }

      for (final eink in [true, false]) {
        await tester.pumpWidget(
          MaterialApp(
            theme: _theme(eink: eink),
            home: Material(
              child: Column(
                children: [
                  Button.text(onPressed: () {}, child: const Text('t')),
                  Button.normal(onPressed: () {}, child: const Text('n')),
                  Button.filled(onPressed: () {}, child: const Text('f')),
                ],
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        BorderRadius? radiusOf(String label) {
          final box = tester.widget<AnimatedContainer>(
            find.ancestor(
              of: find.text(label),
              matching: find.byType(AnimatedContainer),
            ),
          );
          return (box.decoration! as BoxDecoration).borderRadius
              as BorderRadius?;
        }

        if (eink) {
          expect(radiusOf('t'), BorderRadius.circular(999));
          expect(radiusOf('n'), BorderRadius.circular(999));
          expect(borderOf('t')!.top.width, EInkStyle.strokeWidth);
          expect(borderOf('n')!.top.width, EInkStyle.strokeWidth);
        } else {
          expect(radiusOf('t'), BorderRadius.circular(16));
          expect(borderOf('t'), isNull);
          expect(borderOf('n'), isNull);
        }
        expect(borderOf('f'), isNull);
      }
    });

    testWidgets('tag outline helper is strokeWidth black in E-Ink only', (
      tester,
    ) async {
      final eink = await _context(tester, _theme(eink: true));
      final border = eink.einkBorder()!;
      expect(border.top.color, Colors.black);
      expect(border.top.width, EInkStyle.strokeWidth);
      final regular = await _context(tester, _theme(eink: false));
      expect(regular.einkBorder(), isNull);
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
