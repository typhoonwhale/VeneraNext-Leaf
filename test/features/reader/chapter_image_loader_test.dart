import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:venera_next/features/reader/chapter_image_loader.dart';
import 'package:venera_next/foundation/image_work.dart';
import 'package:venera_next/foundation/operation_failure.dart';
import 'package:venera_next/features/reader/reader_controller.dart';
import 'package:venera_next/features/reader/waterfall_controller.dart';
import 'package:venera_next/features/reader/waterfall_flow.dart';
import 'package:venera_next/network/request_scope.dart';

void main() {
  final emptyChapter = OperationFailure.message('empty chapter');
  ChapterImageLoader loader({
    Future<List<String>> Function()? local,
    Future<List<String>> Function()? online,
    void Function(FileSystemException, StackTrace)? failure,
  }) => ChapterImageLoader(
    readLocal: local,
    loadOnline: online,
    localPath: '/book',
    onLocalFailure: failure ?? (_, _) {},
    localUnavailable: (path) => FileSystemException('repair', path),
    sourceUnavailable: StateError('source unavailable'),
    emptyChapter: emptyChapter,
  );

  test('empty online chapters fail and never report local recovery', () async {
    for (final localState in ['none', 'empty', 'missing']) {
      var recovered = 0;
      var images = <String>[];
      final service = loader(
        local: localState == 'none'
            ? null
            : () async {
                if (localState == 'missing') {
                  throw const FileSystemException('missing', '/book');
                }
                return [];
              },
        online: () async => images,
      );
      await expectLater(
        service.load(onOnlineFallback: () => recovered++),
        throwsA(same(emptyChapter)),
      );
      expect(recovered, 0);
      images = ['retried'];
      expect(await service.load(onOnlineFallback: () => recovered++), images);
      expect(recovered, localState == 'none' ? 0 : 1);
    }
  });

  test('cancelled empty online result remains cancellation', () async {
    final pending = Completer<List<String>>();
    final owner = RequestScope();
    final result = loader(online: () => pending.future).load(scope: owner);
    final checked = expectLater(result, throwsA(isA<RequestCancelled>()));
    owner.cancel();
    pending.complete([]);
    await checked;
    owner.dispose();
  });

  for (final oldImages in [
    <String>[],
    ['late page'],
  ]) {
    test(
      'retired online result cannot affect a reopened reader: $oldImages',
      () async {
        ReaderController controller() => ReaderController(
          pageCount: () => 1,
          chapterCount: () => 1,
          animationEnabled: () => false,
          viewport: () => null,
          onChanged: () {},
          onPageChanged: () {},
          onError: (error, stack) => fail('$error'),
        );
        final old = controller();
        final current = controller();
        final pending = Completer<List<String>>();
        final started = Completer<void>();
        final work = ImageWork();
        final loading = old.loadContent(
          old.beginContentLoad(),
          imageWork: work,
          beforeLoad: () async {},
          loadImages: (scope) => loader(
            online: () {
              started.complete();
              return pending.future;
            },
          ).load(scope: scope),
          prepareMode: () async => fail('retired content must not prepare'),
        );
        await started.future;
        old.dispose();
        expect(
          await current.loadContent(
            current.beginContentLoad(),
            beforeLoad: () async {},
            loadImages: (scope) =>
                loader(online: () async => ['current']).load(scope: scope),
            prepareMode: () async {},
          ),
          ReaderContentLoadResult.ready,
        );
        pending.complete(oldImages);
        expect(await loading, ReaderContentLoadResult.ignored);
        expect(current.content.images, ['current']);
        expect(current.content.error, isNull);
        expect(old.content.images, isNull);
        (await work.prepareForExit())();
        await work.dispose();
        current.dispose();
      },
    );
  }

  test(
    'empty waterfall chapter preserves content until explicit retry',
    () async {
      var images = <String>[];
      var calls = 0;
      final work = ImageWork();
      final controller =
          WaterfallController(
            maxChapter: 2,
            imageWork: work,
            load: (_, scope) => loader(
              online: () async {
                calls++;
                return images;
              },
            ).load(scope: scope),
            chapterId: (chapter) => '$chapter',
            onChanged: () {},
            onPreviousError: (_, _) => fail('unexpected previous error'),
          )..initialize(
            WaterfallChapterSegment(chapter: 1, eid: '1', images: ['first']),
          );
      await controller.ensureAfter(current: 1, threshold: 1);
      await controller.ensureAfter(current: 1, threshold: 1);
      expect(calls, 1);
      expect(controller.afterError, emptyChapter.toString());
      expect(controller.flow.lastChapter, 1);
      expect(controller.flow.imageRefAt(1)!.imageKey, 'first');
      images = ['second'];
      controller.retryAfter();
      await controller.ensureAfter(current: 1, threshold: 1);
      expect(calls, 2);
      expect(controller.afterError, isNull);
      expect(controller.flow.lastChapter, 2);
      expect(controller.flow.imageRefAt(1)!.imageKey, 'first');
      await controller.dispose();
      await work.dispose();
    },
  );

  test(
    'local success avoids online access and keeps original image order',
    () async {
      var onlineCalls = 0;
      final service = loader(
        local: () async => ['2.jpg', '1.jpg'],
        online: () async {
          onlineCalls++;
          return ['remote'];
        },
      );
      expect(await service.load(), ['2.jpg', '1.jpg']);
      expect(onlineCalls, 0);
    },
  );

  test(
    'missing and empty local files notify recovery only after online success',
    () async {
      for (final empty in [true, false]) {
        var failures = 0;
        var recovered = 0;
        final service = loader(
          local: () async {
            if (empty) return [];
            throw const FileSystemException('missing', '/gone');
          },
          online: () async => ['online.jpg'],
          failure: (_, _) => failures++,
        );
        expect(await service.load(onOnlineFallback: () => recovered++), [
          'online.jpg',
        ]);
        expect(failures, 1);
        expect(recovered, 1);
      }
    },
  );

  test('unavailable storage and source expose distinct errors', () async {
    await expectLater(
      loader(local: () async => []).load(),
      throwsA(
        isA<FileSystemException>().having((e) => e.path, 'path', '/book'),
      ),
    );
    await expectLater(loader().load(), throwsStateError);
    var recovered = false;
    await expectLater(
      loader(
        local: () async => [],
        online: () async => throw StateError('offline'),
      ).load(onOnlineFallback: () => recovered = true),
      throwsStateError,
    );
    expect(recovered, false);
  });

  test(
    'non-filesystem failures do not silently trigger online fallback',
    () async {
      var called = false;
      await expectLater(
        loader(
          local: () async => throw StateError('database'),
          online: () async {
            called = true;
            return [];
          },
        ).load(),
        throwsStateError,
      );
      expect(called, false);
    },
  );

  test(
    'cancelled local read cannot log, recover or start online work',
    () async {
      final pending = Completer<List<String>>();
      final owner = RequestScope();
      var effects = 0;
      final service = loader(
        local: () => pending.future,
        online: () async {
          effects++;
          return [];
        },
        failure: (_, _) => effects++,
      );
      final failure = const FileSystemException('late missing');
      var settled = false;
      final expectation = expectLater(
        service.load(scope: owner, onOnlineFallback: () => effects++),
        throwsA(same(failure)),
      ).then((_) => settled = true);
      owner.cancel();
      await pumpEventQueue();
      expect(settled, false);
      pending.completeError(failure);
      await expectation;
      expect(effects, 0);
      owner.dispose();
    },
  );

  test(
    'cancelled local success waits for the read and skips fallback',
    () async {
      final pending = Completer<List<String>>();
      final owner = RequestScope();
      late RequestScope child;
      var settled = false;
      var effects = 0;
      final service = loader(
        local: () {
          child = RequestScope.current!;
          return pending.future;
        },
        online: () async {
          effects++;
          return ['remote'];
        },
        failure: (_, _) => effects++,
      );
      final expected = expectLater(
        service.load(scope: owner, onOnlineFallback: () => effects++),
        throwsA(isA<RequestCancelled>()),
      ).then((_) => settled = true);
      owner.cancel();
      await pumpEventQueue();
      expect(child.cancelToken.isCancelled, true);
      expect(settled, false);
      pending.complete(['local']);
      await expected;
      expect(effects, 0);
      owner.dispose();
    },
  );

  test(
    'cancelled online failure retains identity and stack after fallback',
    () async {
      final pending = Completer<List<String>>();
      final onlineStarted = Completer<RequestScope>();
      final owner = RequestScope();
      final failure = StateError('late online error');
      final stack = StackTrace.fromString('original online stack');
      var recovered = false;
      final result = loader(
        local: () async => [],
        online: () {
          onlineStarted.complete(RequestScope.current!);
          return pending.future;
        },
      ).load(scope: owner, onOnlineFallback: () => recovered = true);
      final checked = result.then<void>(
        (_) => fail('unexpected success'),
        onError: (Object error, StackTrace actualStack) {
          expect(error, same(failure));
          expect(actualStack, same(stack));
        },
      );
      final child = await onlineStarted.future;
      owner.cancel();
      expect(child.cancelToken.isCancelled, true);
      pending.completeError(failure, stack);
      await checked;
      expect(recovered, false);
      owner.dispose();
    },
  );

  for (final failRead in [false, true]) {
    test(
      'waterfall exit joins the original local read; failure=$failRead',
      () async {
        final work = ImageWork();
        final pending = Completer<List<String>>();
        final failure = const FileSystemException('late local read failure');
        final controller =
            WaterfallController(
              maxChapter: 2,
              imageWork: work,
              load: (_, scope) =>
                  loader(local: () => pending.future).load(scope: scope),
              chapterId: (chapter) => '$chapter',
              onChanged: () {},
              onPreviousError: (_, _) => fail('unexpected UI error'),
            )..initialize(
              WaterfallChapterSegment(chapter: 1, eid: '1', images: ['first']),
            );
        final loading = controller.ensureAfter(current: 1, threshold: 1);
        var prepared = false;
        final preparation = work.prepareForExit();
        final checked = failRead
            ? expectLater(
                preparation,
                throwsA(
                  isA<ImageWorkFailure>().having(
                    (error) => error.failures.map((entry) => entry.error),
                    'original local error',
                    [failure],
                  ),
                ),
              ).then((_) => prepared = true)
            : preparation.then((release) {
                prepared = true;
                release();
              });
        await loading;
        await pumpEventQueue();
        expect(prepared, false);
        if (failRead) {
          pending.completeError(failure);
        } else {
          pending.complete(['late local page']);
        }
        await checked;
        expect(controller.flow.lastChapter, 1);
        expect(controller.afterError, isNull);
        await controller.dispose();
      },
    );
  }
}
