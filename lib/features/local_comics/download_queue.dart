import 'dart:collection';
import 'dart:async';
import 'package:venera_next/foundation/comic_type.dart';
import 'download_task.dart';
import 'local_comic_model.dart';

/// Persisted queue state of a task. [paused] (by the user) and [error] tasks
/// are parked: they keep their place in the list but nothing starts them
/// until the user resumes them.
enum DownloadTaskState { normal, paused, error }

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

  /// Parked tasks only; every other task is normal. System suspension and
  /// exit preparation never change a state.
  final _parked = Map<DownloadTask, DownloadTaskState>.identity();

  DownloadTaskState stateOf(DownloadTask task) =>
      _parked[task] ?? DownloadTaskState.normal;

  /// The only task the queue may run: the first normal task.
  DownloadTask? get activeTask {
    for (final task in _tasks) {
      if (!_parked.containsKey(task)) return task;
    }
    return null;
  }

  bool get _hasRunningTask => _tasks.any((task) => !task.isPaused);

  final List<DownloadTask> _tasks = [];
  late final List<DownloadTask> tasks = UnmodifiableListView(_tasks);
  final _completing = Set<DownloadTask>.identity();
  final _canceling = Set<DownloadTask>.identity();
  int _revision = 0;

  /// Publish a complete paused snapshot during initialization/recovery, without
  /// starting tasks, notifying listeners or writing the snapshot back to disk.
  void restorePausedTasks(
    Iterable<DownloadTask> restored, {
    Map<DownloadTask, DownloadTaskState> states = const {},
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
    _parked.clear();
    for (final MapEntry(key: task, value: state) in states.entries) {
      if (state != DownloadTaskState.normal && _indexOf(task) >= 0) {
        _parked[task] = state;
      }
    }
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
      _parked.remove(task);
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
      activeTask?.resume();
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

  /// A queued start is still cancellable while an older task is stopping.
  bool get isResumePending =>
      _pendingStop != null && _scheduledResumeRevision == _revision;

  /// A manual resume. A parked task becomes normal at the end of the list
  /// and starts only when nothing runs; while automatic starts are held it
  /// starts only as the first normal task. A normal task starts only as the
  /// idle first normal task.
  void resume(DownloadTask task) {
    if (_suspension != null || _indexOf(task) < 0) return;
    if (_parked.containsKey(task)) {
      _resumeParked(task);
      return;
    }
    if (!identical(activeTask, task) || !task.isPaused || isResumePending) {
      return;
    }
    final revision = ++_revision;
    _scheduledResumeRevision = revision;
    notifyChanged();
    _resumeIfUnchanged(revision);
  }

  void _resumeParked(DownloadTask task) {
    if (_parked.remove(task) == DownloadTaskState.error) {
      task.retryAfterFailure();
    }
    _tasks.removeAt(_indexOf(task));
    _tasks.add(task);
    final revision = ++_revision;
    _publish();
    // A listener reentering the queue owns the final scheduling decision.
    if (revision != _revision || _hasRunningTask) return;
    _resumeIfUnchanged(revision, automatic: !identical(activeTask, task));
  }

  /// Start the restored first normal task. Parked tasks keep waiting, as they
  /// did before the restart.
  void resumeByIntent() {
    final first = activeTask;
    if (_suspension != null ||
        first == null ||
        !first.isPaused ||
        isResumePending) {
      return;
    }
    final revision = ++_revision;
    _scheduledResumeRevision = revision;
    notifyChanged();
    _resumeIfUnchanged(revision, automatic: true);
  }

  /// A pause [byUser] parks any normal task; stopping the running task
  /// advances the queue to the next normal task. A system pause only stops
  /// the first normal task and keeps its state.
  Future<void> pause(DownloadTask task, {bool byUser = false}) {
    if (_suspension != null) return _suspension!.future;
    if (byUser) return _park(task, DownloadTaskState.paused);
    if (!identical(activeTask, task)) return Future.value();
    _revision++;
    _scheduledResumeRevision = null;
    final stopped = _stopBeforeScheduling(task, task.pause);
    notifyChanged();
    return stopped;
  }

  /// Called by a task whose run failed; it is parked until a manual resume.
  void fail(DownloadTask task) => _park(task, DownloadTaskState.error);

  Future<void> _park(DownloadTask task, DownloadTaskState state) {
    if (_indexOf(task) < 0 || _parked.containsKey(task)) return Future.value();
    final active = identical(activeTask, task);
    final startPending = isResumePending;
    final advance =
        startPending ||
        (active && (state == DownloadTaskState.error || !task.isPaused));
    final automatic = active || _scheduledResumeAutomatic;
    _parked[task] = state;
    _scheduledResumeRevision = null;
    // A failed task has already stopped; only a user pause stops the task.
    final stopped = active && state == DownloadTaskState.paused
        ? _stopBeforeScheduling(task, task.pause)
        : Future<void>.value();
    final revision = ++_revision;
    _publish();
    if (advance) _resumeIfUnchanged(revision, automatic: automatic);
    return stopped;
  }

  /// Park every normal task as paused by the user and stop the running one.
  Future<void> pauseAll() {
    if (_suspension != null) return _suspension!.future;
    final active = activeTask;
    if (active == null) return Future.value();
    for (final task in _tasks) {
      _parked.putIfAbsent(task, () => DownloadTaskState.paused);
    }
    _scheduledResumeRevision = null;
    final stopped = _stopBeforeScheduling(active, active.pause);
    _revision++;
    _publish();
    return stopped;
  }

  Future<void> cancel(DownloadTask task) {
    if (_suspension != null) return _suspension!.future;
    if (_indexOf(task) < 0 || !_canceling.add(task)) return Future.value();
    final before = _revision;
    final keepPendingStart = isResumePending && !identical(activeTask, task);
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
    _parked.remove(task);
    _revision++;
    _publish();
  }

  /// A normal task becomes the running task if the first normal task was
  /// running or about to start. Any other move only reorders the list.
  Future<void> moveToFirst(DownloadTask task) {
    if (_suspension != null) return _suspension!.future;
    if (_indexOf(task) <= 0) return Future.value();
    final first = activeTask;
    if (first == null || identical(first, task) || _parked.containsKey(task)) {
      final startPending = isResumePending;
      _tasks.insert(0, _tasks.removeAt(_indexOf(task)));
      final revision = ++_revision;
      _publish();
      if (startPending) {
        _resumeIfUnchanged(revision, automatic: _scheduledResumeAutomatic);
      }
      return Future.value();
    }
    final shouldResume =
        !first.isPaused || _scheduledResumeRevision == _revision;
    final beforePause = _revision;
    final stopped = _stopBeforeScheduling(first, first.pause);
    if (beforePause != _revision || !identical(activeTask, first)) {
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
