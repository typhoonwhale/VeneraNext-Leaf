import 'dart:math' as math;

/// Reasons describe navigation intent, independent of screen reading direction.
enum ReaderPositionCause { user, jump, remap }

class ReaderReadVerdict {
  const ReaderReadVerdict(this.key, this.completed, {this.legacyRawKey});
  final String key;
  final bool completed;
  final String? legacyRawKey;
}

class _ChapterProgress {
  _ChapterProgress(this.count, this.legacyRawKey);
  final int count;
  final String? legacyRawKey;
  final passed = <int>{};
  bool lastShown = false;
  bool pastEnd = false;
  bool completed = false;
  int currentLast = 0;
  int? visibleLast;
  int? visibleFirst;
  bool enteredForward = false;
}

/// Session-only evidence. Persisted read marks are deliberately never revoked.
class ReaderProgressTracker {
  final _chapters = <String, _ChapterProgress>{};
  ({String key, int ordinal, int first, int last})? _last;

  void seedResumed(
    String key,
    int imageCount,
    int savedImage, {
    String? legacyRawKey,
  }) {
    if (savedImage < 1 || savedImage > imageCount) return;
    final state = _state(key, imageCount, legacyRawKey);
    state.passed.addAll(Iterable.generate(savedImage - 1, (i) => i + 1));
  }

  _ChapterProgress _state(String key, int count, String? legacyRawKey) {
    final old = _chapters[key];
    if (old != null && old.count == count) return old;
    if (_last?.key == key) _last = null;
    return _chapters[key] = _ChapterProgress(count, legacyRawKey);
  }

  ReaderReadVerdict _verdict(
    String key,
    _ChapterProgress state, {
    bool evaluate = false,
  }) {
    if (evaluate && state.count > 0) {
      final required = math.max(3, (state.count / 2).ceil());
      state.completed |= state.count <= 3
          ? state.pastEnd && state.passed.length >= state.count - 1
          : state.lastShown && state.passed.length >= required;
    }
    return ReaderReadVerdict(
      key,
      state.completed,
      legacyRawKey: state.legacyRawKey,
    );
  }

  List<ReaderReadVerdict> observe({
    required String key,
    required int ordinal,
    required int imageCount,
    required int firstImage,
    required int lastImage,
    required ReaderPositionCause cause,
    String? legacyRawKey,
    bool countProgress = true,
  }) {
    final state = _state(key, imageCount, legacyRawKey);
    if (cause != ReaderPositionCause.user) state.enteredForward = false;
    if (imageCount <= 0) {
      _last = null;
      return [_verdict(key, state)];
    }
    final first = firstImage.clamp(1, imageCount);
    final last = lastImage.clamp(first, imageCount);
    final previous = _last;
    final results = <ReaderReadVerdict>[];
    bool forward = false;
    if (cause == ReaderPositionCause.user && previous != null) {
      if (ordinal == previous.ordinal + 1) {
        final prior = _chapters[previous.key]!;
        if (prior.count > 0 && prior.currentLast == prior.count) {
          if (prior.visibleFirst != null) {
            if (prior.visibleFirst == 1) _add(prior, 2, prior.visibleLast!);
          } else if (previous.first == 1) {
            _add(prior, 2, previous.last);
          }
          prior.pastEnd = true;
          results.add(_verdict(previous.key, prior, evaluate: true));
        }
        forward = true;
        state.enteredForward = !countProgress;
        if (countProgress) _add(state, 1, last);
      } else if (key == previous.key && first > previous.first) {
        forward = true;
        if (countProgress) {
          if (previous.first == 1) _add(state, 2, previous.last);
          _add(state, previous.last + 1, last);
        }
      }
    }
    if (countProgress) {
      state.currentLast = last;
      state.lastShown |= last == imageCount;
    }
    _last = (key: key, ordinal: ordinal, first: first, last: last);
    results.add(_verdict(key, state, evaluate: forward && countProgress));
    return results;
  }

  /// Visible ranges supplement continuous-mode coordinates without moving them.
  ReaderReadVerdict observeVisible({
    required String key,
    required int imageCount,
    required int firstImage,
    required int lastImage,
    required bool forward,
    String? legacyRawKey,
  }) {
    final state = _state(key, imageCount, legacyRawKey);
    if (imageCount <= 0) return _verdict(key, state);
    final last = lastImage.clamp(1, imageCount);
    final previous = state.visibleLast;
    if (forward && state.visibleFirst == 1 && previous != null) {
      _add(state, 2, previous);
    }
    if (forward && state.enteredForward) {
      _add(state, 1, last);
      state.enteredForward = false;
    } else if (forward && previous != null && last > previous) {
      _add(state, previous + 1, last);
    }
    state.visibleFirst = firstImage;
    state.visibleLast = last;
    state.currentLast = last;
    state.lastShown |= last == imageCount;
    return _verdict(key, state, evaluate: forward);
  }

  ReaderReadVerdict? forwardPastEnd() {
    final previous = _last;
    if (previous == null) return null;
    final state = _chapters[previous.key]!;
    if (state.count <= 0 || state.currentLast != state.count) return null;
    if (state.visibleFirst != null) {
      if (state.visibleFirst == 1) _add(state, 2, state.visibleLast!);
    } else if (previous.first == 1) {
      _add(state, 2, previous.last);
    }
    state.pastEnd = true;
    return _verdict(previous.key, state, evaluate: true);
  }

  void _add(_ChapterProgress state, int first, int last) {
    for (
      var image = math.max(1, first);
      image <= math.min(last, state.count);
      image++
    ) {
      state.passed.add(image);
    }
  }
}
