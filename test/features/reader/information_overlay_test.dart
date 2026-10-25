import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:venera_next/features/reader/auto_reading.dart';
import 'package:venera_next/features/reader/information_footer.dart';
import 'package:venera_next/features/reader/brightness.dart';
import 'package:venera_next/features/reader/platform_effects_controller.dart';
import 'package:venera_next/features/reader/progress_bar.dart';
import 'package:venera_next/features/reader/progress_navigation.dart';
import 'package:venera_next/features/reader/scaffold.dart';
import 'package:venera_next/features/reader/shell_data.dart';
import 'package:venera_next/features/reader/status_info.dart';
import 'package:venera_next/foundation/image_work.dart';
import 'package:venera_next/foundation/reader_settings.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const battery = MethodChannel('dev.fluttercommunity.plus/battery');
  setUpAll(() async {
    final path = Platform.environment['INFORMATION_QA_FONT'];
    if (path == null) return;
    await (FontLoader(
      'InformationQA',
    )..addFont(File(path).readAsBytes().then(ByteData.sublistView))).load();
    await (FontLoader('MaterialIcons')..addFont(
          File(
            'build/windows/x64/runner/Release/data/flutter_assets/fonts/MaterialIcons-Regular.otf',
          ).readAsBytes().then(ByteData.sublistView),
        ))
        .load();
  });
  tearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(battery, null),
  );

  for (final scenario in [
    (size: const Size(375, 667), scale: 1.0, dark: false),
    (size: const Size(375, 667), scale: 3.2, dark: true),
    (size: const Size(667, 375), scale: 1.0, dark: true),
    (size: const Size(667, 375), scale: 3.2, dark: false),
    (size: const Size(1024, 768), scale: 2.0, dark: false),
    (size: const Size(320, 568), scale: 3.2, dark: true),
  ]) {
    testWidgets('information stays readable inside safe area $scenario', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(scenario.size);
      addTearDown(() => tester.binding.setSurfaceSize(null));
      var batteryReads = 0;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(battery, (call) async {
            if (call.method == 'getBatteryLevel') {
              batteryReads++;
              return 85;
            }
            return 'discharging';
          });
      final f = _Fixture();
      try {
        Future<void> mount() async {
          await tester.pumpWidget(f.build(scenario.scale, scenario.dark));
          await tester.pump();
        }

        await mount();
        final status = tester.state(find.byType(ReaderStatusInfo));
        void checkBounds() {
          final safe = Rect.fromLTRB(
            f.padding.left,
            f.padding.top,
            scenario.size.width - f.padding.right,
            scenario.size.height - f.padding.bottom,
          );
          for (final type in [ReaderPageInfo, ReaderStatusInfo]) {
            final bounds = tester.getRect(find.byType(type));
            expect(bounds.left, greaterThanOrEqualTo(safe.left));
            expect(bounds.right, lessThanOrEqualTo(safe.right));
            expect(bounds.top, greaterThanOrEqualTo(safe.top));
            expect(bounds.bottom, lessThanOrEqualTo(safe.bottom));
          }
          expect(
            tester
                .getRect(find.byType(ReaderPageInfo))
                .overlaps(tester.getRect(find.byType(ReaderStatusInfo))),
            isFalse,
          );
          expect(tester.takeException(), isNull);
          for (final element in find.text('4/12').evaluate()) {
            expect(
              (element.findRenderObject()! as RenderParagraph)
                  .didExceedMaxLines,
              isFalse,
            );
          }
          expect(find.text('4/12'), findsNWidgets(2));
        }

        checkBounds();
        expect(find.text('85%'), findsNWidgets(2));
        for (final type in [ReaderPageInfo, ReaderStatusInfo]) {
          await tester.tapAt(tester.getCenter(find.byType(type)));
        }
        expect(
          f.taps,
          2,
          reason: 'Information must not intercept reading taps.',
        );
        final directory = Platform.environment['INFORMATION_QA_DIR'];
        if (directory != null) {
          await tester.runAsync(() async {
            final boundary =
                f.repaint.currentContext!.findRenderObject()!
                    as RenderRepaintBoundary;
            final frame = await boundary.toImage();
            try {
              final data = await frame.toByteData(
                format: ui.ImageByteFormat.png,
              );
              await File(
                '$directory/${scenario.size.width.toInt()}-${scenario.dark ? 'dark' : 'light'}-${scenario.scale}.png',
              ).writeAsBytes(data!.buffer.asUint8List());
            } finally {
              frame.dispose();
            }
          });
        }
        f.padding = const EdgeInsets.fromLTRB(40, 24, 16, 48);
        await mount();
        checkBounds();
        expect(tester.state(find.byType(ReaderStatusInfo)), same(status));
        f.showPage = false;
        await mount();
        expect(find.byType(ReaderPageInfo), findsNothing);
        expect(tester.state(find.byType(ReaderStatusInfo)), same(status));
        expect(
          batteryReads,
          1,
          reason: 'Changing page visibility must not replace polling.',
        );
        f.showPage = true;
        f.showStatus = false;
        await mount();
        expect(find.byType(ReaderStatusInfo), findsNothing);
        expect(find.byType(ReaderPageInfo), findsOneWidget);
        await tester.pump(const Duration(seconds: 3));
        expect(batteryReads, 1);
        f.showPage = false;
        await mount();
        expect(find.byType(ReaderPageInfo), findsNothing);
        f.showPage = true;
        f.showStatus = true;
        f.comments = true;
        await mount();
        expect(find.byType(ReaderPageInfo), findsNothing);
        expect(find.byType(ReaderStatusInfo), findsNothing);
      } finally {
        await tester.pumpWidget(const SizedBox());
        await f.work.dispose();
        f.favorites.dispose();
      }
    });
  }

  testWidgets(
    'footer uses white and black in light theme and dark theme colors',
    (tester) async {
      final f = _Fixture()..gallery = true;
      try {
        for (final dark in [false, true]) {
          await tester.pumpWidget(f.build(1, dark));
          await tester.pump(const Duration(milliseconds: 300));
          final footer = find.byType(ReaderInformationFooter);
          final context = tester.element(footer);
          final colors = Theme.of(context).colorScheme;
          final background = tester.widget<ColoredBox>(
            find
                .descendant(of: footer, matching: find.byType(ColoredBox))
                .first,
          );
          final page = tester.widget<Text>(find.text('4/12'));
          expect(background.color, dark ? colors.surface : Colors.white);
          expect(page.style!.color, dark ? colors.onSurface : Colors.black);
          final divider = find.byKey(const ValueKey('reader-footer-divider'));
          final dividerColor = tester.widget<ColoredBox>(divider).color;
          expect(dividerColor, dark ? colors.onSurface : Colors.black);
          expect(tester.getRect(divider).height, 1);
          expect(
            tester.getRect(divider).width,
            tester.getRect(footer).width,
            reason: 'The divider spans the full information bar.',
          );
        }
      } finally {
        await tester.pumpWidget(const SizedBox());
        await f.work.dispose();
        f.favorites.dispose();
      }
    },
  );

  for (final size in [const Size(320, 568), const Size(667, 375)]) {
    for (final scale in [1.0, 3.2]) {
      testWidgets(
        'footer reserves viewport and blocks reading taps $size/$scale',
        (tester) async {
          await tester.binding.setSurfaceSize(size);
          addTearDown(() => tester.binding.setSurfaceSize(null));
          final f = _Fixture()..gallery = true;
          try {
            Future<void> mount() async {
              await tester.pumpWidget(f.build(scale, false));
              await tester.pump();
            }

            await mount();
            final footerFinder = find.byType(ReaderInformationFooter);
            final viewportFinder = find.byKey(
              const ValueKey('reader-content-viewport'),
            );
            final viewport = tester.getRect(viewportFinder);
            final footer = tester.getRect(footerFinder);
            expect(viewport.bottom, footer.top);
            expect(viewport.overlaps(footer), isFalse);
            expect(
              tester.getRect(find.byType(ReaderBrightnessOverlay)),
              viewport,
            );
            expect(
              tester.widget<ClipRect>(viewportFinder).clipBehavior,
              Clip.hardEdge,
            );
            final childContext = tester.element(
              find.byKey(const ValueKey('reader-test-content')),
            );
            expect(MediaQuery.sizeOf(childContext), viewport.size);
            await tester.pump(const Duration(minutes: 1));
            expect(tester.getRect(viewportFinder), viewport);
            await tester.tapAt(footer.center);
            expect(f.taps, 0);
            await tester.tapAt(viewport.center);
            expect(f.taps, 1);
            final shell = tester.state<ReaderScaffoldState>(
              find.byType(ReaderScaffold),
            );
            shell.openOrClose();
            await tester.pump();
            expect(tester.getRect(viewportFinder), viewport);
            shell.openOrClose();
            await tester.pump();
            f.chapterTitle = 'A changed chapter ' * 30;
            await mount();
            expect(tester.getRect(viewportFinder), viewport);
            f.comments = true;
            await mount();
            expect(tester.getRect(viewportFinder), viewport);
            // Visibility retains layout/state while excluding paint and input.
            expect(find.text('4/12').hitTestable(), findsNothing);
            final visibility = tester.widget<Visibility>(
              find
                  .ancestor(
                    of: find.text('4/12'),
                    matching: find.byType(Visibility),
                  )
                  .first,
            );
            expect(visibility.visible, isFalse);
            f.comments = false;
            f.footerHeight = 25;
            f.footerFontSize = 13;
            await mount();
            expect(
              tester.getRect(viewportFinder).bottom,
              lessThanOrEqualTo(viewport.bottom),
            );
            expect(
              tester.element(find.byKey(const ValueKey('reader-test-content'))),
              same(childContext),
            );
            f.showPage = false;
            f.showStatus = false;
            f.showChapter = false;
            await mount();
            expect(footerFinder, findsNothing);
            expect(
              tester.getSize(find.byKey(const ValueKey('reader-test-content'))),
              size,
            );
            f.showPage = true;
            f.mode = 'hidden';
            await mount();
            expect(footerFinder, findsNothing);
            expect(find.byType(ReaderPageInfo), findsNothing);
            f.mode = 'overlay';
            await mount();
            expect(
              tester.element(find.byKey(const ValueKey('reader-test-content'))),
              same(childContext),
            );
            expect(find.byType(ReaderPageInfo), findsOneWidget);
            expect(tester.takeException(), isNull);
          } finally {
            await tester.pumpWidget(const SizedBox());
            await f.work.dispose();
            f.favorites.dispose();
          }
        },
      );
    }
  }

  testWidgets(
    'footer chapter capacity stays stable and grows without truncation',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(320, 568));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      double? reservedHeight;
      for (final maxPage in [9, 99, 999, 10000, 99999, 100000]) {
        await tester.pumpWidget(
          MaterialApp(
            home: MediaQuery(
              data: const MediaQueryData(
                size: Size(320, 568),
                textScaler: TextScaler.linear(3.2),
                padding: EdgeInsets.fromLTRB(16, 24, 12, 20),
              ),
              child: Align(
                alignment: Alignment.bottomCenter,
                child: ReaderInformationFooter(
                  page: maxPage,
                  maxPage: maxPage,
                  showPage: true,
                  showStatus: true,
                  height: 18,
                  fontSize: 11,
                ),
              ),
            ),
          ),
        );
        await tester.pump();
        final height = tester
            .getSize(find.byType(ReaderInformationFooter))
            .height;
        reservedHeight ??= height;
        if (maxPage <= 99999) {
          expect(height, reservedHeight);
        } else {
          expect(height, greaterThanOrEqualTo(reservedHeight));
        }
        final page = find.text('$maxPage/$maxPage');
        expect(page, findsOneWidget);
        final paragraph = tester.renderObject<RenderParagraph>(page);
        expect(paragraph.didExceedMaxLines, isFalse);
        expect(tester.takeException(), isNull);
      }
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'compact footer honors configured heights and grows without overlap',
    (tester) async {
      const size = Size(667, 375);
      await tester.binding.setSurfaceSize(size);
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final f = _Fixture()
        ..gallery = true
        ..padding = const EdgeInsets.fromLTRB(16, 24, 12, 0)
        ..footerHeight = 18
        ..footerFontSize = 11
        ..showChapter = false;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('dev.fluttercommunity.plus/battery'),
            (call) async =>
                call.method == 'getBatteryLevel' ? 85 : 'discharging',
          );
      try {
        Future<void> mount(double scale) async {
          await tester.pumpWidget(f.build(scale, false));
          await tester.pump();
        }

        double contentHeight() =>
            tester.getRect(find.byType(ReaderInformationFooter)).height -
            f.padding.bottom;

        void expectBottomAligned(Finder finder) {
          final targetBottom =
              tester.getRect(find.byType(ReaderInformationFooter)).bottom -
              f.padding.bottom;
          expect(tester.getRect(finder).bottom, closeTo(targetBottom, 0.01));
        }

        await mount(1);
        expect(contentHeight(), 18);
        final page = find.text('4/12');
        final status = find.byType(ReaderStatusInfo);
        expectBottomAligned(page);
        expectBottomAligned(status);

        f.padding = const EdgeInsets.fromLTRB(16, 24, 12, 20);
        await mount(1);
        expect(contentHeight(), 18);
        expectBottomAligned(page);
        expectBottomAligned(status);

        f.footerHeight = 15;
        f.footerFontSize = 9;
        await mount(1);
        expect(contentHeight(), 15);

        f.footerFontSize = 13;
        f.showChapter = true;
        f.title = 'A very long book title ' * 8;
        f.chapterTitle = 'A very long chapter title ' * 8;
        await mount(1);
        final largeFontHeight = contentHeight();
        expect(largeFontHeight, greaterThan(15));
        final title = find.byKey(const ValueKey('reader-footer-title'));
        expect(tester.renderObject<RenderParagraph>(title).maxLines, 1);
        expect(tester.getRect(title).overlaps(tester.getRect(status)), isFalse);
        expect(tester.getRect(page).overlaps(tester.getRect(status)), isFalse);
        expectBottomAligned(title);
        expectBottomAligned(status);
        expectBottomAligned(page);

        f.title = 'Book';
        f.chapterTitle = 'Chapter';
        await mount(1);
        expect(contentHeight(), closeTo(largeFontHeight, 0.01));

        f.title = 'A very long book title ' * 8;
        f.chapterTitle = 'A very long chapter title ' * 8;
        await tester.binding.setSurfaceSize(const Size(320, 568));
        await mount(3.2);
        expect(contentHeight(), greaterThan(largeFontHeight));
        final titleRect = tester.getRect(title);
        final pageRect = tester.getRect(page);
        final statusRect = tester.getRect(status);
        expect(titleRect.overlaps(statusRect), isFalse);
        expect(pageRect.overlaps(statusRect), isFalse);
        expect(titleRect.bottom, closeTo(pageRect.bottom, 0.01));
        expect(pageRect.bottom, lessThan(statusRect.top));
        expectBottomAligned(status);
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox());
        await f.work.dispose();
        f.favorites.dispose();
      }
    },
  );

  testWidgets('footer title follows shell data and the existing preference', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(375, 667));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final f = _Fixture()
      ..gallery = true
      ..showPage = false
      ..showStatus = false
      ..title = 'Reader widget book';
    try {
      Future<void> mount() async {
        await tester.pumpWidget(f.build(1, false));
        await tester.pump();
      }

      await mount();
      expect(find.byType(ReaderInformationFooter), findsOneWidget);
      expect(
        find.text('Reader widget book｜A very long chapter title'),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('reader-footer-title')), findsOneWidget);

      f.chapterTitle = null;
      await mount();
      expect(find.text('Reader widget book｜E2'), findsOneWidget);

      f.hasChapters = false;
      await mount();
      expect(
        find.descendant(
          of: find.byType(ReaderInformationFooter),
          matching: find.text('Reader widget book'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byType(ReaderInformationFooter),
          matching: find.textContaining('｜'),
        ),
        findsNothing,
      );

      f.title = '  ';
      f.hasChapters = true;
      f.chapterTitle = 'Chapter without book title';
      await mount();
      expect(
        find.descendant(
          of: find.byType(ReaderInformationFooter),
          matching: find.text('Chapter without book title'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byType(ReaderInformationFooter),
          matching: find.textContaining('｜'),
        ),
        findsNothing,
      );

      f.showChapter = false;
      f.showPage = true;
      await mount();
      expect(find.byType(ReaderInformationFooter), findsOneWidget);
      expect(find.byKey(const ValueKey('reader-footer-title')), findsNothing);
      expect(find.text('4/12'), findsOneWidget);
      expect(tester.takeException(), isNull);
    } finally {
      await tester.pumpWidget(const SizedBox());
      await f.work.dispose();
      f.favorites.dispose();
    }
  });

  testWidgets('page-off title ellipsizes without displacing status or height', (
    tester,
  ) async {
    const size = Size(320, 568);
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final f = _Fixture()
      ..gallery = true
      ..showPage = false
      ..showStatus = true
      ..title = 'A very long book title for a narrow reader window ' * 5
      ..chapterTitle =
          'A very long chapter title for a narrow reader window ' * 5;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('dev.fluttercommunity.plus/battery'),
          (call) async => call.method == 'getBatteryLevel' ? 85 : 'discharging',
        );
    try {
      Future<void> mount() async {
        await tester.pumpWidget(f.build(3.2, false));
        await tester.pump();
      }

      await mount();
      final footer = find.byType(ReaderInformationFooter);
      final title = find.byKey(const ValueKey('reader-footer-title'));
      final status = find.byType(ReaderStatusInfo);
      expect(footer, findsOneWidget);
      expect(title, findsOneWidget);
      expect(find.byType(ReaderPageInfo), findsNothing);
      final titleParagraph = tester.renderObject<RenderParagraph>(title);
      expect(titleParagraph.maxLines, 1);
      expect(titleParagraph.didExceedMaxLines, isTrue);
      final initialHeight = tester.getRect(footer).height;
      final titleRect = tester.getRect(title);
      final statusRect = tester.getRect(status);
      expect(titleRect.overlaps(statusRect), isFalse);
      expect(
        statusRect.right,
        lessThanOrEqualTo(size.width - f.padding.right - 12),
      );

      f.title = 'Book';
      f.chapterTitle = 'Chapter';
      await mount();
      expect(tester.getRect(footer).height, initialHeight);
      expect(tester.takeException(), isNull);
    } finally {
      await tester.pumpWidget(const SizedBox());
      await f.work.dispose();
      f.favorites.dispose();
    }
  });

  testWidgets('title-only footer reserves a large-text line without wrapping', (
    tester,
  ) async {
    const size = Size(320, 568);
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final f = _Fixture()
      ..gallery = true
      ..showPage = false
      ..showStatus = false
      ..title = 'A long book title in a narrow window ' * 5;
    try {
      Future<void> mount() async {
        await tester.pumpWidget(f.build(3.2, false));
        await tester.pump();
      }

      await mount();
      final footer = find.byType(ReaderInformationFooter);
      final title = find.byKey(const ValueKey('reader-footer-title'));
      expect(footer, findsOneWidget);
      expect(title, findsOneWidget);
      final titleRect = tester.getRect(title);
      final footerRect = tester.getRect(footer);
      final paragraph = tester.renderObject<RenderParagraph>(title);
      expect(paragraph.maxLines, 1);
      expect(paragraph.didExceedMaxLines, isTrue);
      expect(titleRect.height, greaterThan(11 * 3.2));
      expect(
        titleRect.bottom,
        lessThanOrEqualTo(footerRect.bottom - f.padding.bottom),
      );
      final initialHeight = footerRect.height;

      f.title = 'Book';
      await mount();
      expect(tester.getRect(footer).height, initialHeight);
      expect(tester.takeException(), isNull);
    } finally {
      await tester.pumpWidget(const SizedBox());
      await f.work.dispose();
      f.favorites.dispose();
    }
  });

  testWidgets('long page counts wrap without losing digits', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: SizedBox(
            width: 140,
            child: MediaQuery(
              data: const MediaQueryData(textScaler: TextScaler.linear(3.2)),
              child: const ReaderPageInfo(
                chapterTitle: 'A long chapter',
                page: 9999,
                maxPage: 10000,
              ),
            ),
          ),
        ),
      ),
    );
    for (final element in find.text('9999/10000').evaluate()) {
      final paragraph = element.findRenderObject()! as RenderParagraph;
      expect(paragraph.didExceedMaxLines, isFalse);
      expect(paragraph.size.width, lessThanOrEqualTo(140));
      expect(paragraph.size.height, greaterThan(14 * 3.2));
    }
    expect(find.text('9999/10000'), findsNWidgets(2));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'outlined information exposes each text once to assistive technology',
    (tester) async {
      final semantics = tester.ensureSemantics();
      try {
        await tester.pumpWidget(
          MaterialApp(
            home: Column(
              children: [
                const ReaderPageInfo(
                  chapterTitle: 'Chapter 2',
                  page: 4,
                  maxPage: 12,
                ),
                ReaderStatusInfo(
                  now: () => DateTime(2026, 10, 7, 12, 34),
                  readBattery: () async =>
                      const ReaderBatterySnapshot(85, charging: false),
                ),
              ],
            ),
          ),
        );
        await tester.pump();
        final labels = <String>[];
        void visit(SemanticsNode node) {
          labels.add(node.getSemanticsData().label);
          node.visitChildren((child) {
            visit(child);
            return true;
          });
        }

        visit(
          tester
              .binding
              .renderViews
              .single
              .owner!
              .semanticsOwner!
              .rootSemanticsNode!,
        );
        final all = labels.join('\n');
        for (final text in ['Chapter 2 : 4/12', '12:34', '85%']) {
          expect(
            RegExp(RegExp.escape(text)).allMatches(all),
            hasLength(1),
            reason: all,
          );
        }
      } finally {
        await tester.pumpWidget(const SizedBox());
        semantics.dispose();
      }
    },
  );
}

class _Fixture {
  final work = ImageWork();
  final favorites = ChangeNotifier();
  final repaint = GlobalKey();
  final progressIdentity = Object();
  var padding = const EdgeInsets.fromLTRB(16, 24, 12, 20);
  bool showPage = true, showStatus = true, comments = false;
  int taps = 0;
  bool gallery = false;
  String mode = 'footer';
  double footerHeight = 18, footerFontSize = 11;
  bool showChapter = true, hasChapters = true;
  String title = 'Book';
  String? chapterTitle = 'A very long chapter title';

  Widget build(double scale, bool dark) => MaterialApp(
    theme: ThemeData(
      brightness: dark ? Brightness.dark : Brightness.light,
      fontFamily: Platform.environment['INFORMATION_QA_FONT'] == null
          ? null
          : 'InformationQA',
    ),
    home: Builder(
      builder: (context) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          padding: padding,
          textScaler: TextScaler.linear(scale),
          disableAnimations: true,
        ),
        child: RepaintBoundary(
          key: repaint,
          child: Scaffold(
            body: SizedBox.expand(
              child: ReaderScaffold(
                data: ReaderShellData(
                  comicId: 'book',
                  sourceKey: 'local',
                  title: title,
                  chapterTitle: chapterTitle,
                  hasChapters: hasChapters,
                  vertical: true,
                  gallery: gallery,
                  animating: false,
                  onCommentsPage: comments,
                  swipeToCollect: false,
                  preferences: ReaderSettings.resolve(
                    global: {
                      'readerInformationMode': mode,
                      'readerFooterHeight': footerHeight,
                      'readerFooterFontSize': footerFontSize,
                      'readerFooterShowChapter': showChapter,
                      'showPageNumberInReader': showPage,
                      'enableClockAndBatteryInfoInReader': showStatus,
                    },
                  ),
                  automaticReading: AutoReadingStatus.stopped,
                ),
                progress: ReaderProgressRequest(
                  identity: progressIdentity,
                  page: 4,
                  maxPage: 12,
                  chapter: 2,
                  maxChapter: 3,
                  reversed: false,
                  isCurrent: () => true,
                  toPage: (_, {animated = true}) => true,
                  toChapter: (_) => true,
                ),
                onExit: () async {},
                onFullscreen: null,
                onToggleAutomaticReading: () => false,
                acquireSidebarPause: () => () {},
                readImagePickContext: () => null,
                imageWork: work,
                orientation: ReaderOrientation.system,
                onRotate: null,
                onSystemUiChanged: (_) {},
                createChapterMenu: () => null,
                favoriteChanges: favorites,
                createFavoriteQuery: () => null,
                createImageFavorite: () => null,
                createImageExport: () => null,
                createSettings: () => null,
                createChapterComments: () => null,
                chapterNavigation: null,
                child: GestureDetector(
                  key: const ValueKey('reader-test-content'),
                  behavior: HitTestBehavior.opaque,
                  onTap: () => taps++,
                  child: const ColoredBox(color: Color(0xff758473)),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
