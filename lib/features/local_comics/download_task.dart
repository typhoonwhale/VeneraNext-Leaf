import 'package:flutter/foundation.dart' show ChangeNotifier;
import 'package:path/path.dart' as p;
import 'package:venera_next/foundation/file_system.dart';
import 'package:venera_next/foundation/comic_type.dart';
import 'local_comic_model.dart';

abstract class DownloadTask with ChangeNotifier {
  /// 0-1
  double get progress;

  bool get isError;

  bool get isPaused;

  bool get isWaitingToRetry => false;

  /// Native extraction is writing the output and cannot be interrupted, even
  /// after a pause.
  bool get isExtracting => false;

  /// After a cancellation: an output folder kept because nothing proves this
  /// task created it, for example one restored from an older snapshot.
  String? get retainedOutputPath => null;

  /// The paused task's library moved from [from] to [to] with its folders.
  void relocateOutput(String from, String to) {
    final output = path;
    if (output != null && p.equals(p.dirname(output), from)) {
      path = FilePath.join(to, p.basename(output));
    }
  }

  /// A network/foreground hint may wake an existing wait, never resume a task.
  void retryNow() {}

  /// The user resumes this task after a failure parked it; called before the
  /// queue starts it again.
  void retryAfterFailure() {}

  /// bytes per second
  int get speed;

  void cancel();

  void pause();

  /// Work already accepted by pause/cancel, including transfer and file cleanup.
  Future<void> get pendingCleanup;

  void resume();

  String get title;

  String? get cover;

  String get message;

  /// root path for the comic. If null, the task is not scheduled.
  String? path;

  /// convert current state to json, which can be used to restore the task
  Map<String, dynamic> toJson();

  LocalComic toLocalComic();

  String get id;

  ComicType get comicType;

  @override
  bool operator ==(Object other) {
    return other is DownloadTask &&
        other.id == id &&
        other.comicType == comicType;
  }

  @override
  int get hashCode => Object.hash(id, comicType);
}
