import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:venera_next/features/local_comics/download_task.dart';
import 'package:venera_next/features/local_comics/downloading_page.dart';
import 'package:venera_next/features/local_comics/local.dart';
import 'package:venera_next/foundation/app.dart';
import 'package:venera_next/foundation/comic_type.dart';

void main() {
  setUp(() => LocalManager.current?.dispose());
  tearDown(() => LocalManager.current?.dispose());

  Widget page({Brightness brightness = Brightness.light}) => MaterialApp(
    theme: ThemeData(brightness: brightness),
    home: const DownloadingPage(),
  );

  testWidgets(
    'theme changes do not duplicate subscriptions and unmount removes all',
    (tester) async {
      final task = _Task('a');
      LocalManager().restorePausedDownloads([task]);
      await tester.pumpWidget(page());
      expect(task.listenerCount, 2);
      await tester.pumpWidget(page(brightness: Brightness.dark));
      await tester.pumpAndSettle();
      await tester.pumpWidget(page());
      await tester.pumpAndSettle();
      expect(task.listenerCount, 2);
      await tester.pumpWidget(const SizedBox());
      expect(task.listenerCount, 0);
      task.emit();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'same-identity replacement retargets page and reused tile listeners',
    (tester) async {
      final manager = LocalManager();
      final original = _Task('same')..label = 'Original';
      manager.restorePausedDownloads([original]);
      await tester.pumpWidget(page());
      expect(original.listenerCount, 2);
      final replacement = _Task('same')..label = 'Replacement';
      expect(original, replacement);
      manager.restorePausedDownloads([replacement]);
      manager.resumeDownload(replacement);
      await tester.pump();
      expect(original.listenerCount, 0);
      expect(replacement.listenerCount, 2);
      replacement.label = 'Updated replacement';
      replacement.emit();
      await tester.pump();
      expect(find.text('Updated replacement'), findsOneWidget);
      expect(find.text('Original'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      expect(replacement.listenerCount, 0);
      original.emit();
      replacement.emit();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('task menu stays open while a running task keeps notifying', (
    tester,
  ) async {
    final root = Directory.systemTemp.createTempSync('downloading-page-');
    App.dataPath = root.path;
    addTearDown(() => root.deleteSync(recursive: true));
    final manager = LocalManager();
    final task = _Task('a')..label = 'Running';
    manager.restorePausedDownloads([task]);
    manager.resumeDownload(task);
    await tester.pumpWidget(page());
    await tester.tap(find.byIcon(Icons.more_horiz));
    await tester.pumpAndSettle();
    expect(find.text('Move To First'), findsOneWidget);
    for (var i = 1; i <= 7; i++) {
      task
        ..status = '$i/10'
        ..emit();
      await tester.pump(const Duration(seconds: 1));
    }
    await tester.pumpAndSettle();
    expect(find.text('Move To First'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(manager.downloadingTasks, isEmpty);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('per-second progress reaches the page at most every 3 seconds', (
    tester,
  ) async {
    final manager = LocalManager();
    final task = _Task('a')..label = 'Running';
    manager.restorePausedDownloads([task]);
    manager.resumeDownload(task);
    await tester.pumpWidget(page());
    double shownProgress() => tester
        .widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator))
        .value!;
    final shown = <String>[];
    void record() {
      for (var i = 1; i <= 9; i++) {
        if (find.text('$i/9').evaluate().isNotEmpty) {
          if (shown.isEmpty || shown.last != '$i/9') shown.add('$i/9');
        }
      }
    }

    for (var i = 1; i <= 9; i++) {
      task
        ..status = '$i/9'
        ..fraction = i / 9
        ..bytesPerSecond = i * 1024
        ..emit();
      await tester.pump();
      record();
      if (i == 1) {
        // The first update after a quiet period is shown at once.
        expect(find.text('1/9'), findsOneWidget);
        expect(find.text('1.00 KB/s'), findsOneWidget);
      }
      if (i == 2) {
        expect(find.text('1/9'), findsOneWidget);
        expect(shownProgress(), closeTo(1 / 9, 1e-9));
        expect(find.text('1.00 KB/s'), findsOneWidget);
      }
      await tester.pump(const Duration(seconds: 1));
      record();
    }
    // Updates at 0s, 1s ... 8s: shown at 0s, then the latest at 3s, 6s, 9s.
    expect(shown, ['1/9', '3/9', '6/9', '9/9']);
    expect(find.text('9/9'), findsOneWidget);
    expect(shownProgress(), closeTo(1, 1e-9));
    expect(find.text('9.00 KB/s'), findsOneWidget);

    // A state change is shown at once, inside the interval.
    task
      ..status = 'unseen progress'
      ..emit();
    await tester.pump();
    expect(find.text('unseen progress'), findsNothing);
    task.pause();
    await tester.pump();
    expect(find.widgetWithText(OutlinedButton, 'Start'), findsOneWidget);
    // A queue change is shown at once as well.
    manager.pauseDownload(task, byUser: true);
    await tester.pump();
    expect(find.text('Paused / Failed'), findsOneWidget);
    expect(find.widgetWithText(TextButton, 'Continue'), findsOneWidget);

    // A closed page leaves no listener or refresh behind.
    await tester.pumpWidget(const SizedBox());
    expect(task.listenerCount, 0);
    task.emit();
    await tester.pump(const Duration(seconds: 3));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'menus offer pause only for normal tasks and queued tasks say so',
    (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final manager = LocalManager();
      final running = _Task('a')..label = 'Running';
      final waiting = _Task('b')
        ..label = 'Waiting'
        ..fraction = 0.5;
      final userPaused = _Task('c')..label = 'User paused';
      final failed = _Task('d')..label = 'Failed';
      manager.restorePausedDownloads(
        [running, waiting, userPaused, failed],
        states: {
          userPaused: DownloadTaskState.paused,
          failed: DownloadTaskState.error,
        },
        errorMessages: {failed: 'Error: offline'},
      );
      manager.resumeDownload(running);
      await tester.pumpWidget(page());
      Finder tile(String title) =>
          find.ancestor(of: find.text(title), matching: find.byType(Row)).last;
      // The waiting task shows its state and the progress it already has.
      expect(
        find.descendant(of: tile('Waiting'), matching: find.text('Queued')),
        findsOneWidget,
      );
      expect(find.text('Queued'), findsOneWidget);
      expect(
        tester
            .widgetList<LinearProgressIndicator>(
              find.byType(LinearProgressIndicator),
            )
            .map((indicator) => indicator.value),
        [0, 0.5, 0, 0],
      );

      Future<List<String>> menu(String title) async {
        await tester.tap(
          find.descendant(
            of: tile(title),
            matching: find.byIcon(Icons.more_horiz),
          ),
        );
        await tester.pumpAndSettle();
        final texts = [
          for (final text in [
            'Error details',
            'Pause',
            'Cancel',
            'Move To First',
          ])
            if (find.text(text).evaluate().isNotEmpty) text,
        ];
        await tester.tapAt(Offset.zero);
        await tester.pumpAndSettle();
        return texts;
      }

      expect(await menu('Running'), ['Pause', 'Cancel', 'Move To First']);
      expect(await menu('Waiting'), ['Pause', 'Cancel', 'Move To First']);
      expect(await menu('User paused'), ['Cancel', 'Move To First']);
      expect(await menu('Failed'), [
        'Error details',
        'Cancel',
        'Move To First',
      ]);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('pausing one task parks it and keeps the queue moving', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final root = Directory.systemTemp.createTempSync('downloading-page-');
    App.dataPath = root.path;
    addTearDown(() => root.deleteSync(recursive: true));
    final manager = LocalManager();
    final first = _Task('a')..label = 'First';
    final second = _Task('b')..label = 'Second';
    final third = _Task('c')..label = 'Third';
    manager.restorePausedDownloads([first, second, third]);
    manager.resumeDownload(first);
    await tester.pumpWidget(page());
    double top(String text) => tester.getTopLeft(find.text(text)).dy;
    Future<void> pause(String title) async {
      await tester.tap(
        find.descendant(
          of: find
              .ancestor(of: find.text(title), matching: find.byType(Row))
              .last,
          matching: find.byIcon(Icons.more_horiz),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Pause'));
      await tester.pumpAndSettle();
    }

    // A queued task is parked without touching the running one.
    await pause('Third');
    expect(manager.downloadState(third), DownloadTaskState.paused);
    expect(third.resumes, 0);
    expect(first.paused, isFalse);
    expect(first.resumes, 1);
    expect(top('Paused / Failed'), lessThan(top('Third')));
    expect(top('Second'), lessThan(top('Paused / Failed')));
    expect(find.text('Queued'), findsOneWidget);

    // Pausing the running task starts the next normal task.
    await pause('First');
    expect(manager.downloadState(first), DownloadTaskState.paused);
    expect(first.paused, isTrue);
    expect(second.resumes, 1);
    expect(second.paused, isFalse);
    expect(identical(manager.activeDownloadTask, second), isTrue);
    expect(find.text('Queued'), findsNothing);
    expect(top('Second'), lessThan(top('Paused / Failed')));
    expect(top('Paused / Failed'), lessThan(top('First')));
    expect(find.widgetWithText(TextButton, 'Continue'), findsNWidgets(2));

    // The snapshot keeps these states; restart behavior is covered by
    // download_resume_intent_test.
    expect(manager.downloadState(second), DownloadTaskState.normal);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('page pause all withdraws a start pending old cleanup', (
    tester,
  ) async {
    // The page's pause all is a user pause and saves the state snapshot.
    final root = Directory.systemTemp.createTempSync('downloading-page-');
    App.dataPath = root.path;
    final manager = LocalManager();
    addTearDown(() => root.deleteSync(recursive: true));
    final gate = Completer<void>();
    final task = _Task('a')..cleanup = gate.future;
    manager.restorePausedDownloads([task]);
    await tester.pumpWidget(page());
    final stopped = manager.pauseDownload(task);
    await tester.pump();
    await tester.tap(find.widgetWithIcon(OutlinedButton, Icons.play_arrow));
    await tester.pump();
    expect(manager.isDownloadResumePending, isTrue);
    expect(task.resumes, 0);
    await tester.tap(find.widgetWithText(OutlinedButton, 'Pause all'));
    await tester.pump();
    expect(manager.isDownloadResumePending, isFalse);
    expect(manager.downloadState(task), DownloadTaskState.paused);
    gate.complete();
    await tester.pump();
    await stopped;
    await tester.pump();
    expect(task.resumes, 0);
    expect(find.widgetWithIcon(OutlinedButton, Icons.play_arrow), findsNothing);
    await tester.tap(find.widgetWithText(TextButton, 'Continue'));
    await tester.pump();
    expect(task.resumes, 1);
    await tester.pumpWidget(const SizedBox());
    expect(task.listenerCount, 0);
  });

  testWidgets('tasks are grouped and parked tasks can be continued', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final root = Directory.systemTemp.createTempSync('downloading-page-');
    App.dataPath = root.path;
    addTearDown(() => root.deleteSync(recursive: true));
    final manager = LocalManager();
    final running = _Task('a')..label = 'Running';
    final waiting = _Task('b')..label = 'Waiting';
    final userPaused = _Task('c')..label = 'User paused';
    final failed = _Task('d')..label = 'Failed';
    manager.restorePausedDownloads(
      [running, waiting, userPaused, failed],
      states: {
        userPaused: DownloadTaskState.paused,
        failed: DownloadTaskState.error,
      },
    );
    manager.resumeDownload(running);
    await tester.pumpWidget(page());
    final continueButton = find.widgetWithText(TextButton, 'Continue');
    double top(String text) => tester.getTopLeft(find.text(text)).dy;
    expect(top('Downloading / Queued'), lessThan(top('Running')));
    expect(top('Waiting'), lessThan(top('Paused / Failed')));
    expect(top('Paused / Failed'), lessThan(top('User paused')));
    expect(top('User paused'), lessThan(top('Failed')));
    expect(continueButton, findsNWidgets(2));
    expect(find.widgetWithText(OutlinedButton, 'Pause all'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, 'Start'), findsNothing);

    await tester.tap(
      find.descendant(
        of: find
            .ancestor(of: find.text('User paused'), matching: find.byType(Row))
            .last,
        matching: continueButton,
      ),
    );
    await tester.pump();
    // Queued behind the running task, not started.
    expect(top('Waiting'), lessThan(top('User paused')));
    expect(top('User paused'), lessThan(top('Paused / Failed')));
    expect(userPaused.resumes, 0);
    expect(continueButton, findsOneWidget);

    await tester.tap(find.widgetWithText(OutlinedButton, 'Pause all'));
    await tester.pump();
    expect(find.text('Downloading / Queued'), findsNothing);
    expect(continueButton, findsNWidgets(4));
    expect(running.paused, isTrue);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a restored failure shows its saved message and details', (
    tester,
  ) async {
    final manager = LocalManager();
    final saved = _Task('saved')..label = 'Saved';
    final legacy = _Task('legacy')..label = 'Legacy';
    manager.restorePausedDownloads(
      [saved, legacy],
      states: {saved: DownloadTaskState.error, legacy: DownloadTaskState.error},
      errorMessages: {saved: 'Error: source offline'},
    );
    await tester.pumpWidget(page());
    expect(find.text('Error: source offline'), findsOneWidget);
    // An older snapshot has no message: generic label, no details.
    expect(find.text('Error'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.more_horiz).last);
    await tester.pumpAndSettle();
    expect(find.text('Error details'), findsNothing);
    await tester.tapAt(Offset.zero);
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.more_horiz).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Error details'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<SelectableText>(find.byType(SelectableText)).data,
      'Error: source offline',
    );
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox());
  });

  for (final brightness in Brightness.values) {
    testWidgets(
      'full download error can be opened, scrolled and copied: $brightness',
      (tester) async {
        tester.view.physicalSize = const Size(375, 667);
        tester.view.devicePixelRatio = 1;
        tester.platformDispatcher.textScaleFactorTestValue = 2;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        final text = List.generate(
          40,
          (i) => 'Connection diagnostic line $i',
        ).join('\n');
        final task = _Task('error')
          ..error = true
          ..status = text;
        LocalManager().restorePausedDownloads(
          [task],
          states: {task: DownloadTaskState.error},
        );
        String? copied;
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          (call) async {
            if (call.method == 'Clipboard.setData') {
              copied = (call.arguments as Map)['text'] as String;
            }
            return null;
          },
        );
        addTearDown(
          () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
            SystemChannels.platform,
            null,
          ),
        );
        await tester.pumpWidget(page(brightness: brightness));
        expect(tester.takeException(), isNull, reason: 'download list layout');
        expect(find.text('Paused / Failed'), findsOneWidget);
        expect(find.widgetWithText(TextButton, 'Continue'), findsOneWidget);
        await tester.tap(find.byIcon(Icons.more_horiz));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: 'download menu layout');
        await tester.tap(find.text('Error details'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: 'error dialog layout');
        expect(find.text('Download error'), findsOneWidget);
        expect(
          tester.widget<SelectableText>(find.byType(SelectableText)).data,
          text,
        );
        await tester.tap(find.text('Copy'));
        await tester.pump();
        expect(copied, text);
        await tester.tap(find.text('Close'));
        await tester.pumpAndSettle();
        expect(find.byType(AlertDialog), findsNothing);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
}

class _Task extends DownloadTask {
  _Task(this.id);
  @override
  final String id;
  final _listeners = <VoidCallback>[];
  int get listenerCount => _listeners.length;
  String label = 'Task';
  bool paused = true;
  bool error = false;
  String status = 'Downloading';
  int resumes = 0;
  int bytesPerSecond = 0;
  double fraction = 0;
  Future<void>? cleanup;

  @override
  void addListener(VoidCallback listener) {
    _listeners.add(listener);
    super.addListener(listener);
  }

  @override
  void removeListener(VoidCallback listener) {
    _listeners.remove(listener);
    super.removeListener(listener);
  }

  void emit() => notifyListeners();
  @override
  ComicType get comicType => const ComicType(17);
  @override
  String get title => label;
  @override
  String? get cover => null;
  @override
  String get message => status;
  @override
  bool get isPaused => paused;
  @override
  bool get isError => error;
  @override
  int get speed => bytesPerSecond;
  @override
  double get progress => fraction;
  @override
  Future<void> get pendingCleanup => cleanup ?? Future.value();
  @override
  void pause() {
    paused = true;
    emit();
  }

  @override
  void resume() {
    paused = false;
    resumes++;
    emit();
  }

  @override
  void cancel() => pause();
  @override
  Map<String, dynamic> toJson() => {'id': id};
  @override
  LocalComic toLocalComic() => throw UnsupportedError('UI fixture');
}
