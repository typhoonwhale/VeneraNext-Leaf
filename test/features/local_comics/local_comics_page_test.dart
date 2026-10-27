import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:venera_next/features/local_comics/local.dart';
import 'package:venera_next/features/local_comics/local_comics_page.dart';
import 'package:venera_next/foundation/app.dart';
import 'package:venera_next/foundation/comic_type.dart';
import 'package:venera_next/routing/app_navigation.dart';

void main() {
  late Directory root;
  late LocalManager manager;
  LocalComic comic(String id) => LocalComic(
    id: id,
    title: id,
    subtitle: '',
    tags: [],
    directory: id,
    chapters: null,
    cover: 'cover.jpg',
    comicType: ComicType.local,
    downloadedChapters: const [],
    createdAt: DateTime(2024),
  );

  setUp(() async {
    root = Directory.systemTemp.createTempSync('local-page-');
    App.dataPath = root.path;
    App.cachePath = root.path;
    LocalManager.current?.dispose();
    LocalManager(initializeSources: () async {});
    manager = LocalManager();
    await manager.init();
    for (final id in ['first', 'second']) {
      Directory('${manager.path}/$id').createSync();
      await manager.add(comic(id));
    }
  });
  tearDown(() async {
    await manager.pendingDownloadTaskWrites;
    LocalManager.current?.dispose();
    root.deleteSync(recursive: true);
  });

  testWidgets('multi-select toolbar and checkboxes do not rely on color', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: appNavigation.rootNavigatorKey,
        home: const LocalComicsPage(),
      ),
    );
    await tester.pump();
    expect(find.byIcon(Icons.check_box_outline_blank), findsNothing);

    await tester.longPress(find.text('first').first);
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('1 selected'), findsOneWidget);
    expect(find.byIcon(Icons.close), findsOneWidget);
    expect(find.byIcon(Icons.check_box), findsOneWidget);
    expect(find.byIcon(Icons.check_box_outline_blank), findsOneWidget);
    expect(find.byIcon(Icons.flip), findsNothing);
    Border border(IconData icon) =>
        (tester
                        .widget<AnimatedContainer>(
                          find
                              .ancestor(
                                of: find.byIcon(icon),
                                matching: find.byType(AnimatedContainer),
                              )
                              .first,
                        )
                        .decoration!
                    as BoxDecoration)
                .border!
            as Border;
    expect(border(Icons.check_box).top.color, Colors.black);
    expect(border(Icons.check_box).top.width, 3);
    expect(border(Icons.check_box_outline_blank).top.color, Colors.transparent);

    // Visible labels under the icons, tooltips and 48dp targets.
    expect(find.text('Select all'), findsOneWidget);
    expect(find.text('Deselect all'), findsOneWidget);
    for (final tooltip in ['Select all', 'Deselect all', 'Delete', 'more']) {
      final target = find.byTooltip(tooltip);
      expect(target, findsOneWidget, reason: tooltip);
      final size = tester.getSize(target);
      expect(size.width, greaterThanOrEqualTo(48), reason: tooltip);
      expect(size.height, greaterThanOrEqualTo(48), reason: tooltip);
    }
    // Delete is a direct action, ordered before the overflow menu.
    expect(
      tester.getCenter(find.byTooltip('Delete')).dx,
      lessThan(tester.getCenter(find.byTooltip('more')).dx),
    );
    expect(
      tester.getCenter(find.byTooltip('Deselect all')).dx,
      lessThan(tester.getCenter(find.byTooltip('Delete')).dx),
    );
    final semantics = tester.ensureSemantics();
    for (final label in ['Select all', 'Deselect all']) {
      expect(
        tester.getSemantics(find.bySemanticsLabel(label)),
        isSemantics(label: label, isButton: true, hasTapAction: true),
      );
    }
    expect(
      tester.widget<Icon>(find.byIcon(Icons.check_box)).semanticLabel,
      'Selected',
    );
    expect(
      tester
          .widget<Icon>(find.byIcon(Icons.check_box_outline_blank))
          .semanticLabel,
      'Unselected',
    );
    semantics.dispose();

    await tester.tap(find.byTooltip('Select all'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('2 selected'), findsOneWidget);
    expect(find.byIcon(Icons.check_box), findsNWidgets(2));

    await tester.tap(find.byTooltip('Deselect all'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('0 selected'), findsOneWidget);
    expect(find.byIcon(Icons.check_box_outline_blank), findsNWidgets(2));
    expect(
      tester.widget<IconButton>(find.byType(IconButton).last).onPressed,
      isNull,
    );

    // The overflow menu keeps the other batch actions but not deletion.
    await tester.tap(find.text('second').first);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.byTooltip('more'));
    await tester.pumpAndSettle();
    expect(find.text('Add to favorites'), findsOneWidget);
    expect(find.text('Archive to WebDAV'), findsOneWidget);
    expect(find.text('Export as cbz'), findsOneWidget);
    expect(find.text('Delete'), findsNothing);
  });
}
