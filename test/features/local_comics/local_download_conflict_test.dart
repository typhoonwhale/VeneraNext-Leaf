import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:venera_next/features/favorites/favorites_manager.dart';
import 'package:venera_next/features/local_comics/download_output_marker.dart';
import 'package:venera_next/features/local_comics/download_task.dart';
import 'package:venera_next/features/local_comics/import_export/comic_import_service.dart';
import 'package:venera_next/features/history/history_api.dart';
import 'package:venera_next/features/local_comics/local.dart';
import 'package:venera_next/features/local_comics/local_related_data.dart';
import 'package:venera_next/features/local_comics/local_repository.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:venera_next/foundation/sqlite_transaction.dart';
import 'package:venera_next/features/local_comics/local_storage_guard.dart';
import 'package:venera_next/foundation/app.dart';
import 'package:venera_next/foundation/comic_type.dart';

const _type = ComicType(9001);
const _token = '0123456789abcdef0123456789abcdef';

void main() {
  late Directory root;
  late LocalManager manager;

  LocalComic comic(String id, {List<String> chapters = const []}) => LocalComic(
    id: id,
    title: id,
    subtitle: '',
    tags: [],
    directory: id,
    chapters: null,
    cover: '0.jpg',
    comicType: _type,
    downloadedChapters: chapters,
    createdAt: DateTime(2024),
  );
  Future<LocalComic> addComic(String id) async {
    final directory = Directory('${manager.path}/$id')..createSync();
    File('${directory.path}/0.jpg').writeAsStringSync(id);
    final item = comic(id);
    await manager.add(item);
    return item;
  }

  Future<void> start({LocalComicRelatedData? relatedData}) async {
    LocalManager.current?.dispose();
    LocalManager(
      initializeSources: () async {},
      relatedData: relatedData,
      decodeDownloadTask: (json, storage) =>
          _Task(json['id'] as String)..path = json['path'] as String?,
    );
    manager = LocalManager();
    await manager.init();
  }

  setUp(() async {
    root = Directory.systemTemp.createTempSync('download-conflict-');
    App.dataPath = root.path;
    App.cachePath = root.path;
    await start();
  });
  tearDown(() async {
    await manager.pendingDeletionCleanup;
    await manager.pendingDownloadTaskWrites;
    LocalManager.current?.dispose();
    root.deleteSync(recursive: true);
  });

  group('deletion', () {
    test('an unrelated comic is deleted while another download runs', () async {
      final other = await addComic('other');
      final running = _Task('running')..path = '${manager.path}/running';
      Directory(running.path!).createSync();
      manager.addTask(running);
      expect(running.isPaused, isFalse);

      await manager.batchDeleteComics([other], true, false);
      expect(manager.find(other.id, other.comicType), isNull);
      expect(Directory('${manager.path}/other').existsSync(), isFalse);
      expect(running.isPaused, isFalse);
      expect(running.pauses, 0);
      expect(manager.downloadingTasks, [running]);
      expect(Directory(running.path!).existsSync(), isTrue);
    });

    for (final state in DownloadTaskState.values) {
      test('a ${state.name} download of a deleted comic is canceled', () async {
        final item = await addComic('book');
        final running = _Task('running');
        final task = _Task('book')..path = '${manager.path}/book';
        manager.restorePausedDownloads(
          [running, task],
          states: {if (state != DownloadTaskState.normal) task: state},
        );
        // A queued normal task waits behind the running one.
        manager.resumeDownload(running);
        expect(running.isPaused, isFalse);
        expect(task.isPaused, isTrue);

        await manager.deleteComic(item);
        expect(task.cancels, 1);
        expect(manager.downloadingTasks, [running]);
        expect(running.isPaused, isFalse);
        expect(manager.find(item.id, item.comicType), isNull);
        expect(Directory('${manager.path}/book').existsSync(), isFalse);
        await manager.pendingDownloadTaskWrites;
        final saved =
            jsonDecode(
                  File(
                    '${root.path}/downloading_tasks.json',
                  ).readAsStringSync(),
                )
                as List;
        expect(saved.map((entry) => entry['id']), ['running']);
      });
    }

    test('only the comic whose download writes is refused', () async {
      final busy = await addComic('busy');
      final other = await addComic('other');
      final task = _Task('busy')..path = '${manager.path}/busy';
      manager.addTask(task);
      expect(task.isPaused, isFalse);

      await expectLater(
        manager.deleteComic(busy),
        throwsA(
          isA<LocalComicTaskBusy>()
              .having((e) => e.title, 'title', 'busy')
              .having(
                (e) => e.message,
                'message',
                'Downloading. Pause or cancel it first.',
              ),
        ),
      );
      // A batch is refused as a whole before anything changes.
      await expectLater(
        manager.batchDeleteComics([other, busy], true, false),
        throwsA(isA<LocalComicTaskBusy>()),
      );
      expect(manager.find(other.id, other.comicType), isNotNull);
      expect(manager.find(busy.id, busy.comicType), isNotNull);
      expect(task.isPaused, isFalse);
      expect(task.cancels, 0);
      expect(File('${manager.path}/busy/0.jpg').existsSync(), isTrue);

      await manager.deleteComic(other);
      expect(manager.find(other.id, other.comicType), isNull);
    });

    test('an extracting archive is refused even after a pause', () async {
      final item = await addComic('archive');
      final task = _Task('archive')..extracting = true;
      manager.restorePausedDownloads([task]);
      await expectLater(
        manager.batchDeleteComics([item], true, false),
        throwsA(
          isA<LocalComicTaskBusy>().having(
            (e) => e.message,
            'message',
            'Extracting. Try again later.',
          ),
        ),
      );
      expect(manager.downloadingTasks, [task]);
      task.extracting = false;
      await manager.batchDeleteComics([item], true, false);
      expect(manager.downloadingTasks, isEmpty);
    });

    test('chapters stay deletable beside a paused download', () async {
      final directory = Directory('${manager.path}/series')..createSync();
      for (final chapter in ['1', '2']) {
        Directory('${directory.path}/$chapter').createSync();
        File('${directory.path}/$chapter/0.jpg').writeAsStringSync(chapter);
      }
      final item = comic('series', chapters: ['1', '2']);
      await manager.add(item);
      final task = _Task('series')..path = directory.path;
      manager.addTask(task);
      await expectLater(
        manager.deleteComicChapters(item, ['1']),
        throwsA(isA<LocalComicTaskBusy>()),
      );
      await manager.pauseDownload(task, byUser: true);
      await manager.deleteComicChapters(item, ['1']);
      expect(Directory('${directory.path}/1').existsSync(), isFalse);
      expect(Directory('${directory.path}/2').existsSync(), isTrue);
      expect(manager.downloadingTasks, [task]);
      expect(task.cancels, 0);
    });

    test('automatic starts wait while deletion decides', () async {
      final entered = Completer<void>();
      final commit = Completer<void>();
      await start(relatedData: _GatedRelatedData(entered, commit.future));
      final item = await addComic('book');
      final first = _Task('first');
      final next = _Task('next');
      manager.restorePausedDownloads([first, next]);
      manager.resumeDownload(first);
      final deleting = manager.batchDeleteComics([item], true, true);
      await entered.future;
      // The running task ends while the deletion is deciding: the queue does
      // not start the next one by itself until the deletion ends.
      await manager.cancelDownload(first);
      await pumpEventQueue();
      expect(next.isPaused, isTrue);
      commit.complete();
      await deleting;
      await pumpEventQueue();
      expect(manager.find(item.id, item.comicType), isNull);
      expect(next.isPaused, isFalse);
    });
  });

  test('imports skip folders a queued download writes', () async {
    final service = ComicImportService(
      localManager: () => manager,
      favoritesManager: LocalFavoritesManager.new,
    );
    final busy = Directory('${manager.path}/busy')..createSync();
    File('${busy.path}/1.jpg').writeAsStringSync('partial');
    final free = Directory('${manager.path}/free')..createSync();
    File('${free.path}/1.jpg').writeAsStringSync('page');
    final task = _Task('downloading')..path = busy.path;
    manager.restorePausedDownloads([task]);
    LocalComic import(String name, String directory) => LocalComic(
      id: '0',
      title: name,
      subtitle: '',
      tags: [],
      directory: directory,
      chapters: null,
      cover: '1.jpg',
      comicType: ComicType.local,
      downloadedChapters: [],
      createdAt: DateTime(2024),
    );
    expect(manager.overlapsDownloadOutput('busy'), isTrue);
    expect(manager.overlapsDownloadOutput('${busy.path}/chapter'), isTrue);
    expect(manager.overlapsDownloadOutput(free.path), isFalse);

    final result = await service.runImport(
      (operation) => operation.registerComics({
        null: [import('Busy', busy.path), import('Free', free.path)],
      }, copy: false),
    );
    expect(result.importedCount, 1);
    expect(
      result.issues.single.error,
      isA<LocalComicTaskBusy>().having((e) => e.title, 'title', 'Busy'),
    );
    expect(manager.findByName('Busy'), isNull);
    expect(manager.findByName('Free'), isNotNull);
    expect(File('${busy.path}/1.jpg').readAsStringSync(), 'partial');
  });

  test('restoring local downloads skips download outputs', () async {
    final service = ComicImportService(
      localManager: () => manager,
      favoritesManager: LocalFavoritesManager.new,
    );
    for (final name in ['queued', 'marked', 'legacy']) {
      final directory = Directory('${manager.path}/$name')..createSync();
      File('${directory.path}/1.jpg').writeAsStringSync(name);
    }
    File(
      '${manager.path}/marked/${DownloadOwnerToken.archiveMarker}',
    ).writeAsStringSync(_token);
    manager.restorePausedDownloads([
      _Task('queued')..path = '${manager.path}/queued',
    ]);
    final result = await service.runRecovery(
      (operation) => operation.localDownloads(isCancelled: () => false),
    );
    expect(result.pendingCopies.map((copy) => p.basename(copy.directory)), [
      'legacy',
    ]);
  });

  group('startup cleanup of orphan outputs', () {
    late String library;
    Directory output(String name, {String? marker, String token = _token}) {
      final directory = Directory('$library/$name')..createSync();
      File('${directory.path}/1.jpg').writeAsStringSync(name);
      if (marker != null) {
        File('${directory.path}/$marker').writeAsStringSync(token);
      }
      return directory;
    }

    setUp(() async {
      library = manager.path;
      await manager.add(comic('registered'));
      await manager.pendingDownloadTaskWrites;
      LocalManager.current?.dispose();
    });

    test('removes only unreferenced marked folders', () async {
      final orphanImages = output(
        'orphan-images',
        marker: DownloadOwnerToken.imagesMarker,
      );
      final orphanArchive = output(
        'orphan-archive',
        marker: DownloadOwnerToken.archiveMarker,
      );
      final restored = output(
        'restored',
        marker: DownloadOwnerToken.archiveMarker,
      );
      final registered = output(
        'registered',
        marker: DownloadOwnerToken.imagesMarker,
      );
      final sentinel = output('sentinel');
      final malformed = output(
        'malformed',
        marker: DownloadOwnerToken.imagesMarker,
        token: 'not a token',
      );
      final target = Directory('${root.path}/outside')..createSync();
      File(
        '${target.path}/${DownloadOwnerToken.imagesMarker}',
      ).writeAsStringSync(_token);
      final link = Link('$library/link')..createSync(target.path);
      File('${root.path}/downloading_tasks.json').writeAsStringSync(
        jsonEncode([
          {'id': 'restored', 'path': restored.path, 'state': 'paused'},
        ]),
      );

      await start();
      await manager.pendingDeletionCleanup;
      expect(orphanImages.existsSync(), isFalse);
      expect(orphanArchive.existsSync(), isFalse);
      for (final kept in [restored, registered, sentinel, malformed]) {
        expect(
          File('${kept.path}/1.jpg').readAsStringSync(),
          p.basename(kept.path),
        );
      }
      expect(link.existsSync(), isTrue);
      expect(
        File('${target.path}/${DownloadOwnerToken.imagesMarker}').existsSync(),
        isTrue,
      );
      expect(
        Directory(library).listSync().where(
          (entry) => p.basename(entry.path).startsWith('.venera-delete-'),
        ),
        isEmpty,
      );
    });

    test('a damaged snapshot removes nothing', () async {
      final orphan = output('orphan', marker: DownloadOwnerToken.imagesMarker);
      File('${root.path}/downloading_tasks.json').writeAsStringSync('{damaged');
      await start();
      await manager.pendingDeletionCleanup;
      expect(File('${orphan.path}/1.jpg').readAsStringSync(), 'orphan');
    });
  });
}

class _GatedRelatedData implements LocalComicRelatedData {
  _GatedRelatedData(this.entered, this.commit);
  final Completer<void> entered;
  final Future<void> commit;

  @override
  Future<void> saveMigratedHistory(History history) async {}

  @override
  Future<void> deleteRecords({
    required Database localDatabase,
    required List<LocalComic> comics,
    required void Function() markCommitted,
    required void Function() validate,
  }) async {
    entered.complete();
    await commit;
    runSqliteTransaction(localDatabase, () {
      validate();
      LocalRepository(localDatabase).removeAll(comics);
      markCommitted();
    });
  }
}

class _Task extends DownloadTask {
  _Task(this.id);
  @override
  final String id;
  bool paused = true;
  bool extracting = false;
  int pauses = 0;
  int cancels = 0;
  @override
  ComicType get comicType => _type;
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
  bool get isExtracting => extracting;
  @override
  int get speed => 0;
  @override
  double get progress => 0;
  @override
  Future<void> get pendingCleanup => Future.value();
  @override
  void pause() {
    if (!paused) pauses++;
    paused = true;
  }

  @override
  void resume() => paused = false;
  @override
  void cancel() {
    cancels++;
    paused = true;
  }

  @override
  Map<String, dynamic> toJson() => {'id': id, 'path': path};
  @override
  LocalComic toLocalComic() => throw UnsupportedError('conflict fixture');
}
