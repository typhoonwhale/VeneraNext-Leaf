import 'package:flutter_test/flutter_test.dart';
import 'package:venera_next/features/comic_details/chapter_menu.dart';
import 'package:venera_next/features/comic_source/models.dart';
import 'package:venera_next/features/history/history_model.dart';

ComicDetails comicFor(ComicChapters chapters) => ComicDetails.fromJson({
  'title': 'Book',
  'cover': '',
  'tags': <String, dynamic>{},
  'sourceKey': 'test',
  'comicId': 'book',
  'chapters': chapters.toJson(),
});

const normal = ComicChapters({'a': 'A', 'b': 'B', 'c': 'C'});
const grouped = ComicChapters.grouped({
  'Volume': {'a': 'A', 'b': 'B'},
  'Serial': {'a': 'C', 'b': 'D', 'c': 'E'},
});

void main() {
  test('manual mark without history creates no resume position', () {
    final comic = comicFor(normal);
    final before = DateTime.now();
    final marked = prepareChapterMark(
      comic: comic,
      latest: null,
      position: normal.positionAt(2),
      action: ChapterMarkAction.read,
    );
    expect(marked.ep, 0);
    expect(marked.page, 0);
    expect(marked.group, isNull);
    expect(marked.id, comic.id);
    expect(marked.time.isBefore(before), isFalse);
    expect(marked.time.isAfter(DateTime.now()), isFalse);
    expect(marked.readEpisode, {'2'});
    expect(marked.viewedEpisode, isEmpty);
    final entries = chapterMarkMenu(
      position: normal.positionAt(1),
      history: null,
      onSelected: (_) {},
    );
    expect(entries.map((e) => e.text), ['Mark as read']);
  });

  test(
    'mark unread clears grouped and legacy marks on a detached snapshot',
    () {
      final comic = comicFor(grouped);
      final latest = History.fromModel(
        model: comic,
        ep: 2,
        page: 9,
        group: 2,
        time: DateTime(2025),
        readChapters: {'1-1', '2-2', '4'},
      )..viewedEpisode = {'2-2', '4', '2-3'};
      final marked = prepareChapterMark(
        comic: comic,
        latest: latest,
        position: grouped.positionAt(4),
        action: ChapterMarkAction.unread,
      );
      expect(marked.readEpisode, {'1-1'});
      expect(marked.viewedEpisode, {'2-3'});
      expect(marked.ep, latest.ep);
      expect(marked.page, latest.page);
      expect(marked.group, latest.group);
      expect(marked.time, latest.time);
      expect(latest.readEpisode, {'1-1', '2-2', '4'});
      expect(latest.viewedEpisode, {'2-2', '4', '2-3'});
      expect(
        chapterMarkMenu(
          position: grouped.positionAt(4),
          history: marked,
          onSelected: (_) {},
        ).map((e) => e.text),
        ['Mark as read', 'Mark previous chapters as read'],
      );
    },
  );

  for (final chapters in [normal, grouped]) {
    test(
      'previous chapters exclude selected chapter and stay in group: ${chapters.isGrouped}',
      () {
        final comic = comicFor(chapters);
        final selected = chapters.isGrouped ? 5 : 3;
        final latest = History.fromModel(model: comic, ep: 1, page: 4)
          ..viewedEpisode = chapters.isGrouped
              ? {'1-1', '2-1', '2-2', '2-3'}
              : {'1', '2', '3'};
        final marked = prepareChapterMark(
          comic: comic,
          latest: latest,
          position: chapters.positionAt(selected),
          action: ChapterMarkAction.previous,
        );
        expect(
          marked.readEpisode,
          chapters.isGrouped ? {'2-1', '2-2'} : {'1', '2'},
        );
        expect(
          marked.viewedEpisode,
          chapters.isGrouped ? {'1-1', '2-3'} : {'3'},
        );
      },
    );
  }

  test('legacy viewed keys do not make grouped chapters viewed', () {
    final comic = comicFor(grouped);
    final history = History.fromModel(model: comic, ep: 0, page: 0)
      ..viewedEpisode = {'3'};
    final entries = chapterMarkMenu(
      position: grouped.positionAt(3),
      history: history,
      onSelected: (_) {},
    );
    expect(entries.map((e) => e.text), ['Mark as read']);
  });
}
