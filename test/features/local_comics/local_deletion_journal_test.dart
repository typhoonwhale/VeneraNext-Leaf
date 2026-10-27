import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:venera_next/features/local_comics/local_deletion_journal.dart';
import 'package:venera_next/foundation/sqlite_transaction.dart';

void main() {
  late Directory root;
  late Database db;
  late LocalDeletionJournal journal;
  Future<bool> exists(String path) async =>
      await FileSystemEntity.type(path, followLinks: false) !=
      FileSystemEntityType.notFound;
  Directory content(String name) {
    final directory = Directory('${root.path}/$name')..createSync();
    File('${directory.path}/page').writeAsStringSync(name);
    return directory;
  }

  void reopen() {
    db.dispose();
    db = sqlite3.open('${root.path}/journal.db');
    journal = LocalDeletionJournal(db, exists: exists)..initialize();
  }

  setUp(() {
    root = Directory.systemTemp.createTempSync('deletion-journal-');
    db = sqlite3.open('${root.path}/journal.db');
    journal = LocalDeletionJournal(db, exists: exists)..initialize();
    db.execute(
      'CREATE TABLE records(id INTEGER PRIMARY KEY); INSERT INTO records VALUES(1);',
    );
  });
  tearDown(() {
    db.dispose();
    root.deleteSync(recursive: true);
  });

  test('database failure restores staged directories and records', () async {
    final directory = content('book');
    await expectLater(
      journal.run([directory], (mark) async {
        expect(directory.existsSync(), isFalse);
        runSqliteTransaction(db, () {
          db.execute('DELETE FROM records');
          mark();
          throw StateError('database failure');
        });
      }),
      throwsStateError,
    );
    expect(File('${directory.path}/page').readAsStringSync(), 'book');
    expect(db.select('SELECT * FROM records'), hasLength(1));
    expect(db.select('SELECT * FROM local_deletion_journal'), isEmpty);
  });

  test(
    'committed cleanup never removes a new directory at the original path',
    () async {
      final directory = content('book');
      await journal.run([directory, Directory('${directory.path}/nested')], (
        mark,
      ) async {
        runSqliteTransaction(db, () {
          db.execute('DELETE FROM records');
          mark();
        });
        directory.createSync();
        File('${directory.path}/new').writeAsStringSync('new owner');
      });
      await journal.purgeCommitted();
      expect(File('${directory.path}/new').readAsStringSync(), 'new owner');
      expect(File('${directory.path}/page').existsSync(), isFalse);
      expect(db.select('SELECT * FROM local_deletion_journal'), isEmpty);
    },
  );

  test(
    'publication failure after commit never restores deleted records or files',
    () async {
      final directory = content('book');
      await expectLater(
        journal.run([directory], (mark) async {
          runSqliteTransaction(db, () {
            db.execute('DELETE FROM records');
            mark();
          });
          throw StateError('publication failure');
        }),
        throwsStateError,
      );
      expect(directory.existsSync(), isFalse);
      expect(db.select('SELECT * FROM records'), isEmpty);
      expect(db.select('SELECT * FROM local_deletion_journal'), hasLength(1));
      await journal.purgeCommitted();
      expect(_quarantines(root), isEmpty);
      expect(db.select('SELECT * FROM local_deletion_journal'), isEmpty);
    },
  );

  test(
    'cleanup interruption survives reopening and retries only quarantine',
    () async {
      final directory = content('book');
      await journal.run([directory], (mark) async {
        runSqliteTransaction(db, () {
          db.execute('DELETE FROM records');
          mark();
        });
      });
      final interrupted = LocalDeletionJournal(
        db,
        exists: exists,
        deleteDirectory: (_) async =>
            throw const FileSystemException('cleanup unavailable'),
      );
      await expectLater(
        interrupted.purgeCommitted(),
        throwsA(isA<FileSystemException>()),
      );
      expect(db.select('SELECT * FROM local_deletion_journal'), hasLength(1));
      directory.createSync();
      File('${directory.path}/new').writeAsStringSync('keep');
      reopen();
      await journal.recover();
      expect(File('${directory.path}/new').readAsStringSync(), 'keep');
      expect(_quarantines(root), isEmpty);
      expect(db.select('SELECT * FROM local_deletion_journal'), isEmpty);
    },
  );

  test('run returns before the committed directory is removed', () async {
    final directory = content('book');
    for (var i = 0; i < 2000; i++) {
      File('${directory.path}/$i.jpg').writeAsStringSync('$i');
    }
    final removal = Completer<void>();
    final removing = <String>[];
    final gated = LocalDeletionJournal(
      db,
      exists: exists,
      deleteDirectory: (path) async {
        removing.add(path);
        await removal.future;
        await Directory(path).delete(recursive: true);
      },
    );
    await gated.run([directory], (mark) async {
      runSqliteTransaction(db, () {
        db.execute('DELETE FROM records');
        mark();
      });
    });
    expect(directory.existsSync(), isFalse);
    final staged = _quarantines(root).single;
    expect(Directory(staged).listSync(), hasLength(2001));
    expect(
      db
          .select('SELECT committed FROM local_deletion_journal')
          .single['committed'],
      1,
    );
    expect(removing, isEmpty);

    final purge = gated.purgeCommitted();
    await pumpEventQueue();
    expect(removing, [staged]);
    // A second purge never removes the same quarantine concurrently.
    await gated.purgeCommitted();
    expect(removing, [staged]);
    expect(db.select('SELECT * FROM local_deletion_journal'), hasLength(1));
    removal.complete();
    await purge;
    expect(Directory(staged).existsSync(), isFalse);
    expect(db.select('SELECT * FROM local_deletion_journal'), isEmpty);
  });

  test('startup recovery restores only uncommitted rows', () async {
    final restored = content('restored');
    final restoredQuarantine = '${root.path}/.venera-delete-1-1';
    await restored.rename(restoredQuarantine);
    final removed = content('.venera-delete-2-2');
    db.execute(
      'INSERT INTO local_deletion_journal(original_path,quarantine_path,committed) VALUES(?,?,0),(?,?,1)',
      [restored.path, restoredQuarantine, '${root.path}/removed', removed.path],
    );
    await journal.recoverUncommitted();
    expect(File('${restored.path}/page').readAsStringSync(), 'restored');
    expect(removed.existsSync(), isTrue);
    expect(
      db
          .select('SELECT committed FROM local_deletion_journal')
          .single['committed'],
      1,
    );
    await journal.purgeCommitted();
    expect(removed.existsSync(), isFalse);
    expect(db.select('SELECT * FROM local_deletion_journal'), isEmpty);
  });

  test('a stopped purge keeps the row of an interrupted removal', () async {
    final removed = content('.venera-delete-3-3');
    db.execute(
      'INSERT INTO local_deletion_journal(original_path,quarantine_path,committed) VALUES(?,?,1)',
      ['${root.path}/removed', removed.path],
    );
    var stopped = false;
    final interrupted = LocalDeletionJournal(
      db,
      exists: exists,
      deleteDirectory: (path) async {
        // Exit arrives while the bytes are being removed.
        stopped = true;
        await File('$path/page').delete();
      },
    );
    await interrupted.purgeCommitted(isStopped: () => stopped);
    expect(db.select('SELECT * FROM local_deletion_journal'), hasLength(1));
    reopen();
    await journal.recover();
    expect(removed.existsSync(), isFalse);
    expect(db.select('SELECT * FROM local_deletion_journal'), isEmpty);
  });

  test('uncommitted movement is restored after reopening', () async {
    final directory = content('book');
    final quarantine = '${root.path}/.venera-delete-interrupted';
    db.execute(
      'INSERT INTO local_deletion_journal(original_path,quarantine_path) VALUES(?,?)',
      [directory.path, quarantine],
    );
    await directory.rename(quarantine);
    reopen();
    await journal.recover();
    expect(File('${directory.path}/page').readAsStringSync(), 'book');
    expect(db.select('SELECT * FROM records'), hasLength(1));
    expect(db.select('SELECT * FROM local_deletion_journal'), isEmpty);
  });

  test(
    'uncommitted collision preserves both directories and durable evidence',
    () async {
      final directory = content('book');
      final quarantine = content('.venera-delete-interrupted');
      db.execute(
        'INSERT INTO local_deletion_journal(original_path,quarantine_path) VALUES(?,?)',
        [directory.path, quarantine.path],
      );
      await expectLater(journal.recover(), throwsA(isA<FileSystemException>()));
      expect(File('${directory.path}/page').readAsStringSync(), 'book');
      expect(
        File('${quarantine.path}/page').readAsStringSync(),
        '.venera-delete-interrupted',
      );
      expect(db.select('SELECT * FROM local_deletion_journal'), hasLength(1));
    },
  );

  test(
    'malformed cleanup paths never delete the original or unrelated root',
    () async {
      final directory = content('book');
      db.execute(
        'INSERT INTO local_deletion_journal(original_path,quarantine_path,committed) VALUES(?,?,1)',
        [directory.path, root.path],
      );
      await expectLater(journal.recover(), throwsStateError);
      expect(File('${directory.path}/page').readAsStringSync(), 'book');
      expect(db.select('SELECT * FROM local_deletion_journal'), hasLength(1));
      await expectLater(journal.purgeCommitted(), throwsStateError);
      expect(File('${directory.path}/page').readAsStringSync(), 'book');
      expect(root.existsSync(), isTrue);
    },
  );

  test('malformed rows do not block other committed removals', () async {
    final directory = content('book');
    final removed = content('.venera-delete-4-4');
    db.execute(
      'INSERT INTO local_deletion_journal(original_path,quarantine_path,committed) VALUES(?,?,1),(?,?,1)',
      [
        directory.path,
        '${root.path}/book-copy',
        '${root.path}/x',
        removed.path,
      ],
    );
    await expectLater(journal.purgeCommitted(), throwsStateError);
    expect(File('${directory.path}/page').readAsStringSync(), 'book');
    expect(removed.existsSync(), isFalse);
    expect(db.select('SELECT * FROM local_deletion_journal'), hasLength(1));
  });

  group('background cleaner', () {
    test(
      'runs one pass at a time and repeats a request made during it',
      () async {
        final gates = <Completer<void>>[];
        var running = 0;
        var maxRunning = 0;
        final cleaner = LocalDeletionCleaner((_) async {
          running++;
          maxRunning = running > maxRunning ? running : maxRunning;
          final gate = Completer<void>();
          gates.add(gate);
          await gate.future;
          running--;
        }, onError: (error, stack) => fail('$error'));
        cleaner.schedule();
        // The caller's turn never runs a pass.
        expect(gates, isEmpty);
        await pumpEventQueue();
        expect(gates, hasLength(1));
        cleaner
          ..schedule()
          ..schedule();
        gates.single.complete();
        await pumpEventQueue();
        expect(gates, hasLength(2));
        gates.last.complete();
        await cleaner.idle;
        expect(gates, hasLength(2));
        expect(maxRunning, 1);
      },
    );

    test('reports failures, retries on request and stops', () async {
      final errors = <Object>[];
      var passes = 0;
      late bool Function() stoppedInPass;
      final cleaner = LocalDeletionCleaner((isStopped) async {
        passes++;
        stoppedInPass = isStopped;
        throw StateError('busy');
      }, onError: (error, stack) => errors.add(error));
      cleaner.schedule();
      await cleaner.idle;
      cleaner.schedule();
      await cleaner.idle;
      expect(passes, 2);
      expect(errors, hasLength(2));
      cleaner.stop();
      expect(stoppedInPass(), isTrue);
      cleaner.schedule();
      await cleaner.idle;
      expect(passes, 2);
    });
  });
}

List<String> _quarantines(Directory root) => [
  for (final entry in root.listSync())
    if (entry is Directory &&
        entry.path
            .split(Platform.pathSeparator)
            .last
            .startsWith('.venera-delete-'))
      entry.path,
];
