import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:venera_next/features/local_comics/download_task.dart';
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
        return restored[json['id'] as String] = _Task(json['id'] as String);
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
    'older or damaged snapshots restore every task as paused by the user',
    () async {
      writeSnapshot([
        {'type': 'fake', 'id': 'legacy'},
        {'type': 'fake', 'id': 'text', 'userPaused': 'false'},
        {'type': 'fake', 'id': 'number', 'userPaused': 0},
        {'type': 'fake', 'id': 'null', 'userPaused': null},
      ]);
      final manager = await start();
      expect(manager.downloadingTasks, hasLength(4));
      expect(restored.values.every((task) => task.isPaused), isTrue);
      expect(marker().existsSync(), isFalse);
      manager.resumeDownload(restored['legacy']!);
      expect(restored['legacy']!.isPaused, isFalse);
      await manager.pendingDownloadTaskWrites;
      expect(readSnapshot().map((entry) => entry['userPaused']), [
        false,
        true,
        true,
        true,
      ]);
    },
  );

  test(
    'restart resumes unpaused work and keeps a user pause across restarts',
    () async {
      writeSnapshot([
        {'type': 'fake', 'id': 'a', 'userPaused': false},
        {'type': 'fake', 'id': 'b', 'userPaused': false},
      ]);
      var manager = await start();
      expect(restored['a']!.isPaused, isFalse);
      expect(restored['b']!.isPaused, isTrue);
      expect(marker().existsSync(), isFalse);

      await manager.pauseDownload(restored['a']!, byUser: true);
      await stop(manager);
      manager = await start();
      expect(restored['a']!.isPaused, isTrue);
      expect(restored['b']!.isPaused, isTrue);

      manager.resumeDownload(restored['a']!);
      await stop(manager);
      manager = await start();
      expect(restored['a']!.isPaused, isFalse);
    },
  );

  test('system pause and exit preparation keep the intent', () async {
    writeSnapshot([
      {'type': 'fake', 'id': 'a', 'userPaused': false},
    ]);
    var manager = await start();
    final task = restored['a']!;
    // The Android download service stopping is a system pause.
    await manager.pauseDownload(task);
    expect(task.isPaused, isTrue);
    final release = await LocalManager.prepareDownloadsForExit();
    expect(task.isPaused, isTrue);
    expect(readSnapshot().single['userPaused'], isFalse);
    release();
    await stop(manager);
    manager = await start();
    expect(restored['a']!.isPaused, isFalse);
  });

  test(
    'an interrupted auto-resume leaves the next start paused once',
    () async {
      writeSnapshot([
        {'type': 'fake', 'id': 'a', 'userPaused': false},
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
      expect(marker().existsSync(), isFalse);
    },
  );

  test('automatic-start hold is a no-op without a live library', () {
    LocalManager.current?.dispose();
    final release = LocalManager.holdAutomaticDownloadStarts();
    release();
    release();
    expect(LocalManager.current, isNull);
  });
}

class _Task extends DownloadTask {
  _Task(this.id);
  @override
  final String id;
  bool paused = true;
  @override
  ComicType get comicType => const ComicType(17);
  @override
  String get title => id;
  @override
  String? get cover => null;
  @override
  String get message => '';
  @override
  bool get isPaused => paused;
  @override
  bool get isError => false;
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
  void cancel() => pause();
  @override
  Map<String, dynamic> toJson() => {'type': 'fake', 'id': id};
  @override
  LocalComic toLocalComic() => throw UnsupportedError('intent fixture');
}
