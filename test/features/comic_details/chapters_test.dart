import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:venera_next/components/menu.dart';
import 'package:venera_next/features/comic_details/chapter_menu.dart';
import 'package:venera_next/features/comic_details/chapters.dart';
import 'package:venera_next/features/comic_source/models.dart';
import 'package:venera_next/features/history/history_model.dart';
import 'package:venera_next/foundation/appdata.dart';
import 'package:venera_next/foundation/comic_type.dart';
import 'package:venera_next/foundation/eink_theme.dart';
import 'package:venera_next/main.dart' show getTheme;

const normal = ComicChapters({'a': 'First', 'b': 'Second', 'c': 'Third'});
const grouped = ComicChapters.grouped({
  'G1': {'a': 'Other'},
  'G2': {'b': 'First', 'c': 'Second', 'd': 'Third'},
});

History historyFor({required bool grouped, required int last}) => History(
  type: const ComicType(17),
  time: DateTime(2026),
  title: 'Book',
  subtitle: '',
  cover: '',
  ep: last,
  group: grouped ? 2 : null,
  page: 8,
  id: 'book',
  readEpisode: {grouped ? '2-1' : '1'},
  viewedEpisode: {grouped ? '2-1' : '1', grouped ? '2-2' : '2'},
  maxPage: null,
  readDurationMs: 0,
);

void main() {
  for (final eink in [false, true]) {
    for (final isGrouped in [false, true]) {
      for (final reverse in [false, true]) {
        for (final last in [1, 2, 3]) {
          testWidgets(
            'three states; eink=$eink grouped=$isGrouped reverse=$reverse last=$last',
            (tester) async {
              final previous = appdata.settings['reverseChapterOrder'];
              appdata.settings['reverseChapterOrder'] = reverse;
              addTearDown(
                () => appdata.settings['reverseChapterOrder'] = previous,
              );
              final selected = <int>[];
              final theme = getTheme(
                Colors.blue,
                null,
                null,
                Brightness.light,
                eink: eink,
              );
              await tester.pumpWidget(
                MaterialApp(
                  theme: theme,
                  home: Scaffold(
                    body: CustomScrollView(
                      slivers: [
                        ComicChaptersView(
                          chapters: isGrouped ? grouped : normal,
                          history: historyFor(grouped: isGrouped, last: last),
                          readChapter: selected.add,
                        ),
                      ],
                    ),
                  ),
                ),
              );
              final labels = eink
                  ? ['First', 'Second', 'Third']
                  : ['✓ First', '○ Second', 'Third'];
              for (var i = 0; i < 3; i++) {
                final text = tester.widget<Text>(find.text(labels[i]));
                final cellFinder = find
                    .ancestor(
                      of: find.text(labels[i]),
                      matching: find.byType(Material),
                    )
                    .first;
                final cell = tester.widget<Material>(cellFinder);
                if (i + 1 == last) {
                  expect(
                    cell.color,
                    eink ? Colors.black : theme.colorScheme.secondaryContainer,
                  );
                  expect(
                    text.style?.color,
                    eink
                        ? Colors.white
                        : theme.colorScheme.onSecondaryContainer,
                  );
                  expect(text.style?.fontWeight, FontWeight.w600);
                } else if (eink) {
                  expect(cell.color, Colors.white);
                  expect(text.style?.color, Colors.black);
                } else {
                  expect(
                    text.style?.color,
                    i == 0 ? theme.colorScheme.outline : null,
                  );
                }
                if (eink && i == 0) {
                  final check = tester.widget<EInkCheckMark>(
                    find.descendant(
                      of: cellFinder,
                      matching: find.byType(EInkCheckMark),
                    ),
                  );
                  expect(check.color, last == 1 ? Colors.white : Colors.black);
                }
                if (eink && i == 1) {
                  final circle = tester.widget<Text>(
                    find.descendant(of: cellFinder, matching: find.text('○')),
                  );
                  expect(
                    circle.style?.color,
                    last == 2 ? Colors.white : Colors.black,
                  );
                }
              }
              final firstX = tester.getTopLeft(find.text(labels.first));
              final thirdX = tester.getTopLeft(find.text(labels.last));
              expect(
                reverse ? thirdX.dx < firstX.dx : firstX.dx < thirdX.dx,
                isTrue,
              );
              await tester.tap(find.text(labels[1]));
              expect(selected, [isGrouped ? 3 : 2]);
              expect(tester.takeException(), isNull);
            },
          );
        }
      }
    }
  }

  testWidgets(
    'manual mark creates history and redraws without a resume highlight',
    (tester) async {
      final comic = ComicDetails.fromJson({
        'title': 'Book',
        'cover': '',
        'tags': <String, dynamic>{},
        'sourceKey': 'test',
        'comicId': 'book',
        'chapters': normal.toJson(),
      });
      History? history;
      final menu = MenuRouteController();
      addTearDown(menu.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) => CustomScrollView(
                slivers: [
                  ComicChaptersView(
                    chapters: normal,
                    history: history,
                    readChapter: (_) {},
                    onChapterMenu: (tileContext, chapter, anchor) {
                      final position = normal.positionAt(chapter);
                      menu.show(
                        tileContext,
                        anchor,
                        chapterMarkMenu(
                          position: position,
                          history: history,
                          onSelected: (action) => setState(() {
                            history = prepareChapterMark(
                              comic: comic,
                              latest: history,
                              position: position,
                              action: action,
                            );
                          }),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.longPress(find.text('Second'));
      await tester.pumpAndSettle();
      expect(find.text('Mark as unread'), findsNothing);
      await tester.tap(find.text('Mark as read'));
      await tester.pumpAndSettle();
      expect(find.text('✓ Second'), findsOneWidget);
      expect(history!.ep, 0);
      expect(history!.page, 0);
      expect(
        tester.widget<Text>(find.text('✓ Second')).style?.fontWeight,
        isNull,
      );
      await tester.longPress(find.text('✓ Second'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Mark as unread'));
      await tester.pumpAndSettle();
      expect(find.text('Second'), findsOneWidget);
      expect(history!.readEpisode, isEmpty);
      expect(history!.viewedEpisode, isEmpty);
    },
  );

  for (final reverse in [false, true]) {
    testWidgets(
      'long press and right click pass original grouped index; reverse=$reverse',
      (tester) async {
        final previous = appdata.settings['reverseChapterOrder'];
        appdata.settings['reverseChapterOrder'] = reverse;
        addTearDown(() => appdata.settings['reverseChapterOrder'] = previous);
        final menu = MenuRouteController();
        addTearDown(menu.dispose);
        final selected = <ChapterMarkAction>[];
        final indices = <int>[];
        // Legacy flat read key must still win over the new viewed key.
        final history = historyFor(grouped: true, last: 0)..readEpisode = {'2'};
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: CustomScrollView(
                slivers: [
                  ComicChaptersView(
                    chapters: grouped,
                    history: history,
                    readChapter: (_) {},
                    onChapterMenu: (context, chapter, anchor) {
                      indices.add(chapter);
                      menu.show(
                        context,
                        anchor,
                        chapterMarkMenu(
                          position: grouped.positionAt(chapter),
                          history: history,
                          onSelected: selected.add,
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        );
        expect(find.text('✓ First'), findsOneWidget);
        await tester.longPress(find.text('○ Second'));
        await tester.pumpAndSettle();
        expect(find.text('Mark as read'), findsOneWidget);
        expect(find.text('Mark as unread'), findsOneWidget);
        expect(find.text('Mark previous chapters as read'), findsOneWidget);
        await tester.tap(find.text('Mark as unread'));
        await tester.pumpAndSettle();
        expect(selected, [ChapterMarkAction.unread]);
        final mouse = await tester.createGesture(
          kind: PointerDeviceKind.mouse,
          buttons: kSecondaryMouseButton,
        );
        await mouse.down(tester.getCenter(find.text('✓ First')));
        await mouse.up();
        await tester.pumpAndSettle();
        expect(indices, [3, 2]);
        expect(find.text('Mark as read'), findsNothing);
        expect(find.text('Mark as unread'), findsOneWidget);
        expect(find.text('Mark previous chapters as read'), findsNothing);
        menu.close();
        await tester.pumpAndSettle();
      },
    );
  }
}
