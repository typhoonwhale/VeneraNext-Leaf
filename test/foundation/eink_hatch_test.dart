import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:venera_next/components/select.dart';
import 'package:venera_next/foundation/eink_theme.dart';

void main() {
  group('einkHatchSegments', () {
    test('count follows size and perpendicular spacing', () {
      // c = k * 10 * sqrt2 < 200  ->  k = 1..14
      expect(einkHatchSegments(const Size(100, 100), 10), hasLength(14));
      expect(einkHatchSegments(const Size(100, 100), 20), hasLength(7));
      expect(einkHatchSegments(Size.zero, 10), isEmpty);
    });

    test(
      'segments are 45 degrees, bottom-left to top-right, inside bounds',
      () {
        const size = Size(120, 40);
        final segs = einkHatchSegments(size, 10);
        expect(segs, isNotEmpty);
        for (final (a, b) in segs) {
          for (final p in [a, b]) {
            expect(p.dx, inInclusiveRange(0, size.width));
            expect(p.dy, inInclusiveRange(0, size.height));
          }
          expect(b.dx, greaterThan(a.dx));
          expect(a.dy, greaterThan(b.dy));
          expect(b.dx - a.dx, closeTo(a.dy - b.dy, 1e-9));
        }
        final d =
            (segs[1].$1.dx + segs[1].$1.dy) - (segs[0].$1.dx + segs[0].$1.dy);
        expect(d / math.sqrt2, closeTo(10, 1e-9));
      },
    );
  });

  test('painter clips drawing to the shape', () async {
    const size = Size(100, 40);
    final recorder = PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawColor(const Color(0xFF00FF00), BlendMode.src);
    const EInkHatchPainter(shape: StadiumBorder()).paint(canvas, size);
    final image = await recorder.endRecording().toImage(100, 40);
    final data = (await image.toByteData())!;
    int px(int x, int y) => data.getUint32((y * 100 + x) * 4);
    // Corner is outside the stadium: the green backdrop must survive.
    expect(px(0, 0), 0x00FF00FF);
    // Center is inside: painted white or black, never the backdrop.
    expect(px(50, 20), anyOf(0xFFFFFFFF, 0x000000FF));
  });

  test('painter strokes the shape outline on top when asked', () async {
    const size = Size(100, 40);
    final recorder = PictureRecorder();
    final canvas = Canvas(recorder);
    const EInkHatchPainter(
      shape: StadiumBorder(side: BorderSide(width: 2)),
      paintBorder: true,
      spacing: 1000,
    ).paint(canvas, size);
    final image = await recorder.endRecording().toImage(100, 40);
    final data = (await image.toByteData())!;
    int px(int x, int y) => data.getUint32((y * 100 + x) * 4);
    // Huge spacing leaves no hatch line here, so black comes from the outline.
    expect(px(50, 0), 0x000000FF);
    expect(px(50, 39), 0x000000FF);
    expect(px(50, 20), 0xFFFFFFFF);
  });

  testWidgets('disabled FilledButton hatch clips to and outlines the pill', (
    tester,
  ) async {
    final theme = applyEInkTheme(ThemeData.light());
    await tester.pumpWidget(
      MaterialApp(
        theme: theme,
        home: const Scaffold(
          body: Row(
            children: [
              Expanded(child: FilledButton(onPressed: null, child: Text('x'))),
            ],
          ),
        ),
      ),
    );
    final hatch = tester.widget<EInkHatch>(find.byType(EInkHatch));
    expect(hatch.shape, isA<StadiumBorder>());
    expect(hatch.paintBorder, isTrue);
  });

  group('halo label', () {
    Future<void> pump(
      WidgetTester tester, {
      required bool eink,
      required bool enabled,
    }) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: eink ? applyEInkTheme(ThemeData.light()) : ThemeData.light(),
          home: Scaffold(
            body: Column(
              children: [
                FilledButton.icon(
                  onPressed: enabled ? () {} : null,
                  icon: const Icon(Icons.download),
                  label: const Text('x'),
                ),
                Select(current: 'a', values: const ['a'], enabled: enabled),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    Finder inButton(Finder f) =>
        find.descendant(of: find.byType(FilledButton), matching: f);
    Finder inSelect(Finder f) =>
        find.descendant(of: find.byType(Select), matching: f);

    TextStyle effective(WidgetTester tester, Element e) {
      final text = e.widget as Text;
      return DefaultTextStyle.of(e).style.merge(text.style);
    }

    void expectHalo(WidgetTester tester, Finder texts) {
      expect(texts, findsNWidgets(2));
      final halo = effective(tester, texts.evaluate().first);
      expect(halo.foreground!.style, PaintingStyle.stroke);
      expect(halo.foreground!.strokeWidth, 2 * EInkStyle.hatchHaloWidth);
      expect(halo.foreground!.color, Colors.white);
      final top = effective(tester, texts.evaluate().last);
      expect(top.color, Colors.black);
      expect(top.foreground, isNull);
    }

    testWidgets('disabled button label is a black glyph over a white stroke', (
      tester,
    ) async {
      await pump(tester, eink: true, enabled: false);
      expectHalo(tester, inButton(find.text('x')));
      expect(
        inButton(find.byType(ColoredBox)).evaluate().where(
          (e) => (e.widget as ColoredBox).color == Colors.white,
        ),
        isEmpty,
      );
      final icons = inButton(find.byIcon(Icons.download));
      expect(icons, findsNWidgets(2));
      final shadows = [
        for (final e in icons.evaluate()) IconTheme.of(e).shadows,
      ];
      expect(shadows.first, hasLength(16));
      expect(shadows.first!.every((s) => s.color == Colors.white), isTrue);
      expect(shadows.first!.every((s) => s.blurRadius == 0), isTrue);
      expect(
        shadows.first!.every(
          (s) => (s.offset.distance - EInkStyle.hatchHaloWidth).abs() < 1e-9,
        ),
        isTrue,
      );
      expect(shadows.last, anyOf(isNull, isEmpty));
    });

    testWidgets('disabled Select text and arrow have a halo', (tester) async {
      await pump(tester, eink: true, enabled: false);
      expectHalo(tester, inSelect(find.text('a')));
      final arrows = inSelect(find.byIcon(Icons.arrow_drop_down));
      expect(arrows, findsNWidgets(2));
      expect(IconTheme.of(tester.element(arrows.first)).shadows, hasLength(16));
      expect(IconTheme.of(tester.element(arrows.last)).shadows, isNull);
    });

    testWidgets('enabled and non-E-Ink controls have no halo', (tester) async {
      await pump(tester, eink: true, enabled: true);
      expect(find.text('x'), findsOneWidget);
      expect(find.text('a'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await pump(tester, eink: false, enabled: false);
      expect(find.text('x'), findsOneWidget);
      expect(find.text('a'), findsOneWidget);
      expect(find.byType(EInkHatch), findsNothing);
    });

    testWidgets('halo does not change the disabled button size', (
      tester,
    ) async {
      await pump(tester, eink: true, enabled: true);
      final enabledSize = tester.getSize(find.byType(FilledButton));
      await tester.pumpWidget(const SizedBox());
      await pump(tester, eink: true, enabled: false);
      expect(tester.getSize(find.byType(FilledButton)), enabledSize);
      final texts = inButton(find.text('x'));
      expect(tester.getRect(texts.first), tester.getRect(texts.last));
      final icons = inButton(find.byIcon(Icons.download));
      expect(tester.getRect(icons.first), tester.getRect(icons.last));
    });

    testWidgets('disabled button with a spinner runs one animation', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: applyEInkTheme(ThemeData.light()),
          home: const Scaffold(
            body: FilledButton(
              onPressed: null,
              child: SizedBox.square(
                dimension: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.byType(EInkHatch), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(tester.binding.transientCallbackCount, 1);
    });

    testWidgets('a halo copy with a spinner has muted tickers', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: einkHaloStack(
              const CircularProgressIndicator(),
              const CircularProgressIndicator(),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.byType(CircularProgressIndicator), findsNWidgets(2));
      expect(tester.binding.transientCallbackCount, 1);
    });

    testWidgets('a GlobalKey child is not duplicated', (tester) async {
      final key = GlobalKey();
      await tester.pumpWidget(
        MaterialApp(
          theme: applyEInkTheme(ThemeData.light()),
          home: Scaffold(
            body: FilledButton(onPressed: null, child: Text('keyed', key: key)),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      expect(find.text('keyed'), findsOneWidget);
      expect(find.byType(EInkHatch), findsOneWidget);
    });

    test('einkHaloSafe accepts plain labels and refuses stateful ones', () {
      expect(einkHaloSafe(const Text('a')), isTrue);
      expect(
        einkHaloSafe(
          const Padding(
            padding: EdgeInsets.all(2),
            child: Row(children: [Icon(Icons.add), Text('a')]),
          ),
        ),
        isTrue,
      );
      expect(einkHaloSafe(const CircularProgressIndicator()), isFalse);
      expect(einkHaloSafe(const EInkProgressIndicator()), isFalse);
      expect(
        einkHaloSafe(
          const Row(
            children: [Text('a'), Checkbox(value: true, onChanged: null)],
          ),
        ),
        isFalse,
      );
      expect(einkHaloSafe(Text('a', key: GlobalKey())), isFalse);
      expect(
        einkHaloSafe(
          Text.rich(
            TextSpan(
              children: [WidgetSpan(child: Text('a', key: GlobalKey()))],
            ),
          ),
        ),
        isFalse,
      );
    });
  });
}
