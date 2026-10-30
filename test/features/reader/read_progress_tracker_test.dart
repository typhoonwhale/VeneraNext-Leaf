import 'package:flutter_test/flutter_test.dart';
import 'package:venera_next/features/reader/read_progress_tracker.dart';

void main() {
  late ReaderProgressTracker tracker;
  setUp(() => tracker = ReaderProgressTracker());
  List<ReaderReadVerdict> at(
    int image, {
    int count = 20,
    int chapter = 1,
    int? last,
    ReaderPositionCause cause = ReaderPositionCause.user,
    bool countProgress = true,
  }) => tracker.observe(
    key: '$chapter',
    ordinal: chapter,
    imageCount: count,
    firstImage: image,
    lastImage: last ?? image,
    cause: cause,
    countProgress: countProgress,
    legacyRawKey: '$chapter',
  );

  test('opening and jumping do not complete, forward half plus tail does', () {
    expect(at(1).single.completed, isFalse);
    expect(at(20, cause: ReaderPositionCause.jump).single.completed, isFalse);
    at(1, cause: ReaderPositionCause.jump);
    for (var i = 2; i < 20; i++) {
      at(i);
    }
    expect(at(20).single.completed, isTrue);
  });
  test(
    'enough pages followed by a jump to the tail still needs forward action',
    () {
      at(1);
      at(11);
      expect(at(20, cause: ReaderPositionCause.jump).single.completed, isFalse);
      expect(tracker.forwardPastEnd()!.completed, isTrue);
    },
  );
  test('resume compensation accepts the deliberately coarse saved cursor', () {
    tracker.seedResumed('1', 40, 25);
    at(25, count: 40);
    expect(at(40, count: 40).single.completed, isTrue);
  });
  test(
    'without compensation a short final session cannot finish a long chapter',
    () {
      at(25, count: 40);
      expect(at(40, count: 40).single.completed, isFalse);
    },
  );
  test(
    'backwards entry then forward crossing returns both chapter verdicts',
    () {
      at(1, count: 1, chapter: 2);
      at(1, count: 1);
      final results = at(1, count: 20, chapter: 2);
      expect(results.map((v) => (v.key, v.completed)), [
        ('1', true),
        ('2', false),
      ]);
    },
  );
  test('backwards entry into a long tail cannot complete by crossing out', () {
    at(1, chapter: 2);
    at(20);
    expect(at(1, chapter: 2).first.completed, isFalse);
  });
  test('a chapter jump does not complete the preceding short chapter', () {
    at(1, count: 1);
    expect(at(1, chapter: 2, cause: ReaderPositionCause.jump), hasLength(1));
  });
  test('short chapters need forward past end, with a full initial spread', () {
    for (final n in [1, 2, 3]) {
      tracker = ReaderProgressTracker();
      expect(at(1, count: n, last: n).single.completed, isFalse);
      expect(tracker.forwardPastEnd()!.completed, isTrue);
    }
  });
  test(
    'short tail restored or jumped to does not imply its preceding images',
    () {
      at(3, count: 3);
      expect(tracker.forwardPastEnd()!.completed, isFalse);
      tracker = ReaderProgressTracker();
      at(1, count: 3, last: 2);
      at(3, count: 3, cause: ReaderPositionCause.jump);
      expect(tracker.forwardPastEnd()!.completed, isFalse);
    },
  );
  test('a backwards tail entry can restart at a complete double spread', () {
    at(1, chapter: 2);
    at(3, count: 3);
    at(1, count: 3, last: 2);
    expect(at(3, count: 3).single.completed, isFalse);
    expect(tracker.forwardPastEnd()!.completed, isTrue);
  });

  test('continuous coordinates alone do not prove a decoded last image', () {
    at(1, count: 1, countProgress: false);
    expect(tracker.forwardPastEnd(), isNull);
  });

  test('three single images need two forward images and a past-end action', () {
    at(1, count: 3);
    at(2, count: 3);
    expect(at(3, count: 3).single.completed, isFalse);
    expect(tracker.forwardPastEnd()!.completed, isTrue);
  });
  test(
    'four image chapter with two spreads satisfies the three image floor',
    () {
      at(1, count: 4, last: 2);
      expect(at(3, count: 4, last: 4).single.completed, isTrue);
    },
  );

  test(
    'jumping away from the first spread does not earn its forward credit',
    () {
      at(1, count: 6, last: 3);
      at(4, count: 6, cause: ReaderPositionCause.jump);
      expect(at(5, count: 6, last: 6).single.completed, isFalse);
    },
  );

  test('first decoded continuous range does not invent an unread prefix', () {
    at(15, countProgress: false);
    expect(
      tracker
          .observeVisible(
            key: '1',
            imageCount: 20,
            firstImage: 15,
            lastImage: 20,
            forward: true,
          )
          .completed,
      isFalse,
    );
    expect(tracker.forwardPastEnd()!.completed, isFalse);
  });

  test('double page evidence counts source images, not display pages', () {
    at(1, last: 2);
    for (var i = 3; i < 19; i += 2) {
      at(i, last: i + 1);
    }
    expect(at(19, last: 20).single.completed, isTrue);
  });
  test('remapping never accumulates images or completes by itself', () {
    at(1);
    at(15, cause: ReaderPositionCause.remap);
    expect(at(20).single.completed, isFalse);
  });
  test('changed and empty content cannot reuse old navigation range', () {
    at(1);
    at(11);
    expect(at(4, count: 4).single.completed, isFalse);
    expect(at(1, count: 0).single.completed, isFalse);
    expect(tracker.forwardPastEnd(), isNull);
  });
  test('back and forth deduplicates passed images', () {
    at(1);
    for (var i = 0; i < 10; i++) {
      at(5);
      at(1);
    }
    expect(at(20, cause: ReaderPositionCause.jump).single.completed, isFalse);
  });
  test('visible short tail can finish while active image is unchanged', () {
    at(1, count: 6, countProgress: false);
    tracker.observeVisible(
      key: '1',
      imageCount: 6,
      firstImage: 1,
      lastImage: 2,
      forward: false,
    );
    tracker.observeVisible(
      key: '1',
      imageCount: 6,
      firstImage: 2,
      lastImage: 5,
      forward: true,
    );
    final result = tracker.observeVisible(
      key: '1',
      imageCount: 6,
      firstImage: 5,
      lastImage: 6,
      forward: true,
    );
    expect(result.completed, isTrue);
  });
  test('geometry-only visibility cannot turn a jump into forward reading', () {
    at(1, countProgress: false);
    tracker.observeVisible(
      key: '1',
      imageCount: 20,
      firstImage: 1,
      lastImage: 2,
      forward: false,
    );
    expect(
      tracker
          .observeVisible(
            key: '1',
            imageCount: 20,
            firstImage: 15,
            lastImage: 20,
            forward: false,
          )
          .completed,
      isFalse,
    );
  });
}
