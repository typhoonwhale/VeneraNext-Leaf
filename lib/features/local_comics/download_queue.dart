import 'dart:collection';
import 'dart:async';
import 'package:venera_next/foundation/comic_type.dart';
import 'download_task.dart';
import 'local_comic_model.dart';

/// Ordered task coordination, independent of global managers and concrete
/// download implementations. Storage/notification adapters are supplied by owner.
class DownloadQueue {
  DownloadQueue({
    required this.commitComic,
    required this.notifyChanged,
    required this.requestSave,
    required this.reportError,
  });

  final void Function(LocalComic) commitComic;
  final void Function() notifyChanged;
  final void Function() requestSave;
  final void Function(Object, StackTrace) reportError;
  Future<void>? _pendingStop;
  int? _scheduledResumeRevision;
  Completer<void>? _suspension;
  final _automaticStartHolds = <Object>{};
  int? _heldAutomaticStartRevision;
  bool _scheduledResumeAutomatic = false;

  bool get isSuspended => _suspension != null;

  /// Persisted user intent; system suspension and exit preparation never
  /// change it. Snapshot decoding treats missing or invalid intent as paused.
  final _pausedByUser = Set<DownloadTask>.identity();

  bool isPausedByUser(DownloadTask task) => _pausedByUser.contains(task);

  final List<DownloadTask> _tasks = [];
  late final List<DownloadTask> tasks = UnmodifiableListView(_tasks);
  final _completing = Set<DownloadTask>.identity();
  final _canceling = Set<DownloadTask>.identity();
  int _revision = 0;

  /// Publish a complete paused snapshot during initialization/recovery, without
  /// starting tasks, notifying listeners or writing the snapshot back to disk.
  void restorePausedTasks(
    Iterable<DownloadTask> restored, {
    Iterable<DownloadTask> pausedByUser = const [],
  }) {
    if (_suspension != null) throw StateError('Download queue is suspended');
    final revision = _revision;
    final snapshot = <DownloadTask>[];
    final identities = <(String, int)>{};
    for (final task in restored) {
      if (!task.isPaused) throw StateError('Cannot restore a running task');
      if (identities.add((task.id, task.comicType.value))) snapshot.add(task);
    }
    if (_pendingStop != null ||
        revision != _revision ||
        _completing.isNotEmpty ||
        _tasks.any((task) => !task.isPaused)) {
      throw StateError('Cannot replace an active or changed download queue');
    }
    _tasks
      ..clear()
      ..addAll(snapshot);
    _pausedByUser
      ..clear()
      ..addAll(pausedByUser.where((task) => _indexOf(task) >= 0));
    _revision++;
  }

  bool contains(String id, ComicType type) =>
      tasks.any((task) => task.id == id && task.comicType == type);

  int _indexOf(DownloadTask task) =>
      tasks.indexWhere((current) => identical(current, task));

  void _publish() {
    notifyChanged();
    requestSave();
  }

  void add(DownloadTask task) {
    if (_suspension != null) throw StateError('Download queue is suspended');
    if (contains(task.id, task.comicType)) return;
    _tasks.add(task);
    final revision = ++_revision;
    _publish();
    _resumeIfUnchanged(revision, automatic: true);
  }

  void complete(DownloadTask task) {
    if (_suspension != null) return;
    if (_indexOf(task) < 0 || !_completing.add(task)) return;
    try {
      final comic = task.toLocalComic();
      if (_indexOf(task) < 0) return;
      // Commit adapters and task methods may synchronously reenter the queue.
      // Never reuse an index captured before calling them.
      commitComic(comic);
      final index = _indexOf(task);
      if (index < 0) return;
      _tasks.removeAt(index);
      _pausedByUser.remove(task);
      final revision = ++_revision;
      _publish();
      _resumeIfUnchanged(revision, automatic: true);
    } finally {
      _completing.remove(task);
    }
  }

  void _resumeIfUnchanged(int revision, {bool automatic = false}) {
    // A nested queue operation owns the final scheduling decision.
    if (_suspension != null || revision != _revision) return;
    if (automatic && _automaticStartHolds.isNotEmpty) {
      // The last released hold performs this start if nothing changed since.
      _scheduledResumeRevision = null;
      _heldAutomaticStartRevision = revision;
      return;
    }
    final stop = _pendingStop;
    if (stop == null) {
      _scheduledResumeRevision = null;
      if (automatic) {
        _startFirstNotPausedByUser();
      } else {
        tasks.firstOrNull?.resume();
      }
    } else {
      _scheduledResumeRevision = revision;
      _scheduledResumeAutomatic = automatic;
      unawaited(
        stop
            .then<void>(
              (_) => _resumeIfUnchanged(revision, automatic: automatic),
              onError: (Object error, StackTrace stack) {},
            )
            .catchError(reportError),
      );
    }
  }

  /// Automatic starts never run a task the user paused. Only the head runs, so
  /// the first task the user did not pause moves ahead of the skipped ones,
  /// which keep their relative order. A running head stays the only task run.
  void _startFirstNotPausedByUser() {
    final head = tasks.firstOrNull;
    if (head == null) return;
    if (!head.isPaused || !_pausedByUser.contains(head)) {
      head.resume();
      return;
    }
    final index = _tasks.indexWhere((task) => !_pausedByUser.contains(task));
    if (index < 0) return;
    if (index > 0) {
      _tasks.insert(0, _tasks.removeAt(index));
      final revision = ++_revision;
      _publish();
      // A listener reentering the queue owns the final scheduling decision.
      if (revision != _revision) return;
    }
    _tasks.first.resume();
  }

  /// A queued start is still cancellable while an older task is stopping.
  bool get isResumePending =>
      _pendingStop != null && _scheduledResumeRevision == _revision;

  /// A manual resume records user intent and is allowed while automatic
  /// starts are held; an automatic resume does neither.
  void resume(DownloadTask task, {bool automatic = false}) {
    if (_suspension != null ||
        !identical(tasks.firstOrNull, task) ||
        !task.isPaused ||
        isResumePending) {
      return;
    }
    if (!automatic && _pausedByUser.remove(task)) requestSave();
    final revision = ++_revision;
    _scheduledResumeRevision = revision;
    notifyChanged();
    _resumeIfUnchanged(revision, automatic: automatic);
  }

  /// Start the restored head only when the user had not paused it. Tasks
  /// behind a user-paused head keep waiting, as they did before the restart.
  void resumeByIntent() {
    final first = tasks.firstOrNull;
    if (first != null && !isPausedByUser(first)) {
      resume(first, automatic: true);
    }
  }

  Future<void> pause(DownloadTask task, {bool byUser = false}) {
    if (_suspension != null) return _suspension!.future;
    if (!identical(tasks.firstOrNull, task)) return Future.value();
    _revision++;
    _scheduledResumeRevision = null;
    if (byUser && _pausedByUser.add(task)) requestSave();
    final stopped = _stopBeforeScheduling(task, task.pause);
    notifyChanged();
    return stopped;
  }

  Future<void> cancel(DownloadTask task) {
    if (_suspension != null) return _suspension!.future;
    if (_indexOf(task) < 0 || !_canceling.add(task)) return Future.value();
    final before = _revision;
    final keepPendingStart =
        isResumePending && !identical(tasks.firstOrNull, task);
    final stopped = _stopBeforeScheduling(task, () {
      try {
        task.cancel();
        // Concrete tasks currently remove themselves through the manager.
        // Identity-based removal is also safe for tasks that do not.
        remove(task);
      } finally {
        _canceling.remove(task);
      }
    });
    // Do not replace a newer listener action with the pre-cancel start intent.
    if (keepPendingStart && _revision == before + 1) {
      _resumeIfUnchanged(_revision, automatic: _scheduledResumeAutomatic);
    }
    return stopped;
  }

  void remove(DownloadTask task) {
    final index = _indexOf(task);
    if (index < 0) return;
    _tasks.removeAt(index);
    _pausedByUser.remove(task);
    _revision++;
    _publish();
  }

  Future<void> moveToFirst(DownloadTask task) {
    if (_suspension != null) return _suspension!.future;
    if (_indexOf(task) <= 0) return Future.value();
    final first = tasks.first;
    final shouldResume =
        !first.isPaused || _scheduledResumeRevision == _revision;
    final beforePause = _revision;
    final stopped = _stopBeforeScheduling(first, first.pause);
    if (beforePause != _revision || !identical(tasks.firstOrNull, first)) {
      return stopped;
    }
    final index = _indexOf(task);
    if (index <= 0) return stopped;
    _tasks.removeAt(index);
    _tasks.insert(0, task);
    final revision = ++_revision;
    _publish();
    if (shouldResume) _resumeIfUnchanged(revision);
    return stopped;
  }

  /// Stop the queue from starting tasks on its own until this holder releases.
  /// Running tasks continue and manual resume still works. Holders are
  /// independent of each other and of [suspend]; release is idempotent.
  void Function() holdAutomaticStarts() {
    final hold = Object();
    _automaticStartHolds.add(hold);
    return () {
      if (!_automaticStartHolds.remove(hold) ||
          _automaticStartHolds.isNotEmpty) {
        return;
      }
      final revision = _heldAutomaticStartRevision;
      _heldAutomaticStartRevision = null;
      if (revision == _revision) {
        _resumeIfUnchanged(revision!, automatic: true);
      }
    };
  }

  /// Freeze admissions/scheduling and drain all accepted pause/cancel work.
  /// The owner releases the suspension if shutdown is abandoned.
  Future<void> suspend({bool notify = true}) {
    if (_suspension != null) return _suspension!.future;
    final completion = _suspension = Completer<void>();
    completion.future.ignore();
    _revision++;
    _scheduledResumeRevision = null;
    for (final task in List<DownloadTask>.of(tasks)) {
      _stopBeforeScheduling(task, task.pause);
    }
    if (notify) notifyChanged();
    unawaited(() async {
      try {
        while (_pendingStop != null) {
          await _pendingStop;
        }
        completion.complete();
      } catch (error, stack) {
        completion.completeError(error, stack);
      }
    }());
    return completion.future;
  }

  void releaseSuspension(Future<void> preparation, {bool notify = true}) {
    final suspension = _suspension;
    if (suspension == null || !identical(suspension.future, preparation)) {
      return;
    }
    if (!suspension.isCompleted) {
      throw StateError('Download cleanup has not completed');
    }
    _suspension = null;
    _revision++;
    _scheduledResumeRevision = null;
    if (notify) notifyChanged();
  }

  Future<void> _stopBeforeScheduling(DownloadTask task, void Function() stop) {
    final previous = _pendingStop;
    final gate = Completer<void>();
    final stopped = _pendingStop = gate.future;
    // UI callers may ignore the result; failures are also sent to the owner.
    stopped.ignore();
    void finish([Object? error, StackTrace? stack]) {
      final isLatest = identical(_pendingStop, stopped);
      if (isLatest) _pendingStop = null;
      if (error == null) {
        gate.complete();
      } else {
        gate.completeError(error, stack);
        if (isLatest) {
          _scheduledResumeRevision = null;
          notifyChanged();
        }
        reportError(error, stack!);
      }
    }

    // Install the barrier before stop can notify/reenter queue operations.
    try {
      stop();
      unawaited(
        Future.wait<void>([?previous, task.pendingCleanup]).then<void>(
          (_) => finish(),
          onError: (Object error, StackTrace stack) => finish(error, stack),
        ),
      );
    } catch (error, stack) {
      scheduleMicrotask(() => finish(error, stack));
    }
    return stopped;
  }
}
