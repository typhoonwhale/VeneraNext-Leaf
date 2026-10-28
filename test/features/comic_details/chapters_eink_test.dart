import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:venera_next/foundation/eink_theme.dart';
import 'package:venera_next/features/comic_details/chapters.dart';
import 'package:venera_next/features/comic_source/models.dart';
import 'package:venera_next/features/history/history_model.dart';
import 'package:venera_next/foundation/comic_type.dart';
import 'package:venera_next/main.dart' show getTheme;

History _history(int ep, Set<String> read, {int? group}) => History(
  type: const ComicType(17),
  time: DateTime(2026),
  title: 'Book',
  subtitle: '',
  cover: '',
  ep: ep,
  group: group,
  page: 1,
  id: 'book',
  readEpisode: read,
  maxPage: null,
  readDurationMs: 0,
);

const _normal = ComicChapters({
  'a': 'Ch1',
  'b': 'Ch2',
  'c': 'Ch3',
  'd': 'Ch4',
  'e': 'Ch5',
});

const _grouped = ComicChapters.grouped({
  'G1': {'a': 'A1', 'b': 'A2', 'c': 'A3'},
  'G2': {'d': 'B1', 'e': 'B2', 'f': 'B3'},
});

Future<ThemeData> _show(
  WidgetTester tester,
  ComicChapters chapters,
  History? history, {
  required bool eink,
}) async {
  final theme = getTheme(Colors.blue, null, null, Brightness.light, eink: eink);
  await tester.pumpWidget(
    MaterialApp(
      theme: theme,
      home: Scaffold(
        body: CustomScrollView(
          slivers: [
            ComicChaptersView(
              chapters: chapters,
              history: history,
              readChapter: (_) {},
            ),
          ],
        ),
      ),
    ),
  );
  return theme;
}

/// The Material that paints a chapter cell's background.
Material _cell(WidgetTester tester, String title) => tester.widget<Material>(
  find.ancestor(of: find.text(title), matching: find.byType(Material)).first,
);

bool _isBlack(Material m) => m.color == Colors.black;

int _blackCells(WidgetTester tester, Iterable<String> titles) =>
    titles.where((t) => _isBlack(_cell(tester, t))).length;

Finder _check(String title) => find.descendant(
  of: find.ancestor(of: find.text(title), matching: find.byType(Row)).first,
  matching: find.byType(EInkCheckMark),
);

void main() {
  const titles = ['Ch1', 'Ch2', 'Ch3', 'Ch4', 'Ch5'];

  testWidgets('eink normal: last read is black, other read is checked', (
    tester,
  ) async {
    await _show(tester, _normal, _history(3, {'1', '3', '4', '5'}), eink: true);
    expect(_isBlack(_cell(tester, 'Ch3')), isTrue);
    expect(_blackCells(tester, titles), 1);
    expect(find.byType(EInkCheckMark), findsNWidgets(3));
    for (final t in ['Ch1', 'Ch4', 'Ch5']) {
      final m = _cell(tester, t);
      expect(m.color, Colors.white);
      expect((m.shape as RoundedRectangleBorder).side.width, 2);
      expect(
        tester.widget<Text>(find.text(t)).style?.fontWeight,
        FontWeight.w600,
      );
      expect(_check(t), findsOneWidget);
    }
    expect(
      find.descendant(
        of: find
            .ancestor(of: find.text('Ch2'), matching: find.byType(Material))
            .first,
        matching: find.byType(EInkCheckMark),
      ),
      findsNothing,
    );
    expect(_cell(tester, 'Ch2').color, Colors.white);
  });

  testWidgets('eink normal: checkmark survives ellipsis', (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    const long = 'A very very very long chapter title that overflows';
    await _show(
      tester,
      const ComicChapters({'a': long, 'b': 'Short'}),
      _history(2, {'1', '2'}),
      eink: true,
    );
    expect(find.byType(EInkCheckMark), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('eink grouped: last read only in its own group', (tester) async {
    // Last read: group 2, ep 2 (B2). Group 1 also has an ep 2 read.
    final history = _history(2, {'1-2', '2-1', '2-2'}, group: 2);
    await _show(tester, _grouped, history, eink: true);
    // Initial tab is group 2.
    expect(_isBlack(_cell(tester, 'B2')), isTrue);
    expect(_blackCells(tester, ['B1', 'B2', 'B3']), 1);
    expect(_check('B1'), findsOneWidget);
    expect(_cell(tester, 'B3').color, Colors.white);
    await tester.tap(find.text('G1'));
    await tester.pumpAndSettle();
    expect(_blackCells(tester, ['A1', 'A2', 'A3']), 0);
    expect(_check('A2'), findsOneWidget);
    expect(find.byType(EInkCheckMark), findsOneWidget);
  });

  testWidgets('eink: no history means all unread', (tester) async {
    await _show(tester, _normal, null, eink: true);
    expect(_blackCells(tester, titles), 0);
    expect(find.byType(EInkCheckMark), findsNothing);
    await _show(tester, _grouped, null, eink: true);
    expect(find.byType(EInkCheckMark), findsNothing);
    expect(_blackCells(tester, ['A1', 'A2', 'A3']), 0);
  });

  testWidgets('normal mode keeps outline text and no checkmark', (
    tester,
  ) async {
    final theme = await _show(
      tester,
      _normal,
      _history(3, {'3', '4'}),
      eink: false,
    );
    expect(find.byType(EInkCheckMark), findsNothing);
    Color? color(String t) => tester.widget<Text>(find.text(t)).style?.color;
    expect(color('Ch3'), theme.colorScheme.outline);
    expect(color('Ch4'), theme.colorScheme.outline);
    expect(color('Ch1'), isNull);
    expect(_blackCells(tester, titles), 0);
  });
}
