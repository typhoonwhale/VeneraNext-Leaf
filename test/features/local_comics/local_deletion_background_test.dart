import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';
import 'package:venera_next/features/local_comics/local.dart';
import 'package:venera_next/features/local_comics/local_storage_guard.dart';
import 'package:venera_next/foundation/app.dart';
import 'package:venera_next/foundation/comic_type.dart';

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
    cover: '0.jpg',
    comicType: const ComicType(9001),
    downloadedChapters: const [],
    createdAt: DateTime(2024),
  );
  Future<LocalComic> addComic(String id, {int pages = 1}) async {
    final directory = Directory('${manager.path}/$id')..createSync();
    for (var i = 0; i < pages; i++) {
      File('${directory.path}/$i.jpg').writeAsStringSync('$i');
    }
    final item = comic(id);
    await manager.add(item);
    return item;
  }

  List<String> quarantines(String library) => [
    for (final entry in Directory(library).listSync())
      if (p.basename(entry.path).startsWith('.venera-delete-')) entry.path,
  ];
  List<Row> journalRows() {
    final db = sqlite3.open('${root.path}/local.db');
    try {
      return db.select('SELECT * FROM local_deletion_journal').toList();
    } finally {
      db.dispose();
    }
  }

  Future<void> restart({
    Future<void> Function(String)? deleteQuarantine,
  }) async {
    await manager.pendingDownloadTaskWrites;
    LocalManager.current?.dispose();
    LocalManager(initializeSources: () async {});
    manager = LocalManager()..debugDeleteQuarantine = deleteQuarantine;
    await manager.init();
  }

  setUp(() async {
    root = Directory.systemTemp.createTempSync('deletion-background-');
    App.dataPath = root.path;
    App.cachePath = root.path;
    LocalManager.current?.dispose();
    LocalManager(initializeSources: () async {});
    manager = LocalManager();
    await manager.init();
  });
  tearDown(() async {
    await manager.pendingDeletionCleanup;
    await manager.pendingDownloadTaskWrites;
    LocalManager.current?.dispose();
    root.deleteSync(recursive: true);
  });

  test(
    'deletion returns and releases storage before files are removed',
    () async {
      final big = await addComic('big', pages: 3000);
      final other = await addComic('other');
      final removal = Completer<void>();
      final removing = <String>[];
      manager.debugDeleteQuarantine = (path) async {
        removing.add(path);
        await removal.future;
        await Directory(path).delete(recursive: true);
      };

      await manager.batchDeleteComics([big], true, false);
      expect(manager.find(big.id, big.comicType), isNull);
      expect(Directory('${manager.path}/big').existsSync(), isFalse);
      final staged = quarantines(manager.path).single;
      expect(Directory(staged).listSync(), hasLength(3000));
      expect(LocalComicStorageGuard.instance.pendingExclusive, isNull);
      await pumpEventQueue();
      expect(removing, [staged]);

      // Storage is free for the next deletion while the first is removed.
      await manager.deleteComic(other);
      expect(manager.count, 0);
      expect(journalRows(), hasLength(2));
      expect(journalRows().every((row) => row['committed'] == 1), isTrue);

      // Exit preparation does not wait for the removal either.
      final release = await LocalManager.prepareDownloadsForExit().timeout(
        const Duration(seconds: 5),
      );
      release();

      removal.complete();
      await manager.pendingDeletionCleanup;
      expect(quarantines(manager.path), isEmpty);
      expect(journalRows(), isEmpty);
    },
  );

  test('startup restores uncommitted rows before the library loads and '
      'removes committed ones in the background', () async {
    final library = manager.path;
    final restored = await addComic('restored');
    final restoredQuarantine = '$library/.venera-delete-1-1';
    final committed = Directory('$library/.venera-delete-2-2')..createSync();
    File('${committed.path}/0.jpg').writeAsStringSync('gone');
    await manager.pendingDownloadTaskWrites;
    LocalManager.current?.dispose();
    await Directory('$library/restored').rename(restoredQuarantine);
    final db = sqlite3.open('${root.path}/local.db');
    try {
      db.execute(
        'INSERT INTO local_deletion_journal(original_path,quarantine_path,committed) VALUES(?,?,0),(?,?,1)',
        [
          '$library/restored',
          restoredQuarantine,
          '$library/removed',
          committed.path,
        ],
      );
    } finally {
      db.dispose();
    }

    final removal = Completer<void>();
    LocalManager(initializeSources: () async {});
    manager = LocalManager()
      ..debugDeleteQuarantine = (path) async {
        await removal.future;
        await Directory(path).delete(recursive: true);
      };
    await manager.init().timeout(const Duration(seconds: 5));
    expect(File('$library/restored/0.jpg').readAsStringSync(), '0');
    expect(manager.find(restored.id, restored.comicType), isNotNull);
    expect(committed.existsSync(), isTrue);
    expect(journalRows().single['committed'], 1);

    removal.complete();
    await manager.pendingDeletionCleanup;
    expect(committed.existsSync(), isFalse);
    expect(journalRows(), isEmpty);
  });

  test('a failed background removal is retried on the next start', () async {
    final item = await addComic('retry', pages: 10);
    manager.debugDeleteQuarantine = (_) async =>
        throw const FileSystemException('device busy');
    await manager.deleteComic(item);
    await manager.pendingDeletionCleanup;
    final staged = quarantines(manager.path).single;
    expect(Directory(staged).existsSync(), isTrue);
    expect(journalRows(), hasLength(1));

    await restart();
    await manager.pendingDeletionCleanup;
    expect(Directory(staged).existsSync(), isFalse);
    expect(journalRows(), isEmpty);
  });

  test('a removal interrupted by disposal resumes on the next start', () async {
    final item = await addComic('interrupted', pages: 10);
    final removal = Completer<void>();
    manager.debugDeleteQuarantine = (path) async {
      await File('$path/0.jpg').delete();
      await removal.future;
    };
    await manager.deleteComic(item);
    await pumpEventQueue();
    final staged = quarantines(manager.path).single;
    await manager.pendingDownloadTaskWrites;
    final disposed = manager;
    LocalManager.current?.dispose();
    removal.complete();
    await disposed.pendingDeletionCleanup;
    expect(Directory(staged).existsSync(), isTrue);
    expect(journalRows(), hasLength(1));

    LocalManager(initializeSources: () async {});
    manager = LocalManager();
    await manager.init();
    await manager.pendingDeletionCleanup;
    expect(Directory(staged).existsSync(), isFalse);
    expect(journalRows(), isEmpty);
  });

  test('a migration waits for removed quarantines first', () async {
    final item = await addComic('moved', pages: 10);
    final removal = Completer<void>();
    manager.debugDeleteQuarantine = (path) async {
      await removal.future;
      await Directory(path).delete(recursive: true);
    };
    await manager.deleteComic(item);
    final destination = Directory('${root.path}/destination')..createSync();
    var moved = false;
    final migrating = manager
        .setNewPath(destination.path)
        .then((value) => moved = value == null);
    await pumpEventQueue();
    expect(moved, isFalse);
    expect(destination.listSync(), isEmpty);
    removal.complete();
    await migrating;
    expect(moved, isTrue);
    expect(quarantines(destination.path), isEmpty);
  });

  test('a malformed committed row never deletes outside quarantine and does '
      'not block startup', () async {
    final kept = await addComic('kept');
    final db = sqlite3.open('${root.path}/local.db');
    try {
      db.execute(
        'INSERT INTO local_deletion_journal(original_path,quarantine_path,committed) VALUES(?,?,1)',
        ['${manager.path}/other', '${manager.path}/kept'],
      );
    } finally {
      db.dispose();
    }
    await restart();
    await manager.pendingDeletionCleanup;
    expect(File('${manager.path}/kept/0.jpg').readAsStringSync(), '0');
    expect(manager.find(kept.id, kept.comicType), isNotNull);
    expect(journalRows(), hasLength(1));
  });
}
