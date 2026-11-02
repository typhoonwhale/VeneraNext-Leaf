import 'dart:io';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import 'package:venera_next/features/reader/continuous_data.dart';
import 'package:venera_next/features/reader/continuous_view.dart';
import 'package:venera_next/features/reader/gallery_data.dart';
import 'package:venera_next/features/reader/gallery_view.dart';
import 'package:venera_next/features/reader/page_layout.dart';
import 'package:venera_next/features/reader/read_progress_tracker.dart';
import 'package:venera_next/features/reader/reader_controller.dart';
import 'package:venera_next/features/reader/reader_viewport.dart';
import 'package:venera_next/foundation/image_work.dart';
import 'package:venera_next/foundation/eink_theme.dart';
import 'package:venera_next/main.dart' show getTheme;

Future<void> pumpImages(WidgetTester tester) async {
  for (var i = 0; i < 25; i++) {
    await tester.pump(const Duration(milliseconds: 20));
    await tester.runAsync(() => pumpEventQueue());
  }
}

Future<void> closeImages(WidgetTester tester, ImageWork work) async {
  final closing = work.dispose();
  var closed = false;
  unawaited(
    closing.then<void>(
      (_) => closed = true,
      onError: (Object e, StackTrace s) => closed = true,
    ),
  );
  while (!closed) {
    await tester.pump();
    await tester.runAsync(() => pumpEventQueue());
  }
  await closing;
}

void main() {
  for (final (reverse, lastChapter) in [
    (false, true),
    (true, true),
    (false, false),
    (true, false),
  ]) {
    testWidgets(
      'short double spread completes on real end swipe reverse=$reverse lastChapter=$lastChapter',
      (tester) async {
        final directory = Directory.systemTemp.createTempSync(
          'read-state-gallery-',
        );
        final file = File('${directory.path}/page.png')
          ..writeAsBytesSync(img.encodePng(img.Image(width: 40, height: 80)));
        final images = List.filled(2, 'file://${file.path}');
        final tracker = ReaderProgressTracker();
        final binding = ReaderViewportBinding();
        final work = ImageWork();
        var completed = false;
        const layout = ReaderPageLayout(
          imagesPerPage: 2,
          singleImageOnFirstPage: false,
        );
        late final ReaderController navigation;
        void observe() {
          if (navigation.contentChapter != navigation.state.chapter) return;
          final (first, last) = layout.imageRange(navigation.state.page, 2);
          final result = tracker.observe(
            key: '1',
            ordinal: 1,
            imageCount: 2,
            firstImage: first + 1,
            lastImage: last,
            cause: navigation.takePositionCause(),
          );
          completed |= result.any((v) => v.completed);
        }

        navigation = ReaderController(
          pageCount: () => 1,
          chapterCount: () => lastChapter ? 1 : 2,
          animationEnabled: () => false,
          viewport: () => binding.current,
          onChanged: () {},
          onPageChanged: observe,
          onError: (_, _) {},
          onForwardPastEnd: () =>
              completed |= tracker.forwardPastEnd()?.completed ?? false,
        )..replaceChapterImages(images);
        observe();
        try {
          await tester.pumpWidget(
            MaterialApp(
              theme: getTheme(
                Colors.blue,
                null,
                null,
                Brightness.light,
                eink: true,
              ),
              builder: (_, child) =>
                  EInkReduceMotion(enabled: true, child: child!),
              home: ReaderGalleryView(
                data: ReaderGalleryData(
                  content: navigation.content,
                  layout: layout,
                  vertical: false,
                  reverse: reverse,
                  commentsAtEnd: false,
                  firstChapter: true,
                  lastChapter: lastChapter,
                  preloadCount: 0,
                  doubleTapCollect: false,
                  centerLongPressZoom: false,
                  pageAnimation: false,
                  sourceKey: null,
                  comicId: 'book',
                  chapterId: '1',
                ),
                imageWork: work,
                navigation: navigation,
                onViewportChanged: binding.update,
                onReady: () {},
                onPageReported: (_, _) {},
                onChapterChanged: () {
                  if (!lastChapter) {
                    final attempt = navigation.beginContentLoad();
                    navigation.failContentLoad(
                      attempt,
                      StateError('Next chapter returned no images'),
                    );
                  }
                },
                onCollectImage: () {},
                readerSize: () => const Size(800, 600),
                readImage: (_) async => file.readAsBytesSync(),
                commentsBuilder: (_) => const SizedBox(),
              ),
            ),
          );
          await pumpImages(tester);
          expect(completed, isFalse);
          await tester.drag(
            find.byType(PageView),
            Offset(reverse ? 700 : -700, 0),
          );
          await pumpImages(tester);
          expect(completed, isTrue);
          if (!lastChapter) {
            expect(navigation.state.chapter, 2);
            expect(navigation.content.error, contains('returned no images'));
            expect(navigation.contentChapter, 1);
          }
          expect(tester.takeException(), isNull);
        } finally {
          await tester.pumpWidget(const SizedBox());
          await closeImages(tester, work);
          navigation.dispose();
          directory.deleteSync(recursive: true);
        }
      },
    );
  }

  for (final waterfall in [false, true]) {
    testWidgets(
      'continuous last chapter visible tail and end gesture waterfall=$waterfall',
      (tester) async {
        final directory = Directory.systemTemp.createTempSync(
          'read-state-continuous-',
        );
        final file = File('${directory.path}/page.png')
          ..writeAsBytesSync(img.encodePng(img.Image(width: 40, height: 80)));
        final imageKey = 'file://${file.path}';
        final tracker = ReaderProgressTracker();
        final binding = ReaderViewportBinding();
        final work = ImageWork();
        var completed = false;
        var visibleReports = 0;
        var forwardVisible = false;
        tracker.observe(
          key: '1',
          ordinal: 1,
          imageCount: 1,
          firstImage: 1,
          lastImage: 1,
          cause: ReaderPositionCause.remap,
          countProgress: false,
        );
        final navigation = ReaderController(
          pageCount: () => 1,
          chapterCount: () => 1,
          animationEnabled: () => false,
          viewport: () => binding.current,
          onChanged: () {},
          onPageChanged: () {},
          onError: (_, _) {},
          onVisibleImages: (chapter, count, first, last, forward) {
            visibleReports++;
            forwardVisible |= forward;
            completed |= tracker
                .observeVisible(
                  key: '$chapter',
                  imageCount: count,
                  firstImage: first,
                  lastImage: last,
                  forward: forward,
                )
                .completed;
          },
          onForwardPastEnd: () =>
              completed |= tracker.forwardPastEnd()?.completed ?? false,
        )..replaceChapterImages([imageKey]);
        try {
          await tester.pumpWidget(
            MaterialApp(
              theme: getTheme(
                Colors.blue,
                null,
                null,
                Brightness.light,
                eink: true,
              ),
              builder: (_, child) =>
                  EInkReduceMotion(enabled: true, child: child!),
              home: ReaderContinuousView(
                data: ReaderContinuousData(
                  vertical: true,
                  reverse: false,
                  crossChapter: waterfall,
                  firstChapter: true,
                  lastChapter: true,
                  maxChapter: 1,
                  preloadCount: 0,
                  splitWideImages: false,
                  invertSplit: false,
                  scrollSpeed: 1,
                  limitImageWidth: false,
                  sideMargin: 0,
                  doubleTapCollect: false,
                  centerLongPressZoom: false,
                  sourceKey: null,
                  comicId: 'book',
                ),
                imageWork: work,
                navigation: navigation,
                loadChapter: (_, _) async => [imageKey],
                chapterId: (_) => '1',
                chapterTitle: (_) => 'One',
                onViewportChanged: binding.update,
                onUpdate: () {},
                onFloatingButton: (_) {},
                onCollectImage: () {},
                onActiveChapterChanged: () {},
                onContentLoading: (_) {},
                onPreviousError: (_, _) {},
                onNavigationError: (_, _, _) {},
                readerSize: () => const Size(800, 600),
                readImage: (_) async => file.readAsBytesSync(),
              ),
            ),
          );
          await pumpImages(tester);
          expect(completed, isFalse);
          expect(navigation.positionCause, ReaderPositionCause.user);
          await tester.fling(
            find.byType(ScrollablePositionedList),
            const Offset(0, -2200),
            3000,
          );
          await pumpImages(tester);
          expect(visibleReports, greaterThan(0));
          expect(forwardVisible, isTrue);
          expect(completed, isTrue);
          expect(tester.takeException(), isNull);
        } finally {
          await tester.pumpWidget(const SizedBox());
          await closeImages(tester, work);
          navigation.dispose();
          directory.deleteSync(recursive: true);
        }
      },
    );
  }
}
