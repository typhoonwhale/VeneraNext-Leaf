import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:venera_next/features/local_comics/download_queue.dart';
import 'package:venera_next/features/local_comics/download_task.dart';
import 'package:venera_next/features/local_comics/local_comic_model.dart';
import 'package:venera_next/foundation/comic_type.dart';

void main() {
  late List<String> events;
  late DownloadQueue queue;
  late bool failCommit;
  void Function()? onCommit;
  void Function()? onNotify;
  setUp(() {
    events = [];
    failCommit = false;
    onCommit = null;
    onNotify = null;
    queue = DownloadQueue(
      commitComic: (comic) {
        events.add('commit:${comic.id}');
        if (failCommit) throw StateError('injected');
        onCommit?.call();
      },
      notifyChanged: () {
        events.add('notify');
        onNotify?.call();
      },
      requestSave: () => events.add('save'),
      reportError: (error, stack) => events.add('error:$error'),
    );
  });

  test(
    'move publishes immediately but all automatic starts wait for cleanup',
    () async {
      final gate = Completer<void>();
      final first = _Task('a', events)..cleanup = gate.future;
      final target = _Task('b', events);
      queue.add(first);
      queue.add(target);
      events.clear();
      final moved = queue.moveToFirst(target);
      expect(queue.tasks.first, target);
      expect(events, ['pause:a', 'notify', 'save']);
      expect(() => queue.restorePausedTasks([]), throwsStateError);
      queue.add(_Task('c', events));
      await pumpEventQueue();
      expect(events.where((event) => event.startsWith('resume:')), isEmpty);
      gate.complete();
      await moved;
      await pumpEventQueue();
      expect(events.where((event) => event.startsWith('resume:')), [
        'resume:b',
      ]);
    },
  );

  test(
    'overlapping moves retain running intent and wait for every old stop',
    () async {
      final gates = [Completer<void>(), Completer<void>()];
      final first = _Task('a', events)..cleanup = gates[0].future;
      final second = _Task('b', events)..cleanup = gates[1].future;
      final last = _Task('c', events);
      queue.add(first);
      queue.add(second);
      queue.add(last);
      events.clear();
      final moveSecond = queue.moveToFirst(second);
      final moveLast = queue.moveToFirst(last);
      gates[1].complete();
      await pumpEventQueue();
      expect(events.where((event) => event.startsWith('resume:')), isEmpty);
      gates[0].complete();
      await Future.wait([moveSecond, moveLast]);
      await pumpEventQueue();
      expect(queue.tasks.first, last);
      expect(events.where((event) => event.startsWith('resume:')), [
        'resume:c',
      ]);
    },
  );

  for (final throwsDuringPause in [false, true]) {
    test(
      'failed stop prevents automatic start (pause throws: $throwsDuringPause)',
      () async {
        final gate = Completer<void>();
        final first = _Task('a', events);
        if (throwsDuringPause) {
          first.onPause = () => throw StateError('stop failed');
        } else {
          first.cleanup = gate.future;
        }
        final target = _Task('b', events);
        queue.add(first);
        queue.add(target);
        events.clear();
        final moved = queue.moveToFirst(target);
        final failed = expectLater(moved, throwsStateError);
        if (!throwsDuringPause) gate.completeError(StateError('stop failed'));
        await failed;
        await pumpEventQueue();
        expect(events.where((event) => event.startsWith('resume:')), isEmpty);
        expect(
          events.where((event) => event.startsWith('error:')),
          hasLength(1),
        );
        expect(queue.tasks.first, target);
      },
    );
  }

  test(
    'manual pause cancels pending start and manual resume respects prior stop',
    () async {
      final gate = Completer<void>();
      final first = _Task('a', events)..cleanup = gate.future;
      final second = _Task('b', events);
      queue.add(first);
      queue.add(second);
      events.clear();
      final moved = queue.moveToFirst(second);
      expect(queue.isResumePending, isTrue);
      final paused = queue.pause(second);
      expect(queue.isResumePending, isFalse);
      queue.resume(second);
      queue.resume(second);
      expect(queue.isResumePending, isTrue);
      await pumpEventQueue();
      expect(events.where((event) => event.startsWith('resume:')), isEmpty);
      final canceledStart = queue.pause(second);
      gate.complete();
      await Future.wait([moved, paused, canceledStart]);
      await pumpEventQueue();
      expect(events.where((event) => event.startsWith('resume:')), isEmpty);
      expect(queue.isResumePending, isFalse);
      queue.resume(second);
      expect(events.where((event) => event.startsWith('resume:')), [
        'resume:b',
      ]);
    },
  );

  test(
    'manual controls ignore stale instances and tasks outside the head',
    () async {
      final first = _Task('a', events);
      final second = _Task('b', events);
      queue.restorePausedTasks([first, second]);
      queue.resume(_Task('a', events));
      queue.resume(second);
      await queue.pause(_Task('a', events));
      await queue.pause(second);
      expect(events, isEmpty);
      queue.resume(first);
      expect(events, ['notify', 'resume:a']);
      events.clear();
      queue.resume(first);
      expect(events, isEmpty);
    },
  );

  test(
    'notification pause invalidates a manual start before it reaches the task',
    () async {
      final task = _Task('a', events);
      queue.restorePausedTasks([task]);
      Future<void>? paused;
      onNotify = () {
        onNotify = null;
        paused = queue.pause(task);
      };
      queue.resume(task);
      await paused;
      await pumpEventQueue();
      expect(task.isPaused, isTrue);
      expect(queue.isResumePending, isFalse);
      expect(events.where((event) => event.startsWith('resume:')), isEmpty);
    },
  );

  test(
    'failed stop clears pending-start state and notifies controls',
    () async {
      final gate = Completer<void>();
      final first = _Task('a', events)..cleanup = gate.future;
      final second = _Task('b', events);
      queue.add(first);
      queue.add(second);
      final moved = queue.moveToFirst(second);
      expect(queue.isResumePending, isTrue);
      events.clear();
      final failure = expectLater(moved, throwsStateError);
      gate.completeError(StateError('cannot stop'));
      await failure;
      await pumpEventQueue();
      expect(queue.isResumePending, isFalse);
      expect(events.where((event) => event == 'notify'), hasLength(1));
      expect(second.isPaused, isTrue);
    },
  );

  test(
    'cancel tracks cleanup assigned after removal and gates a replacement start',
    () async {
      final gate = Completer<void>();
      final first = _Task('a', events);
      final replacement = _Task('a', events);
      first.onCancel = () {
        queue.remove(first);
        queue.add(replacement);
        first.cleanup = gate.future;
      };
      queue.add(first);
      events.clear();
      final canceled = queue.cancel(first);
      expect(identical(queue.tasks.single, replacement), isTrue);
      await pumpEventQueue();
      expect(events.where((event) => event.startsWith('resume:')), isEmpty);
      gate.complete();
      await canceled;
      await pumpEventQueue();
      expect(events.where((event) => event.startsWith('resume:')), [
        'resume:a',
      ]);
    },
  );

  test(
    'canceling the running task advances and ignores stale or recursive requests',
    () async {
      final first = _Task('a', events);
      final next = _Task('b', events);
      var cancels = 0;
      first.onCancel = () {
        cancels++;
        queue.cancel(first);
      };
      queue.add(first);
      queue.add(next);
      events.clear();
      await queue.cancel(_Task('a', events));
      expect(events, isEmpty);
      await queue.cancel(first);
      await queue.cancel(first);
      await pumpEventQueue();
      expect(cancels, 1);
      expect(queue.tasks, [next]);
      expect(next.isPaused, isFalse);
      expect(events.where((event) => event.startsWith('resume:')), [
        'resume:b',
      ]);
    },
  );

  test(
    'canceling the running task waits for cleanup and respects holds',
    () async {
      final gate = Completer<void>();
      final first = _Task('a', events)..cleanup = gate.future;
      final next = _Task('b', events);
      final idle = _Task('c', events);
      queue.add(first);
      queue.add(next);
      queue.add(idle);
      final canceled = queue.cancel(first);
      expect(queue.isResumePending, isTrue);
      await pumpEventQueue();
      expect(next.isPaused, isTrue);
      final release = queue.holdAutomaticStarts();
      gate.complete();
      await canceled;
      await pumpEventQueue();
      expect(next.isPaused, isTrue);
      release();
      expect(next.isPaused, isFalse);

      // An idle task is not running: canceling it starts nothing.
      await queue.pause(next);
      await queue.cancel(next);
      await pumpEventQueue();
      expect(idle.isPaused, isTrue);
    },
  );

  test(
    'canceling a tail retains pending head start but waits for its cleanup',
    () async {
      final gates = [Completer<void>(), Completer<void>()];
      final first = _Task('a', events)..cleanup = gates[0].future;
      final second = _Task('b', events);
      final tail = _Task('c', events)..cleanup = gates[1].future;
      queue.add(first);
      queue.add(second);
      queue.add(tail);
      events.clear();
      final moved = queue.moveToFirst(second);
      final canceled = queue.cancel(tail);
      gates[0].complete();
      await moved;
      await pumpEventQueue();
      expect(events.where((event) => event.startsWith('resume:')), isEmpty);
      gates[1].complete();
      await canceled;
      await pumpEventQueue();
      expect(events.where((event) => event.startsWith('resume:')), [
        'resume:b',
      ]);
    },
  );

  test('cancel listener pause overrides an older pending start', () async {
    final gate = Completer<void>();
    final first = _Task('a', events)..cleanup = gate.future;
    final second = _Task('b', events);
    final tail = _Task('c', events);
    queue.add(first);
    queue.add(second);
    queue.add(tail);
    final moved = queue.moveToFirst(second);
    Future<void>? paused;
    tail.onCancel = () => paused = queue.pause(second);
    events.clear();
    final canceled = queue.cancel(tail);
    gate.complete();
    await Future.wait([moved, canceled, paused!]);
    await pumpEventQueue();
    expect(second.isPaused, isTrue);
    expect(events.where((event) => event.startsWith('resume:')), isEmpty);
  });

  test(
    'suspension drains removed cancellation and freezes admission until release',
    () async {
      final gate = Completer<void>();
      final removed = _Task('a', events)..cleanup = gate.future;
      final next = _Task('b', events);
      queue.add(removed);
      queue.add(next);
      final canceled = queue.cancel(removed);
      final suspended = queue.suspend();
      expect(identical(suspended, queue.suspend()), isTrue);
      expect(() => queue.add(_Task('c', events)), throwsStateError);
      expect(() => queue.restorePausedTasks([]), throwsStateError);
      expect(() => queue.releaseSuspension(suspended), throwsStateError);
      events.clear();
      queue.resume(next);
      var completed = false;
      suspended.then((_) => completed = true);
      await pumpEventQueue();
      expect(completed, isFalse);
      gate.complete();
      await Future.wait([canceled, suspended]);
      expect(events.where((event) => event.startsWith('resume:')), isEmpty);
      queue.releaseSuspension(suspended);
      expect(next.isPaused, isTrue);
      queue.resume(next);
      expect(next.isPaused, isFalse);
    },
  );

  test(
    'suspension pauses every task and failed drain can be released and retried',
    () async {
      final first = _Task('a', events)
        ..cleanup = Future.error(StateError('cleanup'));
      final second = _Task('b', events);
      queue.restorePausedTasks([first, second]);
      final suspended = queue.suspend();
      await expectLater(suspended, throwsStateError);
      expect(events, containsAll(['pause:a', 'pause:b']));
      queue.releaseSuspension(suspended);
      first.cleanup = null;
      final retry = queue.suspend();
      await retry;
      queue.releaseSuspension(suspended);
      queue.resume(first);
      expect(first.isPaused, isTrue);
      queue.releaseSuspension(retry);
      queue.resume(first);
      expect(first.isPaused, isFalse);
    },
  );

  test('task view rejects mutations but reflects service updates', () {
    final view = queue.tasks;
    final task = _Task('a', events);
    expect(() => view.add(task), throwsUnsupportedError);
    queue.add(task);
    expect(view, [task]);
    expect(() => view.clear(), throwsUnsupportedError);
    expect(() => view[0] = _Task('b', events), throwsUnsupportedError);
    queue.remove(task);
    expect(view, isEmpty);
  });

  test(
    'paused restoration is complete, silent and deduplicated by source identity',
    () {
      final first = _Task('a', events);
      final other = _Task('a', events, type: 18);
      queue.restorePausedTasks([first, _Task('a', events), other]);
      expect(queue.tasks, [first, other]);
      expect(identical(queue.tasks.first, first), isTrue);
      expect(events, isEmpty);
      Iterable<DownloadTask> broken() sync* {
        yield _Task('new', events);
        throw StateError('injected decode failure');
      }

      expect(() => queue.restorePausedTasks(broken()), throwsStateError);
      expect(queue.tasks, [first, other]);
      queue.restorePausedTasks(queue.tasks);
      expect(queue.tasks, [first, other]);
      queue.restorePausedTasks([]);
      expect(queue.tasks, isEmpty);
      expect(events, isEmpty);
    },
  );

  test(
    'restoration rejects active current or incoming tasks without changing state',
    () {
      final running = _Task('a', events);
      queue.add(running);
      events.clear();
      expect(() => queue.restorePausedTasks([]), throwsStateError);
      expect(queue.tasks, [running]);
      running.pause();
      final incoming = _Task('b', events)..resume();
      events.clear();
      expect(() => queue.restorePausedTasks([incoming]), throwsStateError);
      expect(queue.tasks, [running]);
      expect(events, isEmpty);
      incoming.pause();
      queue.restorePausedTasks([incoming]);
      expect(queue.tasks, [incoming]);
    },
  );

  test(
    'pause listener removing the target cannot remove another task or reinsert it',
    () async {
      final first = _Task('a', events);
      final target = _Task('b', events);
      final last = _Task('c', events);
      queue.add(first);
      queue.add(target);
      queue.add(last);
      first.onPause = () => queue.remove(target);
      events.clear();
      await queue.moveToFirst(target);
      expect(queue.tasks, [first, last]);
      expect(events, ['pause:a', 'notify', 'save']);
      expect(last.isPaused, isTrue);
    },
  );

  test(
    'nested notification mutation owns scheduling and outer add does not resume twice',
    () {
      final first = _Task('a', events);
      final second = _Task('b', events);
      onNotify = () {
        onNotify = null;
        queue.add(second);
      };
      queue.add(first);
      expect(queue.tasks, [first, second]);
      expect(events.where((event) => event.startsWith('resume:')), [
        'resume:a',
      ]);
    },
  );

  test(
    'completion recalculates task index after commit callback changes queue',
    () {
      final first = _Task('a', events);
      final target = _Task('b', events);
      final last = _Task('c', events);
      queue.add(first);
      queue.add(target);
      queue.add(last);
      onCommit = () => queue.remove(first);
      events.clear();
      queue.complete(target);
      expect(queue.tasks, [last]);
      expect(events, [
        'commit:b',
        'notify',
        'save',
        'notify',
        'save',
        'resume:c',
      ]);
    },
  );

  test('same task completion cannot recursively commit twice', () {
    final task = _Task('a', events);
    queue.add(task);
    onCommit = () => queue.complete(task);
    events.clear();
    queue.complete(task);
    expect(queue.tasks, isEmpty);
    expect(events, ['commit:a', 'notify', 'save']);
  });

  test(
    'add publishes before resuming head and rejects duplicate source identity',
    () {
      final first = _Task('a', events);
      queue.add(first);
      expect(events, ['notify', 'save', 'resume:a']);
      events.clear();
      queue.add(_Task('a', events));
      expect(events, isEmpty);
      expect(queue.tasks, [first]);
      queue.add(_Task('a', events, type: 18));
      expect(queue.tasks, hasLength(2));
      expect(queue.contains('a', const ComicType(17)), isTrue);
      expect(queue.contains('a', const ComicType(18)), isTrue);
      expect(queue.contains('a', const ComicType(19)), isFalse);
      expect(events, ['notify', 'save', 'resume:a']);
    },
  );

  test(
    'move preserves running or paused state and ignores missing or first task',
    () async {
      final first = _Task('a', events);
      final second = _Task('b', events);
      await queue.moveToFirst(first);
      expect(events, isEmpty);
      queue.add(first);
      queue.add(second);
      events.clear();
      await queue.moveToFirst(second);
      expect(queue.tasks, [second, first]);
      expect(events, ['pause:a', 'notify', 'save', 'resume:b']);
      events.clear();
      await queue.moveToFirst(second);
      await queue.moveToFirst(_Task('b', events));
      expect(events, isEmpty);
      second.pause();
      events.clear();
      await queue.moveToFirst(first);
      expect(queue.tasks, [first, second]);
      expect(events, ['pause:b', 'notify', 'save']);
      expect(first.isPaused, isTrue);
    },
  );

  test(
    'stale callbacks cannot remove replacement and failed commit permits retry',
    () {
      final obsolete = _Task('a', events);
      final replacement = _Task('a', events);
      final next = _Task('b', events);
      queue.add(obsolete);
      queue.remove(obsolete);
      queue.add(replacement);
      queue.add(next);
      events.clear();
      queue.complete(obsolete);
      queue.remove(obsolete);
      queue.moveToFirst(obsolete);
      expect(events, isEmpty);
      expect(identical(queue.tasks.first, replacement), isTrue);
      failCommit = true;
      expect(() => queue.complete(replacement), throwsStateError);
      expect(events, ['commit:a']);
      expect(identical(queue.tasks.first, replacement), isTrue);
      failCommit = false;
      events.clear();
      queue.complete(replacement);
      expect(queue.tasks, [next]);
      expect(events, ['commit:a', 'notify', 'save', 'resume:b']);
      events.clear();
      queue.complete(replacement);
      expect(events, isEmpty);
    },
  );

  test(
    'held queue keeps running work, skips automatic starts and allows manual resume',
    () async {
      final first = _Task('a', events);
      final second = _Task('b', events);
      final third = _Task('c', events);
      queue.add(first);
      final release = queue.holdAutomaticStarts();
      queue.add(second);
      queue.add(third);
      expect(first.isPaused, isFalse);
      queue.complete(first);
      await pumpEventQueue();
      expect(queue.tasks.first, second);
      expect(second.isPaused, isTrue);
      expect(queue.isResumePending, isFalse);
      queue.resume(second);
      expect(second.isPaused, isFalse);
      queue.complete(second);
      await pumpEventQueue();
      expect(third.isPaused, isTrue);
      release();
      expect(third.isPaused, isFalse);
      expect(events.where((event) => event.startsWith('resume:')), [
        'resume:a',
        'resume:b',
        'resume:c',
      ]);
    },
  );

  test(
    'automatic start deferred behind a stop stays held until release',
    () async {
      final gate = Completer<void>();
      final first = _Task('a', events)..cleanup = gate.future;
      final second = _Task('b', events);
      queue.add(first);
      queue.add(second);
      final paused = queue.pause(first);
      queue.complete(first);
      expect(queue.isResumePending, isTrue);
      final release = queue.holdAutomaticStarts();
      gate.complete();
      await paused;
      await pumpEventQueue();
      expect(second.isPaused, isTrue);
      expect(queue.isResumePending, isFalse);
      release();
      expect(second.isPaused, isFalse);
    },
  );

  test('a newer manual action supersedes the held automatic start', () {
    final first = _Task('a', events);
    final second = _Task('b', events);
    queue.add(first);
    final release = queue.holdAutomaticStarts();
    queue.add(second);
    queue.complete(first);
    queue.pause(second, byUser: true);
    release();
    expect(second.isPaused, isTrue);
  });

  test('holders release independently and stale releases are no-ops', () {
    final first = _Task('a', events);
    final second = _Task('b', events);
    queue.add(first);
    final older = queue.holdAutomaticStarts();
    final newer = queue.holdAutomaticStarts();
    queue.add(second);
    queue.complete(first);
    older();
    older();
    expect(second.isPaused, isTrue);
    final latest = queue.holdAutomaticStarts();
    newer();
    expect(second.isPaused, isTrue);
    latest();
    expect(second.isPaused, isFalse);
  });

  test('holds and suspension never release each other', () async {
    final first = _Task('a', events);
    final second = _Task('b', events);
    queue.add(first);
    final release = queue.holdAutomaticStarts();
    queue.add(second);
    queue.complete(first);
    final suspension = queue.suspend();
    await suspension;
    release();
    expect(queue.isSuspended, isTrue);
    expect(second.isPaused, isTrue);
    final again = queue.holdAutomaticStarts();
    queue.releaseSuspension(suspension);
    queue.add(_Task('c', events));
    expect(second.isPaused, isTrue);
    again();
    expect(second.isPaused, isFalse);
  });

  const normal = DownloadTaskState.normal;
  const paused = DownloadTaskState.paused;
  const failed = DownloadTaskState.error;
  List<DownloadTaskState> states() => [
    for (final task in queue.tasks) queue.stateOf(task),
  ];
  List<String> resumes() =>
      events.where((event) => event.startsWith('resume:')).toList();

  test(
    'only user pause, failure and manual resume change state and save',
    () async {
      final first = _Task('a', events);
      final second = _Task('b', events);
      queue.restorePausedTasks([first, second], states: {second: paused});
      expect(states(), [normal, paused]);
      queue.resume(first);
      await queue.pause(first);
      await queue.suspend();
      expect(states(), [normal, paused]);
      expect(events.where((event) => event == 'save'), isEmpty);

      final restored = _Task('a', events);
      queue = DownloadQueue(
        commitComic: (_) {},
        notifyChanged: () {},
        requestSave: () => events.add('save'),
        reportError: (error, stack) => events.add('error:$error'),
      );
      queue.restorePausedTasks([restored]);
      queue.resume(restored);
      await queue.pause(restored, byUser: true);
      expect(queue.stateOf(restored), paused);
      queue.resumeByIntent();
      expect(restored.isPaused, isTrue);
      queue.resume(restored);
      expect(queue.stateOf(restored), normal);
      expect(restored.isPaused, isFalse);
      restored.status = 'Error: boom';
      queue.fail(restored);
      expect(queue.stateOf(restored), failed);
      expect(queue.errorMessageOf(restored), 'Error: boom');
      queue.resume(restored);
      expect(queue.errorMessageOf(restored), isNull);
      await queue.pause(restored, byUser: true);
      queue.restorePausedTasks(
        [restored],
        states: {restored: failed},
        errorMessages: {restored: 'Error: saved'},
      );
      expect(queue.errorMessageOf(restored), 'Error: saved');
      expect(events.where((event) => event == 'save'), hasLength(5));
    },
  );

  test('automatic paths never start parked tasks', () async {
    final userPaused = _Task('a', events);
    final broken = _Task('b', events);
    final waiting = _Task('c', events);
    final later = _Task('d', events);
    queue.restorePausedTasks(
      [userPaused, broken, waiting],
      states: {userPaused: paused, broken: failed},
    );
    queue.resumeByIntent();
    expect(resumes(), ['resume:c']);
    queue.add(later);
    queue.complete(waiting);
    // Adding behind the running task resumes only that running task again.
    expect(resumes(), ['resume:c', 'resume:c', 'resume:d']);
    // Parked tasks keep their place; nothing is reordered.
    expect(queue.tasks, [userPaused, broken, later]);
    final release = queue.holdAutomaticStarts();
    queue.complete(later);
    release();
    queue.add(_Task('e', events)..onResumeFail = queue.fail);
    await pumpEventQueue();
    queue.resumeByIntent();
    await pumpEventQueue();
    expect(resumes(), ['resume:c', 'resume:c', 'resume:d', 'resume:e']);
    expect(states(), [paused, failed, failed]);
    expect(userPaused.isPaused && broken.isPaused, isTrue);
  });

  test(
    'user pause and failure of the running task advance the queue',
    () async {
      final gate = Completer<void>();
      final first = _Task('a', events)..cleanup = gate.future;
      final second = _Task('b', events);
      final third = _Task('c', events);
      final fourth = _Task('d', events);
      queue.restorePausedTasks([first, second, third, fourth]);
      queue.resume(first);
      events.clear();
      final stopped = queue.pause(first, byUser: true);
      expect(events, ['pause:a', 'notify', 'save']);
      expect(queue.isResumePending, isTrue);
      await pumpEventQueue();
      expect(resumes(), isEmpty);
      gate.complete();
      await stopped;
      await pumpEventQueue();
      expect(resumes(), ['resume:b']);
      // The failed task stopped itself; the next start waits for its cleanup.
      second.pause();
      queue.fail(second);
      await pumpEventQueue();
      expect(resumes(), ['resume:b', 'resume:c']);
      // A parked task that is not running never advances the queue.
      await queue.pause(fourth, byUser: true);
      await pumpEventQueue();
      expect(resumes(), ['resume:b', 'resume:c']);
      expect(states(), [paused, failed, normal, paused]);
      expect(queue.activeTask, third);
    },
  );

  test(
    'manual resume moves a parked task to the end and starts it when idle',
    () async {
      final userPaused = _Task('a', events);
      final running = _Task('b', events);
      final broken = _Task('c', events);
      queue.restorePausedTasks(
        [userPaused, running, broken],
        states: {userPaused: paused, broken: failed},
      );
      queue.resume(running);
      queue.resume(userPaused);
      expect(queue.tasks, [running, broken, userPaused]);
      expect(states(), [normal, failed, normal]);
      expect(userPaused.isPaused, isTrue);
      expect(userPaused.failureRetries, 0);
      queue.complete(running);
      expect(userPaused.isPaused, isFalse);

      await queue.pause(userPaused, byUser: true);
      events.clear();
      queue.resume(broken);
      expect(queue.tasks, [userPaused, broken]);
      expect(broken.failureRetries, 1);
      expect(resumes(), ['resume:c']);
      expect(events.indexOf('retry:c'), lessThan(events.indexOf('resume:c')));
    },
  );

  test(
    'manual resume while held starts only as the first normal task',
    () async {
      final userPaused = _Task('a', events);
      final waiting = _Task('b', events);
      queue.restorePausedTasks(
        [userPaused, waiting],
        states: {userPaused: paused},
      );
      final release = queue.holdAutomaticStarts();
      queue.resume(userPaused);
      expect(queue.tasks, [waiting, userPaused]);
      expect(resumes(), isEmpty);
      release();
      expect(resumes(), ['resume:b']);

      final only = _Task('c', events);
      queue.remove(waiting);
      queue.remove(userPaused);
      queue.add(only);
      await queue.pause(only, byUser: true);
      final again = queue.holdAutomaticStarts();
      queue.resume(only);
      expect(only.isPaused, isFalse);
      again();
    },
  );

  test('move to first reorders a parked task without starting it', () async {
    final running = _Task('a', events);
    final userPaused = _Task('b', events);
    final broken = _Task('c', events);
    queue.restorePausedTasks(
      [running, userPaused, broken],
      states: {userPaused: paused, broken: failed},
    );
    queue.resume(running);
    events.clear();
    await queue.moveToFirst(userPaused);
    await queue.moveToFirst(broken);
    await pumpEventQueue();
    expect(queue.tasks, [broken, userPaused, running]);
    expect(states(), [failed, paused, normal]);
    expect(events, ['notify', 'save', 'notify', 'save']);
    expect(running.isPaused, isFalse);
  });

  test('pause all parks every normal task and stops the running one', () async {
    final running = _Task('a', events);
    final waiting = _Task('b', events);
    final broken = _Task('c', events);
    queue.restorePausedTasks(
      [running, waiting, broken],
      states: {broken: failed},
    );
    queue.resume(running);
    events.clear();
    await queue.pauseAll();
    await pumpEventQueue();
    expect(states(), [paused, paused, failed]);
    expect(events, ['pause:a', 'notify', 'save']);
    expect(queue.activeTask, isNull);
  });

  test('resume by intent starts the first normal task through holds', () {
    final head = _Task('a', events);
    queue.restorePausedTasks([head]);
    final release = queue.holdAutomaticStarts();
    queue.resumeByIntent();
    expect(head.isPaused, isTrue);
    release();
    expect(head.isPaused, isFalse);
  });
}

class _Task extends DownloadTask {
  _Task(this.id, this.events, {int type = 17}) : comicType = ComicType(type);
  final List<String> events;
  @override
  final String id;
  @override
  final ComicType comicType;
  Future<void>? cleanup;
  @override
  Future<void> get pendingCleanup => cleanup ?? Future.value();
  bool _paused = true;
  void Function()? onPause;
  void Function()? onCancel;
  void Function(DownloadTask)? onResumeFail;
  int failureRetries = 0;
  @override
  void retryAfterFailure() {
    failureRetries++;
    events.add('retry:$id');
  }

  @override
  bool get isPaused => _paused;
  @override
  bool get isError => false;
  @override
  double get progress => 1;
  @override
  int get speed => 0;
  @override
  String get title => id;
  @override
  String? get cover => null;
  String status = '';
  @override
  String get message => status;
  @override
  void cancel() {
    pause();
    onCancel?.call();
  }

  @override
  void pause() {
    _paused = true;
    events.add('pause:$id');
    onPause?.call();
  }

  @override
  void resume() {
    _paused = false;
    events.add('resume:$id');
    final fail = onResumeFail;
    if (fail != null) {
      _paused = true;
      fail(this);
    }
  }

  @override
  Map<String, dynamic> toJson() => {'id': id};
  @override
  LocalComic toLocalComic() => LocalComic(
    id: id,
    title: id,
    subtitle: '',
    tags: [],
    directory: id,
    chapters: null,
    cover: '',
    comicType: comicType,
    downloadedChapters: [],
    createdAt: DateTime(2026),
  );
}
