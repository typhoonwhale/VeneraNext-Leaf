import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:venera_next/components/menu.dart';
import 'package:venera_next/features/comic_details/actions.dart';
import 'package:venera_next/features/comic_details/chapter_menu.dart';
import 'package:venera_next/features/comic_source/comic_source_api.dart';
import 'package:venera_next/features/history/history_api.dart';
import 'package:venera_next/features/reader/reader.dart';
import 'package:venera_next/foundation/app_page_route.dart';
import 'package:venera_next/foundation/context.dart';
import 'package:venera_next/routing/app_navigation.dart';

class _Actions with ComicPageActions {
  _Actions(this.context) {
    history = History.fromModel(model: comic, ep: 2, page: 7);
  }
  @override
  final BuildContext context;
  @override
  final contextMenus = MenuRouteController();
  @override
  final comic = ComicDetails.fromJson({
    'title': 'Book',
    'cover': '',
    'tags': {},
    'sourceKey': 'test',
    'comicId': 'book',
    'chapters': {'a': 'First', 'b': 'Second'},
  });
  @override
  History? history;
  @override
  bool isComicActive(ComicDetails value) =>
      context.mounted && identical(value, comic);
  @override
  void update() {}
  @override
  void onReadEnd() {}
}

class _Routes extends NavigatorObserver {
  final readers = <AppPageRoute<dynamic>>[];
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (route is AppPageRoute) readers.add(route);
  }
}

void main() {
  Future<_Actions> mount(WidgetTester tester, _Routes routes) async {
    late BuildContext owner;
    await tester.pumpWidget(
      ReaderSessionScope(
        onClosed: () {},
        child: MaterialApp(
          navigatorKey: appNavigation.rootNavigatorKey,
          navigatorObservers: [routes],
          home: Builder(
            builder: (context) {
              owner = context;
              return const Scaffold();
            },
          ),
        ),
      ),
    );
    return _Actions(owner);
  }

  for (final entry in ['chapter', 'continue', 'thumbnail']) {
    testWidgets(
      'delayed chapter mark blocks $entry until new history is published',
      (tester) async {
        final routes = _Routes();
        final actions = await mount(tester, routes);
        final original = actions.history!;
        final write = Completer<void>();
        final marked = prepareChapterMark(
          comic: actions.comic,
          latest: original,
          position: actions.comic.chapters!.positionAt(1),
          action: ChapterMarkAction.read,
        );
        final saving = actions.saveChapterMark(() async {
          await write.future;
          actions.history = marked;
        });
        void enter() {
          switch (entry) {
            case 'chapter':
              actions.read(1);
            case 'continue':
              actions.continueRead();
            case 'thumbnail':
              actions.read(null, 4);
          }
        }

        expect(actions.isSavingChapterMark, isTrue);
        enter();
        expect(routes.readers, isEmpty);
        expect(actions.history, same(original));
        expect(original.readEpisode, isEmpty);
        write.complete();
        await saving;
        expect(actions.isSavingChapterMark, isFalse);
        enter();
        expect(routes.readers, hasLength(1));
        final route = routes.readers.single;
        final reader = route.builder(appNavigation.rootContext) as Reader;
        expect(reader.history, same(marked));
        expect(reader.history.readEpisode, {'1'});
        if (entry == 'continue') {
          expect(reader.initialChapter, 2);
          expect(reader.initialPage, 7);
        }
        // Inspect the real Reader entry contract without mounting reader services.
        appNavigation.rootNavigatorKey.currentState!.removeRoute(route);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final dispose in [false, true]) {
    testWidgets(
      'failed delayed save preserves history and releases gate; dispose=$dispose',
      (tester) async {
        final routes = _Routes();
        final actions = await mount(tester, routes);
        final original = actions.history;
        final messages = <String>[];
        registerShowMessageHandler((owner, message) {
          expect(owner.mounted, isTrue);
          messages.add(message);
        });
        addTearDown(() => registerShowMessageHandler((_, _) {}));
        final write = Completer<void>();
        final saving = actions.saveChapterMark(() => write.future);
        actions.read(1);
        actions.continueRead();
        expect(routes.readers, isEmpty);
        if (dispose) await tester.pumpWidget(const SizedBox());
        write.completeError(StateError('write failed'));
        await saving;
        expect(actions.history, same(original));
        expect(actions.history!.readEpisode, isEmpty);
        expect(actions.isSavingChapterMark, isFalse);
        expect(messages, dispose ? isEmpty : hasLength(1));
        if (dispose) {
          actions.read(1);
          actions.continueRead();
          expect(routes.readers, isEmpty);
        }
        expect(tester.takeException(), isNull);
      },
    );
  }
}
