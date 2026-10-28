import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:venera_next/features/local_comics/download_task.dart';
import 'package:venera_next/features/local_comics/local.dart';
import 'package:venera_next/features/local_comics/local_comics_page.dart';
import 'package:venera_next/foundation/app.dart';
import 'package:venera_next/foundation/app_data_operations.dart';
import 'package:venera_next/foundation/comic_type.dart';
import 'package:venera_next/foundation/context.dart';
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

  testWidgets('the delete dialog shows progress and cannot be resubmitted', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: appNavigation.rootNavigatorKey,
        home: const LocalComicsPage(),
      ),
    );
    await tester.pump();
    await tester.longPress(find.text('first').first);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.byTooltip('Delete'));
    await tester.pumpAndSettle();
    expect(find.text('Deleting...'), findsNothing);

    // Keep the deletion waiting for data access while the dialog is open.
    final gate = Completer<void>();
    unawaited(AppDataOperations.instance.run(() => gate.future));
    addTearDown(() {
      if (!gate.isCompleted) gate.complete();
    });
    await tester.tap(find.text('Confirm'));
    await tester.pump();
    expect(find.text('Deleting...'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'Confirm'))
          .onPressed,
      isNull,
    );
    // Neither back navigation nor the barrier closes the running dialog.
    await tester.binding.handlePopRoute();
    await tester.pump();
    expect(find.text('Deleting...'), findsOneWidget);

    gate.complete();
    // The deletion started in the widget zone; alternate real I/O and frames.
    Future<void> settle() async {
      for (
        var i = 0;
        i < 200 && find.text('Deleting...').evaluate().isNotEmpty;
        i++
      ) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        await tester.pump();
      }
      await tester.pumpAndSettle();
    }

    // This fixture has no favorites store: the failure stays in the dialog
    // and the action becomes available again.
    await settle();
    expect(find.text('Deleting...'), findsNothing);
    expect(find.textContaining('Favorites database is closed'), findsOneWidget);
    expect(manager.find('first', ComicType.local), isNotNull);
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'Confirm'))
          .onPressed,
      isNotNull,
    );

    await tester.tap(find.text('Remove local favorite and history'));
    await tester.pump();
    await tester.tap(find.text('Confirm'));
    await tester.pump();
    expect(find.text('Deleting...'), findsOneWidget);
    await settle();
    expect(find.text('Confirm'), findsNothing);
    expect(manager.find('first', ComicType.local), isNull);
    expect(find.text('first'), findsNothing);
    // The background removal was also scheduled from the widget zone.
    var removed = false;
    manager.pendingDeletionCleanup.then((_) => removed = true);
    for (var i = 0; i < 200 && !removed; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump(const Duration(milliseconds: 1));
    }
    expect(removed, isTrue);
    expect(Directory(manager.path).listSync().map((entry) => entry.path), [
      endsWith('second'),
    ]);
  });

  testWidgets('batch deletion skips a comic being downloaded and says so', (
    tester,
  ) async {
    final messages = <String>[];
    registerShowMessageHandler((_, message) => messages.add(message));
    addTearDown(() => registerShowMessageHandler((_, _) {}));
    final task = _RunningTask('first');
    // Real zone: its snapshot writes must not wait for the fake clock.
    await tester.runAsync(() async => manager.addTask(task));

    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: appNavigation.rootNavigatorKey,
        home: const LocalComicsPage(),
      ),
    );
    await tester.pump();
    await tester.longPress(find.text('first').first);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('second').first);
    await tester.pump();
    await tester.tap(find.byTooltip('Delete'));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(find.text('Remove local favorite and history'));
    await tester.pump();
    await tester.tap(find.text('Confirm'));
    await tester.pump();
    for (var i = 0; i < 200 && messages.isEmpty; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump();
    }
    await tester.pump(const Duration(milliseconds: 500));

    expect(manager.find('second', ComicType.local), isNull);
    expect(manager.find('first', ComicType.local), isNotNull);
    expect(manager.downloadingTasks, [task]);
    expect(messages, [
      'Deleted 1. Skipped 1 being downloaded or extracted: "first"',
    ]);
    // The skipped comic stays selected.
    expect(find.text('1 selected'), findsOneWidget);
    task.pause();
  });

  testWidgets('batch deletion of only busy comics deletes nothing', (
    tester,
  ) async {
    final tasks = [_RunningTask('first'), _RunningTask('second')];
    await tester.runAsync(() async => tasks.forEach(manager.addTask));
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: appNavigation.rootNavigatorKey,
        home: const LocalComicsPage(),
      ),
    );
    await tester.pump();
    await tester.longPress(find.text('first').first);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('second').first);
    await tester.pump();
    await tester.tap(find.byTooltip('Delete'));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(find.text('Confirm'));
    await tester.pump();
    for (var i = 0; i < 50; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump();
    }
    expect(
      find.textContaining('Downloading. Pause or cancel it first.'),
      findsWidgets,
    );
    expect(manager.find('first', ComicType.local), isNotNull);
    expect(manager.find('second', ComicType.local), isNotNull);
    for (final task in tasks) {
      task.pause();
    }
  });
}

class _RunningTask extends DownloadTask {
  _RunningTask(this.id);
  @override
  final String id;
  @override
  ComicType get comicType => ComicType.local;
  @override
  String get title => id;
  @override
  String? get cover => null;
  @override
  String get message => '';
  bool paused = false;
  @override
  bool get isPaused => paused;
  @override
  bool get isError => false;
  @override
  bool get isExtracting => false;
  @override
  int get speed => 0;
  @override
  double get progress => 0;
  @override
  Future<void> get pendingCleanup => Future.value();
  @override
  void pause() => paused = true;
  @override
  void resume() => paused = false;
  @override
  void cancel() => paused = true;
  @override
  Map<String, dynamic> toJson() => {'id': id};
  @override
  LocalComic toLocalComic() => throw UnsupportedError('page fixture');
}
