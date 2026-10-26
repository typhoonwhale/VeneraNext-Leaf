import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:venera_next/features/comic_source/comic_source.dart';
import 'package:venera_next/features/local_comics/download_task_codec.dart';
import 'package:venera_next/features/local_comics/local_comics.dart';
import 'package:venera_next/foundation/app.dart';
import 'package:venera_next/foundation/comic_type.dart';
import 'package:venera_next/network/file_downloader.dart';

const _sourceKey = 'archive_recovery_test_source';
const _archive = [80, 75, 3, 4, 1, 2, 3];

void main() {
  late Directory root;
  late Directory cache;
  // Each simulated process gets fresh hooks, as after a real restart.
  late List<String> transfers;
  late Stream<DownloadingStatus> Function(String path) transfer;
  late List<String> extractions;
  Completer<void>? extractGate;
  Completer<void>? extracting;
  // Stopping a real downloader closes its stream; hanging fakes do the same.
  late Map<String, void Function()> closers;

  final comicType = ComicType(_sourceKey.hashCode);
  File snapshot() => File('${root.path}/data/downloading_tasks.json');
  List<dynamic> readSnapshot() =>
      jsonDecode(snapshot().readAsStringSync()) as List;
  void writeSnapshot(List<dynamic> entries) =>
      snapshot().writeAsStringSync(jsonEncode(entries));

  Stream<DownloadingStatus> completeTransfer(String path) async* {
    File(path).writeAsBytesSync(_archive);
    yield DownloadingStatus(_archive.length, _archive.length, 0, true);
  }

  /// Leaves a range sidecar and never finishes, like an interrupted transfer.
  Stream<DownloadingStatus> hangingTransfer(String path) {
    File(path).writeAsBytesSync(List.filled(_archive.length, 0));
    File('$path.download').writeAsStringSync('0-${_archive.length}-3');
    final controller = StreamController<DownloadingStatus>();
    closers[path] = controller.close;
    controller.add(DownloadingStatus(3, _archive.length, 0));
    return controller.stream;
  }

  FileDownloader createDownloader(String url, String path) {
    transfers.add(path);
    return _Downloader(
      url,
      path,
      transfer(path),
      () => closers.remove(path)?.call(),
    );
  }

  Future<void> extract(String archive, String output) async {
    extractions.add(output);
    expect(File(archive).readAsBytesSync(), _archive);
    File('$output/1.jpg').writeAsBytesSync([1]);
    final gate = extractGate;
    if (gate != null) {
      extracting?.complete();
      await gate.future;
    }
    File('$output/2.jpg').writeAsBytesSync([2]);
  }

  ArchiveDownloadTask newTask(LocalManager manager, String id) =>
      ArchiveDownloadTask(
        'https://example.invalid/$id.zip',
        _comic(id),
        storage: manager,
        createDownloader: createDownloader,
        extractArchive: extract,
      );

  /// One application process: init, restore, then background resume.
  Future<LocalManager> start({
    Stream<DownloadingStatus> Function(String path)? using,
  }) async {
    transfers = [];
    extractions = [];
    closers = {};
    transfer = using ?? completeTransfer;
    extractGate = null;
    extracting = null;
    LocalManager.current?.dispose();
    final manager = LocalManager(
      initializeSources: () async {},
      decodeDownloadTask: (json, storage) => json['type'] == 'fake'
          ? null
          : ArchiveDownloadTask.fromJson(
              storage,
              json,
              createDownloader: createDownloader,
              extractArchive: extract,
            ),
    );
    await manager.init();
    await manager.pendingDownloadAutoResume;
    return manager;
  }

  /// The process ends without any shutdown work: the last written snapshot
  /// and files are all the next process sees.
  Future<List<dynamic>> crash(LocalManager manager) async {
    await manager.pendingDownloadTaskWrites;
    final saved = readSnapshot();
    manager.dispose();
    return saved;
  }

  ArchiveDownloadTask restored(LocalManager manager, [String id = 'a']) =>
      manager.downloadingTasks.firstWhere((task) => task.id == id)
          as ArchiveDownloadTask;

  Future<void> finish(ArchiveDownloadTask task) async {
    await waitFor(() => task.isPaused);
    await task.pendingRun;
  }

  Map<String, dynamic> entry(List<dynamic> saved, [String id = 'a']) => saved
      .cast<Map<String, dynamic>>()
      .firstWhere((entry) => (entry['comic'] as Map)['comicId'] == id);

  List<String> workspaces() =>
      cache
          .listSync()
          .map((entry) => entry.path.split('/').last)
          .where((name) => name.startsWith('archive-download-'))
          .toList()
        ..sort();

  void expectCompletedOnce(LocalManager manager, String id, String output) {
    expect(manager.find(id, comicType), isNotNull);
    expect(manager.count, 1);
    expect(manager.downloadingTasks.where((task) => task.id == id), isEmpty);
    expect(
      Directory(output).listSync().map((e) => e.path.split('/').last).toSet(),
      {'1.jpg', '2.jpg'},
    );
  }

  setUp(() {
    LocalManager.current?.dispose();
    ComicSourceManager().remove(_sourceKey);
    ComicSourceManager().add(_testSource(_sourceKey));
    root = Directory.systemTemp.createTempSync('archive-recovery-');
    Directory('${root.path}/data').createSync();
    cache = Directory('${root.path}/cache')..createSync();
    App.dataPath = '${root.path}/data';
    App.cachePath = cache.path;
  });

  tearDown(() async {
    final manager = LocalManager.current;
    if (manager != null) {
      await manager.pendingDownloadTaskWrites;
      manager.dispose();
    }
    ComicSourceManager().remove(_sourceKey);
    root.deleteSync(recursive: true);
  });

  test('codec recognizes archive snapshots and skips malformed ones', () async {
    final manager = await start();
    final task = newTask(manager, 'a');
    expect(downloadTaskFromJson(task.toJson(), storage: manager), isNotNull);
    for (final broken in <Map<String, dynamic>>[
      {...task.toJson()}..remove('archiveUrl'),
      {...task.toJson(), 'comic': 'not a comic'},
      {
        ...task.toJson(),
        'comic': {...task.toJson()['comic'] as Map, 'sourceKey': 'missing'},
      },
      {...task.toJson(), 'path': 7},
    ]) {
      expect(downloadTaskFromJson(broken, storage: manager), isNull);
    }
  });

  test(
    'downloading and queued tasks survive a restart and resume by intent',
    () async {
      var manager = await start();
      transfer = hangingTransfer;
      manager.addTask(newTask(manager, 'a'));
      manager.addTask(newTask(manager, 'b'));
      await waitFor(() => transfers.isNotEmpty);
      final archive = transfers.single;
      final saved = await crash(manager);
      expect(entry(saved)['workspace'], File(archive).parent.path);
      expect(entry(saved)['phase'], 'downloading');
      expect(entry(saved, 'b')['workspace'], isNull);

      final sidecars = <bool>[];
      manager = await start(
        using: (path) {
          sidecars.add(File('$path.download').existsSync());
          return completeTransfer(path);
        },
      );
      expect(manager.downloadingTasks.map((task) => task.id), ['a', 'b']);
      final head = restored(manager);
      final queued = restored(manager, 'b');
      expect(queued.isPaused, isTrue);
      // The restored head continues in its own workspace, sidecar intact.
      await finish(head);
      expect(transfers.first, archive);
      expect(sidecars.first, isTrue);
      expect(manager.find('a', comicType), isNotNull);
      expect(File(archive).parent.existsSync(), isFalse);
      // Completing the head advances the queue to the restored queued task.
      await waitFor(() => transfers.length == 2);
      await finish(queued);
      expect(manager.count, 2);
      expect(manager.downloadingTasks, isEmpty);
      expect(workspaces(), isEmpty);
      for (final id in ['a', 'b']) {
        final comic = manager.find(id, comicType)!;
        expect(
          File('${comic.baseDir}/.venera-archive-download').existsSync(),
          isFalse,
        );
      }
    },
  );

  test('a user pause survives restarts with its workspace', () async {
    var manager = await start();
    transfer = hangingTransfer;
    final task = newTask(manager, 'a');
    manager.addTask(task);
    await waitFor(() => transfers.isNotEmpty);
    final archive = transfers.single;
    await manager.pauseDownload(task, byUser: true);
    await crash(manager);

    manager = await start();
    final paused = restored(manager);
    expect(paused.isPaused, isTrue);
    expect(transfers, isEmpty);
    expect(File('$archive.download').existsSync(), isTrue);
    manager.resumeDownload(paused);
    await finish(paused);
    expect(transfers, [archive]);
    expectCompletedOnce(manager, 'a', paused.path!);
  });

  test(
    'interrupted extraction is not complete and re-extracts cleanly once',
    () async {
      var manager = await start();
      extractGate = Completer<void>();
      extracting = Completer<void>();
      manager.addTask(newTask(manager, 'a'));
      await extracting!.future;
      final output = manager.downloadingTasks.single.path!;
      // Another comic in the library must never be touched.
      final other = Directory('${manager.path}/other')..createSync();
      final sentinel = File('${other.path}/keep.jpg')..writeAsBytesSync([9]);
      final saved = await crash(manager);
      expect(entry(saved)['phase'], 'extracting');
      expect(entry(saved)['outputOwned'], isTrue);
      // Leave the half output and pretend the user paused before the crash.
      writeSnapshot([
        {...entry(saved), 'userPaused': true},
      ]);

      manager = await start();
      final task = restored(manager);
      expect(task.isPaused, isTrue);
      expect(manager.find('a', comicType), isNull);
      File('$output/stale.jpg').writeAsBytesSync([0]);
      manager.resumeDownload(task);
      await finish(task);
      // The downloaded archive is reused; half pages from before are gone.
      expect(transfers, isEmpty);
      expect(extractions, [output]);
      expectCompletedOnce(manager, 'a', output);
      expect(sentinel.readAsBytesSync(), [9]);
      expect(workspaces(), isEmpty);
    },
  );

  test(
    'a commit that outlived its snapshot is not registered or extracted again',
    () async {
      var manager = await start();
      extractGate = Completer<void>();
      extracting = Completer<void>();
      final task = newTask(manager, 'a');
      manager.addTask(task);
      await extracting!.future;
      await manager.pendingDownloadTaskWrites;
      final stale = readSnapshot();
      extractGate!.complete();
      await finish(task);
      expect(manager.count, 1);
      await crash(manager);
      // The process ended after the database commit, before the rewrite.
      writeSnapshot(stale);

      manager = await start();
      expect(manager.downloadingTasks, isEmpty);
      expect(extractions, isEmpty);
      expect(manager.count, 1);
    },
  );

  test(
    'unverifiable output ownership is kept and reported, not deleted',
    () async {
      var manager = await start();
      extractGate = Completer<void>();
      extracting = Completer<void>();
      manager.addTask(newTask(manager, 'a'));
      await extracting!.future;
      final output = manager.downloadingTasks.single.path!;
      await crash(manager);
      File('$output/.venera-archive-download').writeAsStringSync('someone');

      manager = await start();
      final task = restored(manager);
      await finish(task);
      expect(task.isError, isTrue);
      expect(extractions, isEmpty);
      expect(File('$output/1.jpg').existsSync(), isTrue);
      expect(manager.find('a', comicType), isNull);
      await manager.cancelDownload(task);
      await task.pendingCleanup;
      expect(File('$output/1.jpg').existsSync(), isTrue);
    },
  );

  test('cancel removes a restored workspace and its own output', () async {
    var manager = await start();
    transfer = hangingTransfer;
    manager.addTask(newTask(manager, 'a'));
    await waitFor(() => transfers.isNotEmpty);
    final workspace = File(transfers.single).parent;
    final output = manager.downloadingTasks.single.path!;
    await crash(manager);
    writeSnapshot([
      {...entry(readSnapshot()), 'userPaused': true},
    ]);

    manager = await start();
    final task = restored(manager);
    await manager.cancelDownload(task);
    await task.pendingCleanup;
    expect(workspace.existsSync(), isFalse);
    expect(Directory(output).existsSync(), isFalse);
    expect(manager.downloadingTasks, isEmpty);
  });

  group('untrusted workspace is replaced by a fresh download', () {
    final cases = <String, String Function(String workspace)>{
      'removed by the system': (workspace) {
        Directory(workspace).deleteSync(recursive: true);
        return workspace;
      },
      'replaced by a symbolic link': (workspace) {
        final outside = Directory('${root.path}/outside')..createSync();
        File('${outside.path}/keep').writeAsStringSync('keep');
        Directory(workspace).deleteSync(recursive: true);
        Link(workspace).createSync(outside.path);
        return workspace;
      },
      'outside the cache': (workspace) {
        final moved = '${root.path}/archive-download-moved';
        Directory(workspace).renameSync(moved);
        return moved;
      },
      'without the task prefix': (workspace) {
        final moved = '${cache.path}/cbz_import_moved';
        Directory(workspace).renameSync(moved);
        return moved;
      },
      'escaping through ..': (workspace) {
        final moved = '${root.path}/archive-download-escaped';
        Directory(workspace).renameSync(moved);
        return '${cache.path}/../archive-download-escaped';
      },
      'marked by another task': (workspace) {
        File('$workspace/.owner').writeAsStringSync('0' * 32);
        return workspace;
      },
    };
    for (final MapEntry(key: name, value: tamper) in cases.entries) {
      test(name, () async {
        var manager = await start();
        extractGate = Completer<void>();
        extracting = Completer<void>();
        manager.addTask(newTask(manager, 'a'));
        await extracting!.future;
        final saved = entry(await crash(manager));
        final original = saved['workspace'] as String;
        final untrusted = tamper(original);
        final untrustedFiles = _listing(untrusted);
        writeSnapshot([
          {...saved, 'workspace': untrusted},
        ]);

        manager = await start();
        final task = restored(manager);
        await finish(task);
        // Downloaded again into a new workspace under the cache root.
        expect(transfers, hasLength(1));
        final fresh = File(transfers.single).parent.path;
        expect(fresh, isNot(original));
        expect(File(fresh).parent.path, cache.path);
        expectCompletedOnce(manager, 'a', task.path!);
        // Prefix-matched direct children of the cache that no task verifies
        // are orphans by definition; everything else is left as found.
        if (name != 'marked by another task') {
          expect(_listing(untrusted), untrustedFiles);
        }
        if (name.contains('link')) {
          expect(File('${root.path}/outside/keep').readAsStringSync(), 'keep');
        }
      });
    }
  });

  test('a damaged downloaded archive is downloaded again', () async {
    var manager = await start();
    extractGate = Completer<void>();
    extracting = Completer<void>();
    manager.addTask(newTask(manager, 'a'));
    await extracting!.future;
    final archive = transfers.single;
    await crash(manager);
    File(archive).writeAsBytesSync([1, 2]);

    manager = await start();
    final task = restored(manager);
    await finish(task);
    expect(transfers, [archive]);
    expectCompletedOnce(manager, 'a', task.path!);
  });

  test('startup removes only unreferenced task workspaces', () async {
    var manager = await start();
    transfer = hangingTransfer;
    manager.addTask(newTask(manager, 'a'));
    await waitFor(() => transfers.isNotEmpty);
    final live = File(transfers.single).parent;
    final saved = await crash(manager);
    writeSnapshot([
      {...entry(saved), 'userPaused': true},
    ]);
    final orphan = Directory('${cache.path}/archive-download-orphan')
      ..createSync();
    File('${orphan.path}/download.zip').writeAsBytesSync([1]);
    final outside = Directory('${root.path}/outside')..createSync();
    final linkTarget = File('${outside.path}/keep')..writeAsStringSync('keep');
    final link = Link('${cache.path}/archive-download-link')
      ..createSync(outside.path);
    final file = File('${cache.path}/archive-download-file')
      ..writeAsStringSync('keep');
    final other = Directory('${cache.path}/cbz_import_other')..createSync();
    final nested = Directory('${cache.path}/cache/archive-download-nested')
      ..createSync(recursive: true);

    manager = await start();
    expect(orphan.existsSync(), isFalse);
    expect(live.existsSync(), isTrue);
    expect(link.existsSync(), isTrue);
    expect(linkTarget.readAsStringSync(), 'keep');
    expect(file.existsSync(), isTrue);
    expect(other.existsSync(), isTrue);
    expect(nested.existsSync(), isTrue);
    await crash(manager);

    // An unreadable snapshot is not evidence that workspaces are orphaned.
    snapshot().writeAsStringSync('{broken');
    await start();
    expect(live.existsSync(), isTrue);
  });

  test('older archive snapshots restore paused without ownership', () async {
    var manager = await start();
    final library = manager.path;
    manager.dispose();
    final partial = Directory('$library/legacy')..createSync();
    final kept = File('${partial.path}/keep.jpg')..writeAsBytesSync([7]);
    writeSnapshot([
      {
        'type': 'ArchiveDownloadTask',
        'archiveUrl': 'https://example.invalid/a.zip',
        'comic': _comic('a').toJson(),
        'path': partial.path,
      },
      {'type': 'ArchiveDownloadTask', 'comic': _comic('b').toJson()},
      {
        'type': 'ArchiveDownloadTask',
        'archiveUrl': 'https://example.invalid/c.zip',
        'comic': _comic('c').toJson(),
        'path': null,
      },
    ]);

    manager = await start();
    expect(manager.downloadingTasks.map((task) => task.id), ['a', 'c']);
    final task = restored(manager);
    expect(task.isPaused, isTrue);
    expect(transfers, isEmpty);
    // Without ownership evidence a canceled legacy task keeps the folder.
    await manager.cancelDownload(task);
    await task.pendingCleanup;
    expect(kept.readAsBytesSync(), [7]);

    final next = restored(manager, 'c');
    manager.resumeDownload(next);
    await finish(next);
    expect(manager.find('c', comicType), isNotNull);
    expect(workspaces(), isEmpty);
  });
}

Future<void> waitFor(bool Function() ready) async {
  final deadline = DateTime.now().add(const Duration(seconds: 5));
  while (!ready()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('Download did not reach the expected state');
    }
    await Future<void>.delayed(const Duration(milliseconds: 2));
  }
}

List<String> _listing(String path) {
  final type = FileSystemEntity.typeSync(path, followLinks: false);
  if (type == FileSystemEntityType.notFound) return const [];
  if (type == FileSystemEntityType.link) return ['link'];
  return Directory(path).listSync().map((e) => e.path.split('/').last).toList()
    ..sort();
}

class _Downloader extends FileDownloader {
  _Downloader(super.url, super.savePath, this.statuses, this.onStop);
  final Stream<DownloadingStatus> statuses;
  final void Function() onStop;
  @override
  Stream<DownloadingStatus> start() => statuses;

  @override
  Future<void> stop() async {
    onStop();
    await super.stop();
  }
}

ComicDetails _comic(String id) => ComicDetails.fromJson({
  'title': 'Archive $id',
  'subtitle': '',
  'cover': 'cover.jpg',
  'description': '',
  'tags': <String, List<String>>{},
  'chapters': null,
  'sourceKey': _sourceKey,
  'comicId': id,
});

ComicSource _testSource(String key) {
  return ComicSource(
    'Test Source',
    key,
    null,
    null,
    null,
    null,
    const [],
    null,
    null,
    null,
    null,
    null,
    null,
    null,
    '',
    '',
    '1.0.0',
    null,
    null,
    null,
    null,
    null,
    null,
    null,
    null,
    null,
    null,
    null,
    null,
    false,
    false,
    null,
    null,
  );
}
