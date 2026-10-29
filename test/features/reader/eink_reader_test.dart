import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:venera_next/app_shell/android_window_insets.dart';
import 'package:venera_next/features/reader/auto_reading.dart';
import 'package:venera_next/features/reader/comic_image.dart';
import 'package:venera_next/features/reader/information_footer.dart';
import 'package:venera_next/features/reader/platform_effects_controller.dart';
import 'package:venera_next/features/reader/progress_bar.dart';
import 'package:venera_next/features/reader/top_bar.dart';
import 'package:venera_next/features/reader/progress_navigation.dart';
import 'package:venera_next/features/reader/scaffold.dart';
import 'package:venera_next/features/reader/shell_data.dart';
import 'package:venera_next/foundation/image_work.dart';
import 'package:venera_next/foundation/reader_settings.dart';
import 'package:venera_next/main.dart' show getTheme;

// 1x1 transparent PNG.
final _png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGNgYGD4DwABBAEAHnOcQAAAAABJRU5ErkJggg==',
);

ThemeData _theme(bool eink) =>
    getTheme(Colors.blue, null, null, Brightness.light, eink: eink);

class _Fixture {
  final work = ImageWork();
  final favorites = ChangeNotifier();
  final progressIdentity = Object();
  double footerHeight = 4, footerFontSize = 11;

  Widget build(bool eink, Widget content) => MaterialApp(
    theme: _theme(eink),
    themeAnimationDuration: Duration.zero,
    home: Builder(
      builder: (context) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          padding: const EdgeInsets.fromLTRB(16, 24, 12, 20),
          viewPadding: const EdgeInsets.fromLTRB(16, 24, 12, 20),
          disableAnimations: true,
        ),
        child: AndroidWindowInsets(
          child: Scaffold(
            body: SizedBox.expand(
              child: ReaderScaffold(
                data: ReaderShellData(
                  comicId: 'book',
                  sourceKey: 'local',
                  title: 'Book',
                  chapterTitle: 'A chapter',
                  hasChapters: true,
                  vertical: true,
                  gallery: true,
                  animating: false,
                  onCommentsPage: false,
                  swipeToCollect: false,
                  preferences: ReaderSettings.resolve(
                    global: {
                      'readerInformationMode': 'footer',
                      'readerFooterHeight': footerHeight,
                      'readerFooterFontSize': footerFontSize,
                      'readerFooterShowChapter': true,
                      'showPageNumberInReader': true,
                      'enableClockAndBatteryInfoInReader': false,
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
                child: content,
              ),
            ),
          ),
        ),
      ),
    ),
  );

  Future<void> dispose() async {
    await work.dispose();
    favorites.dispose();
  }
}

/// Everything that determines how the footer looks: sizes, text styles and
/// fills, in tree order.
List<String> _footerLook(WidgetTester tester) {
  final footer = find.byType(ReaderInformationFooter);
  final out = <String>[
    'size ${tester.getSize(footer)}',
    'rect ${tester.getRect(footer)}',
  ];
  void visit(Element element) {
    final w = element.widget;
    if (w is Text) {
      final style = DefaultTextStyle.of(element).style.merge(w.style);
      out.add(
        'text ${w.data} ${style.fontSize} ${style.color} ${style.fontWeight} '
        '${style.height}',
      );
    } else if (w is ColoredBox) {
      out.add('fill ${w.color} ${(element.renderObject as RenderBox).size}');
    } else if (w is DecoratedBox) {
      out.add(
        'deco ${w.decoration} ${(element.renderObject as RenderBox).size}',
      );
    } else if (w is Divider) {
      out.add('divider ${w.thickness} ${w.color}');
    }
    element.visitChildren(visit);
  }

  visit(tester.element(footer));
  return out;
}

int _count(WidgetTester tester, Finder f) => tester.widgetList(f).length;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final (height, font) in [(7.0, 13.0), (4.0, 11.0)]) {
    testWidgets(
      'T12 footer looks identical in E-Ink and light ($height/$font)',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(667, 900));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final f = _Fixture()
          ..footerHeight = height
          ..footerFontSize = font;
        try {
          await tester.pumpWidget(
            f.build(false, const ColoredBox(color: Color(0xff758473))),
          );
          await tester.pump();
          final light = _footerLook(tester);
          await tester.pumpWidget(
            f.build(true, const ColoredBox(color: Color(0xff758473))),
          );
          await tester.pump();
          final eink = _footerLook(tester);
          expect(eink, light);
          expect(
            light.where((line) => line.startsWith('text')).length,
            greaterThan(0),
          );
          expect(tester.takeException(), isNull);
        } finally {
          await tester.pumpWidget(const SizedBox());
          await f.dispose();
        }
      },
    );
  }

  testWidgets('T13 comic images get no filter, shader or blur in E-Ink', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(667, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final f = _Fixture();
    final filters = <Type>[ColorFiltered, ShaderMask, BackdropFilter];
    Finder anyFilter() => find.byWidgetPredicate(
      (w) => filters.contains(w.runtimeType),
      description: 'image filter widget',
    );
    try {
      Future<void> pump(bool eink) async {
        await tester.pumpWidget(
          f.build(eink, ComicImage(image: MemoryImage(_png))),
        );
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)),
        );
        await tester.pump();
        final shell = tester.state<ReaderScaffoldState>(
          find.byType(ReaderScaffold),
        );
        shell.openOrClose();
        await tester.pump();
      }

      await pump(false);
      expect(find.byType(ComicImage), findsOneWidget);
      final regularFilters = _count(tester, anyFilter());
      expect(
        find.ancestor(of: find.byType(ComicImage), matching: anyFilter()),
        findsNothing,
      );
      // The regular theme blurs the opened menu bars, proving the probe works.
      expect(_count(tester, find.byType(BackdropFilter)), greaterThan(0));

      await pump(true);
      expect(find.byType(ComicImage), findsOneWidget);
      expect(find.byType(ReaderInformationFooter), findsOneWidget);
      expect(
        find.ancestor(of: find.byType(ComicImage), matching: anyFilter()),
        findsNothing,
      );
      expect(_count(tester, anyFilter()), lessThan(regularFilters));
      expect(_count(tester, find.byType(BackdropFilter)), 0);
      expect(_count(tester, find.byType(ColorFiltered)), 0);
      expect(_count(tester, find.byType(ShaderMask)), 0);
    } finally {
      await tester.pumpWidget(const SizedBox());
      await f.dispose();
    }
  });

  testWidgets('T11 reader menu snaps open and closed in one frame in E-Ink', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(667, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final f = _Fixture();
    try {
      await tester.pumpWidget(
        f.build(true, const ColoredBox(color: Color(0xff758473))),
      );
      await tester.pump();
      final shell = tester.state<ReaderScaffoldState>(
        find.byType(ReaderScaffold),
      );
      final top = find.byType(ReaderTopBar);
      final bottom = find.byType(ReaderBottomBar);
      final screen = tester.getRect(find.byType(ReaderScaffold));

      bool opened() =>
          tester.getRect(top).top == screen.top &&
          tester.getRect(bottom).bottom == screen.bottom;
      bool closed() =>
          tester.getRect(top).bottom <= screen.top &&
          tester.getRect(bottom).top >= screen.bottom;

      expect(closed(), isTrue);
      shell.openOrClose();
      await tester.pump();
      expect(opened(), isTrue);
      // One trailing frame may flush bookkeeping; no ticker may remain.
      await tester.pump();
      expect(tester.binding.hasScheduledFrame, isFalse);
      shell.openOrClose();
      await tester.pump();
      expect(closed(), isTrue);
      // One trailing frame may flush bookkeeping; no ticker may remain.
      await tester.pump();
      expect(tester.binding.hasScheduledFrame, isFalse);

      for (var i = 1; i <= 5; i++) {
        shell.openOrClose();
        await tester.pump();
        expect(shell.isOpen, i.isOdd);
        expect(opened(), i.isOdd);
        expect(closed(), i.isEven);
      }

      expect(find.byType(BackdropFilter), findsNothing);
      for (final bar in [top, bottom]) {
        final fills = tester
            .widgetList<Container>(
              find.descendant(of: bar, matching: find.byType(Container)),
            )
            .map((c) => (c.decoration as BoxDecoration?)?.color)
            .whereType<Color>();
        expect(fills, isNotEmpty);
        expect(fills.first.a, 1.0);
      }
    } finally {
      await tester.pumpWidget(const SizedBox());
      await f.dispose();
    }
  });
}
