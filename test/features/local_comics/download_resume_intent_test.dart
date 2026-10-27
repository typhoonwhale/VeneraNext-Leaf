import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:venera_next/features/local_comics/download_task.dart';
import 'package:venera_next/features/local_comics/download_task_storage.dart';
import 'package:venera_next/features/local_comics/local.dart';
import 'package:venera_next/foundation/app.dart';
import 'package:venera_next/foundation/comic_type.dart';

void main() {
  late Directory root;
  late Map<String, _Task> restored;
  File snapshot() => File('${root.path}/downloading_tasks.json');
  File marker() => File('${root.path}/download_auto_resume.pending');

  void writeSnapshot(List<Map<String, dynamic>> entries) =>
      snapshot().writeAsStringSync(jsonEncode(entries));

  List<dynamic> readSnapshot() =>
      jsonDecode(snapshot().readAsStringSync()) as List;

  /// Simulates one application process: init, then background resume.
  Future<LocalManager> start() async {
    restored = {};
    LocalManager.current?.dispose();
    final manager = LocalManager(
      initializeSources: () async {},
      decodeDownloadTask: (json, storage) {
        if (json['type'] != 'fake') return null;
        return restored[json['id'] as String] = _Task(
          json['id'] as String,
          storage,
        );
      },
    );
    await manager.init();
    await manager.pendingDownloadAutoResume;
    return manager;
  }

  Future<void> stop(LocalManager manager) async {
    await manager.pendingDownloadTaskWrites;
    manager.dispose();
  }

  setUp(() {
    LocalManager.current?.dispose();
    root = Directory.systemTemp.createTempSync('download-resume-intent-');
    App.dataPath = root.path;
    App.cachePath = root.path;
  });

  tearDown(() async {
    final manager = LocalManager.current;
    if (manager != null) await stop(manager);
    root.deleteSync(recursive: true);
  });

  test(
    'state round-trips and older or damaged snapshots never resume a task',
    () async {
      writeSnapshot([
        {'type': 'fake', 'id': 'legacy'},
        {'type': 'fake', 'id': 'legacyRun', 'userPaused': false},
        {'type': 'fake', 'id': 'legacyPaused', 'userPaused': true},
        {'type': 'fake', 'id': 'text', 'userPaused': 'false'},
        {'type': 'fake', 'id': 'null', 'userPaused': null},
        {'type': 'fake', 'id': 'bogus', 'state': 'running'},
        {'type': 'fake', 'id': 'number', 'state': 0},
        {'type': 'fake', 'id': 'failed', 'state': 'error'},
        {'type': 'fake', 'id': 'normal', 'state': 'normal', 'userPaused': true},
      ]);
      final manager = await start();
      List<String> states() => [
        for (final task in manager.downloadingTasks)
          manager.downloadState(task).name,
      ];
      expect(states(), [
        'paused',
        'normal',
        'paused',
        'paused',
        'paused',
        'paused',
        'paused',
        'error',
        'normal',
      ]);
      expect(
        [
          for (final task in restored.values)
            if (!task.isPaused) task.id,
        ],
        ['legacyRun'],
      );
      manager.resumeDownload(restored['legacy']!);
      // Behind the running task: resumed to normal but waiting.
      expect(restored['legacy']!.isPaused, isTrue);
      await manager.pendingDownloadTaskWrites;
      final saved = readSnapshot().cast<Map<String, dynamic>>();
      expect(saved.map((entry) => entry['id']).last, 'legacy');
      expect(saved.map((entry) => entry['state']), [...states()]);
      expect(states().last, 'normal');
      // An older snapshot keeps the error state without a message.
      expect(manager.downloadErrorMessage(restored['failed']!), isNull);
      expect(saved.every((entry) => !entry.containsKey('userPaused')), isTrue);
    },
  );

  test('a failure stays parked across restarts until resumed', () async {
    writeSnapshot([
      {'type': 'fake', 'id': 'a', 'state': 'normal'},
      {'type': 'fake', 'id': 'b', 'state': 'normal'},
    ]);
    var manager = await start();
    expect(restored['a']!.isPaused, isFalse);
    final reason = 'Error: ${'x' * 5000}';
    restored['a']!.fail(reason);
    await pumpEventQueue();
    expect(restored['b']!.isPaused, isFalse);
    await manager.pendingDownloadAutoResumeMarkerRemoval;
    expect(marker().existsSync(), isFalse);
    await stop(manager);
    expect(readSnapshot().map((entry) => entry['state']), ['error', 'normal']);
    final saved = readSnapshot().first['error'] as String;
    expect(saved, hasLength(4000));
    expect(reason, startsWith(saved));
    expect(readSnapshot().last.containsKey('error'), isFalse);

    manager = await start();
    expect(restored['a']!.isPaused, isTrue);
    expect(restored['b']!.isPaused, isFalse);
    expect(manager.downloadState(restored['a']!), DownloadTaskState.error);
    expect(manager.downloadErrorMessage(restored['a']!), saved);
    restored['b']!.advance();
    manager.removeTask(restored['b']!);
    await manager.pendingDownloadAutoResumeMarkerRemoval;
    await stop(manager);

    // Nothing else to run: a failed task still waits for the user.
    manager = await start();
    expect(restored['a']!.isPaused, isTrue);
    expect(marker().existsSync(), isFalse);
    manager.resumeDownload(restored['a']!);
    expect(restored['a']!.isPaused, isFalse);
    expect(manager.downloadState(restored['a']!), DownloadTaskState.normal);
    expect(manager.downloadErrorMessage(restored['a']!), isNull);
  });

  test(
    'restart resumes unpaused work and keeps a user pause across restarts',
    () async {
      writeSnapshot([
        {'type': 'fake', 'id': 'a', 'state': 'normal'},
        {'type': 'fake', 'id': 'b', 'state': 'normal'},
      ]);
      var manager = await start();
      expect(restored['a']!.isPaused, isFalse);
      expect(restored['b']!.isPaused, isTrue);
      // Kept until the resumed task proves stable; a user pause settles it.
      expect(marker().existsSync(), isTrue);

      // A user pause parks the task and advances to the next normal one.
      await manager.pauseDownload(restored['a']!, byUser: true);
      await pumpEventQueue();
      expect(restored['b']!.isPaused, isFalse);
      await manager.pendingDownloadAutoResumeMarkerRemoval;
      expect(marker().existsSync(), isFalse);
      await stop(manager);
      manager = await start();
      expect(restored['a']!.isPaused, isTrue);
      expect(restored['b']!.isPaused, isFalse);
      restored['b']!.advance();
      await manager.pendingDownloadAutoResumeMarkerRemoval;

      // Resumed behind the running task: it waits there, also after restart.
      manager.resumeDownload(restored['a']!);
      expect(restored['a']!.isPaused, isTrue);
      await stop(manager);
      manager = await start();
      expect(manager.downloadingTasks, [restored['b'], restored['a']]);
      expect(restored['b']!.isPaused, isFalse);
      expect(restored['a']!.isPaused, isTrue);
      expect(manager.downloadState(restored['a']!), DownloadTaskState.normal);
    },
  );

  test('system pause and exit preparation keep the intent', () async {
    writeSnapshot([
      {'type': 'fake', 'id': 'a', 'state': 'normal'},
    ]);
    var manager = await start();
    final task = restored['a']!;
    // The Android download service stopping is a system pause.
    await manager.pauseDownload(task);
    expect(task.isPaused, isTrue);
    final release = await LocalManager.prepareDownloadsForExit();
    expect(task.isPaused, isTrue);
    expect(readSnapshot().single['state'], 'normal');
    expect(marker().existsSync(), isFalse);
    release();
    await stop(manager);
    manager = await start();
    expect(restored['a']!.isPaused, isFalse);
    // Exit preparation stops the resumed task and removes the marker.
    expect(marker().existsSync(), isTrue);
    final exit = await LocalManager.prepareDownloadsForExit();
    expect(marker().existsSync(), isFalse);
    exit();
  });

  test(
    'an interrupted auto-resume leaves the next start paused once',
    () async {
      writeSnapshot([
        {'type': 'fake', 'id': 'a', 'state': 'normal'},
      ]);
      marker().writeAsStringSync('');
      var manager = await start();
      expect(restored['a']!.isPaused, isTrue);
      expect(marker().existsSync(), isFalse);
      manager.resumeDownload(restored['a']!);
      expect(restored['a']!.isPaused, isFalse);

      await stop(manager);
      manager = await start();
      expect(restored['a']!.isPaused, isFalse);
      restored['a']!.advance();
      await manager.pendingDownloadAutoResumeMarkerRemoval;
      expect(marker().existsSync(), isFalse);
    },
  );

  test(
    'a crash after the start but before the first progress skips one resume',
    () async {
      writeSnapshot([
        {'type': 'fake', 'id': 'a', 'state': 'normal'},
        {'type': 'fake', 'id': 'b', 'state': 'normal'},
      ]);
      var manager = await start();
      final task = restored['a']!;
      expect(task.isPaused, isFalse);
      // The asynchronous work (extraction, decoding) is still running.
      await pumpEventQueue();
      expect(marker().existsSync(), isTrue);
      // Notifications without progress do not settle the task.
      task.notifyListeners();
      manager.notifyListeners();
      await manager.pendingDownloadAutoResumeMarkerRemoval;
      expect(marker().existsSync(), isTrue);

      // Process dies without exit preparation.
      await stop(manager);
      expect(marker().existsSync(), isTrue);
      manager = await start();
      expect(restored['a']!.isPaused, isTrue);
      expect(restored['b']!.isPaused, isTrue);
      expect(marker().existsSync(), isFalse);
      expect(readSnapshot().map((entry) => entry['state']), [
        'normal',
        'normal',
      ]);

      // Only once: the following start resumes again and progress settles it.
      await stop(manager);
      manager = await start();
      expect(restored['a']!.isPaused, isFalse);
      expect(marker().existsSync(), isTrue);
      restored['a']!.advance();
      await manager.pendingDownloadAutoResumeMarkerRemoval;
      expect(marker().existsSync(), isFalse);
      await stop(manager);
      manager = await start();
      expect(restored['a']!.isPaused, isFalse);
    },
  );

  test('completing or failing the resumed task removes the marker', () async {
    writeSnapshot([
      {'type': 'fake', 'id': 'a', 'state': 'normal'},
    ]);
    var manager = await start();
    expect(marker().existsSync(), isTrue);
    manager.removeTask(restored['a']!);
    await manager.pendingDownloadAutoResumeMarkerRemoval;
    expect(marker().existsSync(), isFalse);
    await stop(manager);

    writeSnapshot([
      {'type': 'fake', 'id': 'a', 'state': 'normal'},
    ]);
    manager = await start();
    expect(marker().existsSync(), isTrue);
    restored['a']!.fail();
    await manager.pendingDownloadAutoResumeMarkerRemoval;
    expect(marker().existsSync(), isFalse);
  });

  test('automatic-start hold is a no-op without a live library', () {
    LocalManager.current?.dispose();
    final release = LocalManager.holdAutomaticDownloadStarts();
    release();
    release();
    expect(LocalManager.current, isNull);
  });
}

class _Task extends DownloadTask {
  _Task(this.id, this.storage);
  final DownloadTaskStorage storage;
  @override
  final String id;
  bool paused = true;
  bool error = false;
  double _progress = 0;

  void advance() {
    _progress += 0.1;
    notifyListeners();
  }

  String status = '';

  void fail([String reason = 'Error: failed']) {
    status = reason;
    paused = true;
    error = true;
    notifyListeners();
    storage.failTask(this);
  }

  @override
  ComicType get comicType => const ComicType(17);
  @override
  String get title => id;
  @override
  String? get cover => null;
  @override
  String get message => status;
  @override
  bool get isPaused => paused;
  @override
  bool get isError => error;
  @override
  int get speed => 0;
  @override
  double get progress => _progress;
  @override
  Future<void> get pendingCleanup => Future.value();
  @override
  void pause() => paused = true;
  @override
  void resume() => paused = false;
  @override
  void cancel() => pause();
  @override
  Map<String, dynamic> toJson() => {'type': 'fake', 'id': id};
  @override
  LocalComic toLocalComic() => throw UnsupportedError('intent fixture');
}
