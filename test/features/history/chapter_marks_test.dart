import 'package:flutter_test/flutter_test.dart';
import 'package:venera_next/features/history/history_api.dart';
import 'package:venera_next/foundation/comic_type.dart';
import 'package:venera_next/foundation/history_contract.dart';

class _Comic with HistoryMixin {
  @override
  String get title => 'Title';

  @override
  String? get subTitle => 'Author';

  @override
  String get cover => 'cover';

  @override
  String get id => 'comic';

  @override
  HistoryType get historyType => ComicType(1);
}

void main() {
  test('constructors and copies keep viewed keys independent', () {
    final fromModel = History.fromModel(
      model: _Comic(),
      ep: 0,
      page: 0,
      readChapters: {'1'},
      viewedChapters: {'2'},
    );
    final copy = fromModel.copy();
    expect(copy.viewedEpisode, {'2'});
    expect(identical(copy.viewedEpisode, fromModel.viewedEpisode), isFalse);
    copy.viewedEpisode.add('3');
    expect(fromModel.viewedEpisode, {'2'});
    expect(
      History.fromModel(model: _Comic(), ep: 0, page: 0).viewedEpisode,
      isEmpty,
    );

    final fromLegacyMap = History.fromMap({
      'type': 1,
      'time': 1000,
      'title': 'Title',
      'subtitle': 'Author',
      'cover': 'cover',
      'ep': 0,
      'page': 0,
      'id': 'comic',
      'readEpisode': ['1'],
      'max_page': null,
    });
    expect(fromLegacyMap.viewedEpisode, isEmpty);
  });

  test('manual marks transition states and recognize legacy flat keys', () {
    final history = History.fromMap({
      'type': 1,
      'time': 1000,
      'title': 'Title',
      'subtitle': 'Author',
      'cover': 'cover',
      'ep': 3,
      'page': 7,
      'id': 'comic',
      'readEpisode': ['1-2', '4'],
      'viewedEpisode': ['1-3', '4'],
      'max_page': 10,
    });
    final originalTime = history.time;

    expect(isChapterRead(history, '1-2'), isTrue);
    expect(isChapterRead(history, '1-3', legacyRawKey: '3'), isFalse);
    history.readEpisode.add('3');
    expect(isChapterRead(history, '1-3', legacyRawKey: '3'), isTrue);

    markChaptersRead(history, ['1-3', '5']);
    expect(history.readEpisode, {'1-2', '4', '3', '1-3', '5'});
    expect(history.viewedEpisode, {'4'});

    markChapterUnread(history, '1-2', legacyRawKey: '2');
    markChapterUnread(history, '1-3', legacyRawKey: '3');
    markChapterUnread(history, '4');
    expect(history.readEpisode, {'5'});
    expect(history.viewedEpisode, isEmpty);
    expect(history.ep, 3);
    expect(history.page, 7);
    expect(history.time, originalTime);
  });
}
