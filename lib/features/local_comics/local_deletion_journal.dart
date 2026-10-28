import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';
import 'package:venera_next/foundation/sqlite_transaction.dart';

/// Durable ownership of directories moved out of the live library before a
/// database deletion. Only committed quarantine paths may be removed on retry.
///
/// [run] returns once the directories are moved and the deletion committed;
/// [purgeCommitted] removes committed quarantines later, outside storage
/// ownership. Callers serialize [run] and [recoverUncommitted].
class LocalDeletionJournal {
  LocalDeletionJournal(
    this.db, {
    required this.exists,
    Future<void> Function(String path)? deleteDirectory,
  }) : deleteDirectory = deleteDirectory ?? _deleteDirectory;

  final Database db;
  final Future<bool> Function(String path) exists;

  /// Removes a committed quarantine directory recursively.
  final Future<void> Function(String path) deleteDirectory;

  static Future<void> _deleteDirectory(String path) =>
      Directory(path).delete(recursive: true);

  /// Quarantines being removed by any journal of this isolate. A second purge
  /// skips them instead of deleting the same directory concurrently.
  static final _purging = <String>{};

  void initialize() =>
      db.execute('''CREATE TABLE IF NOT EXISTS local_deletion_journal (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    original_path TEXT NOT NULL,
    quarantine_path TEXT NOT NULL,
    committed INTEGER NOT NULL DEFAULT 0
  );''');

  /// Restore uncommitted movements, then remove committed quarantines.
  Future<void> recover() async {
    await recoverUncommitted();
    await purgeCommitted();
  }

  /// Restore directories whose deletion never committed. This must finish
  /// before the library is read, so it runs synchronously at startup.
  Future<void> recoverUncommitted() async {
    for (final row in db.select(
      'SELECT * FROM local_deletion_journal WHERE committed = 0 ORDER BY id DESC',
    )) {
      await _recoverRow(row);
    }
  }

  /// Remove committed quarantines and their journal rows. Rows that fail stay
  /// for a later attempt; the first failure is rethrown after the others ran.
  /// [isStopped] ends the pass between directories, before any database
  /// write. [write] performs each row removal, for an owner's access rules.
  /// While [deferWrites] holds, directories are still removed but their rows
  /// are kept; a later pass removes a row whose quarantine is gone.
  Future<void> purgeCommitted({
    bool Function()? isStopped,
    FutureOr<void> Function(void Function() remove)? write,
    bool Function()? deferWrites,
  }) async {
    bool stopped() => isStopped?.call() ?? false;
    (Object, StackTrace)? failure;
    for (final row in db.select(
      'SELECT * FROM local_deletion_journal WHERE committed = 1 ORDER BY id',
    )) {
      if (stopped()) return;
      final id = row['id'] as int;
      final original = row['original_path'] as String;
      final quarantine = row['quarantine_path'] as String;
      try {
        _checkPaths(original, quarantine);
        final key = p.normalize(p.absolute(quarantine));
        if (!_purging.add(key)) continue;
        try {
          if (await exists(quarantine)) await deleteDirectory(quarantine);
        } finally {
          _purging.remove(key);
        }
        if (stopped()) return;
        if (deferWrites?.call() ?? false) continue;
        void remove() => db.execute(
          'DELETE FROM local_deletion_journal WHERE id = ? AND committed = 1',
          [id],
        );
        if (write == null) {
          remove();
        } else {
          await write(remove);
        }
      } catch (error, stack) {
        failure ??= (error, stack);
      }
    }
    if (failure case (final error, final stack)) {
      Error.throwWithStackTrace(error, stack);
    }
  }

  /// A journal is local state, but never allow malformed entries to designate
  /// a parent, the original path or a different directory for recursive I/O.
  static void _checkPaths(String original, String quarantine) {
    if (!p.equals(p.dirname(original), p.dirname(quarantine)) ||
        p.equals(original, quarantine) ||
        !p.basename(quarantine).startsWith('.venera-delete-')) {
      throw StateError('Invalid local deletion journal path');
    }
  }

  Future<void> _recoverRow(Row row) async {
    final id = row['id'] as int;
    final original = row['original_path'] as String;
    final quarantine = row['quarantine_path'] as String;
    _checkPaths(original, quarantine);
    final staged = await exists(quarantine);
    if (staged) {
      if (await exists(original)) {
        throw FileSystemException(
          'Cannot restore deletion: original path is occupied',
          original,
        );
      }
      await Directory(quarantine).rename(original);
    } else if (!await exists(original)) {
      throw FileSystemException(
        'Cannot restore deletion: both paths are missing',
        original,
      );
    }
    db.execute('DELETE FROM local_deletion_journal WHERE id = ?', [id]);
  }

  /// The callback must mark this journal in the same SQLite transaction that
  /// removes records. Publication errors after commit must not restore files.
  /// Returns without removing the committed quarantines; see [purgeCommitted].
  Future<void> run(
    List<Directory> directories,
    Future<void> Function(void Function() markCommitted) commit,
  ) async {
    await recoverUncommitted();
    final ids = <int>[];
    try {
      final roots = <String>[];
      final candidates =
          directories
              .map((directory) => p.normalize(p.absolute(directory.path)))
              .toSet()
              .toList()
            ..sort((a, b) => a.length.compareTo(b.length));
      for (final original in candidates) {
        if (roots.any(
          (root) => p.equals(root, original) || p.isWithin(root, original),
        )) {
          continue;
        }
        if (!await exists(original)) continue;
        roots.add(original);
        // Allocate an identifier durably before moving any bytes. An existing
        // quarantine is never overwritten, even after restoring an old DB.
        late int id;
        late String quarantine;
        runSqliteTransaction(db, () {
          db.execute(
            'INSERT INTO local_deletion_journal(original_path, quarantine_path) VALUES (?, ?)',
            [original, ''],
          );
          id = db.lastInsertRowId;
          quarantine = p.join(
            p.dirname(original),
            '.venera-delete-$id-${DateTime.now().microsecondsSinceEpoch}',
          );
          db.execute(
            'UPDATE local_deletion_journal SET quarantine_path = ? WHERE id = ?',
            [quarantine, id],
          );
        });
        ids.add(id);
        if (await exists(quarantine)) {
          // This path is not owned by us. Forget this unstarted entry so a
          // recovery attempt cannot restore or delete someone else's directory.
          db.execute('DELETE FROM local_deletion_journal WHERE id = ?', [id]);
          throw FileSystemException(
            'Deletion quarantine already exists',
            quarantine,
          );
        }
        await Directory(original).rename(quarantine);
      }
      await commit(() {
        if (db.autocommit) {
          throw StateError('Deletion journal requires an active transaction');
        }
        for (final id in ids) {
          db.execute(
            'UPDATE local_deletion_journal SET committed = 1 WHERE id = ?',
            [id],
          );
        }
      });
    } catch (error, stack) {
      try {
        // Committed quarantines stay for the purge after a publication error.
        await recoverUncommitted();
      } catch (recoveryError, recoveryStack) {
        throw LocalDeletionRecoveryFailure(
          error,
          stack,
          recoveryError,
          recoveryStack,
        );
      }
      Error.throwWithStackTrace(error, stack);
    }
  }
}

/// Runs [LocalDeletionJournal.purgeCommitted] passes one at a time in the
/// background. A request during a pass runs one more pass afterwards. Errors
/// are reported; their rows stay for the next request or startup.
class LocalDeletionCleaner {
  LocalDeletionCleaner(this._purge, {required this.onError});

  final Future<void> Function(bool Function() isStopped) _purge;
  final void Function(Object error, StackTrace stack) onError;
  Future<void>? _pass;
  bool _requested = false;
  bool _stopped = false;

  /// Completes when no pass is running or requested.
  Future<void> get idle async {
    for (var pass = _pass; pass != null; pass = _pass) {
      await pass;
    }
  }

  void schedule() {
    if (_stopped) return;
    _requested = true;
    _pass ??= _run();
  }

  /// Ends after the directory being removed; an interrupted removal resumes
  /// from its committed row on the next start.
  void stop() => _stopped = true;

  Future<void> _run() async {
    try {
      while (_requested && !_stopped) {
        _requested = false;
        // Never run within the caller's turn or storage reservation.
        await Future<void>.delayed(Duration.zero);
        if (_stopped) break;
        try {
          await _purge(() => _stopped);
        } catch (error, stack) {
          onError(error, stack);
        }
      }
    } finally {
      _pass = null;
    }
  }
}

class LocalDeletionRecoveryFailure implements Exception {
  const LocalDeletionRecoveryFailure(
    this.operation,
    this.operationStack,
    this.recovery,
    this.recoveryStack,
  );
  final Object operation;
  final StackTrace operationStack;
  final Object recovery;
  final StackTrace recoveryStack;
  @override
  String toString() =>
      'Local deletion failed: $operation; recovery failed: $recovery';
}
