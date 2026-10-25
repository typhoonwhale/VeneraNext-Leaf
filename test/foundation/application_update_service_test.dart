import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:venera_next/foundation/application_update_service.dart';
import 'package:venera_next/foundation/operation_failure.dart';
import 'package:venera_next/network/app_dio.dart';
import 'package:venera_next/network/request_scope.dart';

import '../support/application_update_adapter.dart';

void main() {
  test(
    'Android update checks stay disabled without an owned release channel',
    () async {
      var createdClient = false;
      final service = ApplicationUpdateService(
        createClient: () {
          createdClient = true;
          throw StateError('disabled update checks must not create a client');
        },
        currentVersion: () => '1.0.0',
        releaseRepository: null,
      );

      expect(service.isEnabled, isFalse);
      expect(service.releasePageUrl, isNull);
      expect(await service.check(), isNull);
      expect(createdClient, isFalse);
      await service.closeAndWait();
    },
  );

  test(
    'configured update channel queries its own GitHub release endpoint',
    () async {
      final adapter = ApplicationUpdateAdapter()..released.complete();
      final service = ApplicationUpdateService(
        createClient: () => Dio()..httpClientAdapter = adapter,
        currentVersion: () => '1.0.0',
        releaseRepository: 'typhoonwhale/VeneraNext-Leaf',
      );

      expect(
        service.releasePageUrl,
        'https://github.com/typhoonwhale/VeneraNext-Leaf/releases',
      );
      final result = service.check();
      await adapter.entered.future;
      expect(
        Uri.parse(adapter.paths.single).path,
        '/repos/typhoonwhale/VeneraNext-Leaf/releases/latest',
      );
      adapter.complete({'tag_name': 'v1.0.1'});
      expect(await result, '1.0.1');
      await service.closeAndWait();
    },
  );

  test(
    'a 404 latest with an empty Leaf release list means no update',
    () async {
      final adapter = _EmptyLeafReleaseAdapter()..released.complete();
      final service = ApplicationUpdateService(
        createClient: () => Dio()..httpClientAdapter = adapter,
        currentVersion: () => '1.0.0',
        releaseRepository: 'typhoonwhale/VeneraNext-Leaf',
      );

      final result = service.check();
      await adapter.releasesEntered.future;
      expect(adapter.paths.map((uri) => Uri.parse(uri).path), [
        '/repos/typhoonwhale/VeneraNext-Leaf/releases/latest',
        '/repos/typhoonwhale/VeneraNext-Leaf/releases',
      ]);
      adapter.complete([]);
      expect(await result, isNull);
      await service.closeAndWait();
    },
  );

  test('a 404 from the Leaf releases list remains a failure', () async {
    final adapter = _EmptyLeafReleaseAdapter()..released.complete();
    final service = ApplicationUpdateService(
      createClient: () => Dio()..httpClientAdapter = adapter,
      currentVersion: () => '1.0.0',
      releaseRepository: 'typhoonwhale/VeneraNext-Leaf',
    );
    final checked = expectLater(
      service.check(),
      throwsA(isA<OperationFailure>()),
    );

    await adapter.releasesEntered.future;
    adapter.complete({'message': 'Not Found'}, status: 404);
    await checked;
    await service.closeAndWait();
  });

  for (final status in [403, 429]) {
    test('Leaf update check preserves HTTP $status failures', () async {
      final adapter = ApplicationUpdateAdapter()..released.complete();
      final service = ApplicationUpdateService(
        createClient: () => Dio()..httpClientAdapter = adapter,
        currentVersion: () => '1.0.0',
        releaseRepository: 'typhoonwhale/VeneraNext-Leaf',
      );
      final checked = expectLater(
        service.check(),
        throwsA(isA<OperationFailure>()),
      );

      await adapter.entered.future;
      adapter.complete({'message': 'HTTP $status'}, status: status);
      await checked;
      await service.closeAndWait();
    });
  }

  test(
    'stable and preview requests preserve channel selection and wait for cleanup',
    () async {
      for (final current in ['1.10.0', '1.11.0-rc.1']) {
        final adapter = ApplicationUpdateAdapter();
        final service = ApplicationUpdateService(
          createClient: () => Dio()..httpClientAdapter = adapter,
          currentVersion: () => current,
        );
        var finished = false;
        final result = service.check().whenComplete(() => finished = true);
        await adapter.entered.future;
        expect(
          Uri.parse(adapter.paths.single).path.endsWith(
            current == '1.10.0' ? '/releases/latest' : '/releases',
          ),
          isTrue,
        );
        adapter.complete([
          {'tag_name': 'v1.12.0', 'draft': true},
          {'tag_name': 'v1.11.0-rc.2', 'prerelease': true},
          {'tag_name': 'v1.10.1'},
        ]);
        await adapter.draining.future;
        expect(finished, isFalse);
        adapter.released.complete();
        expect(await result, current == '1.10.0' ? '1.10.1' : '1.11.0-rc.2');
        await service.closeAndWait();
        expect(adapter.closes, 1);
      }
    },
  );

  test(
    'one consumer cancels without cancelling siblings or losing retired cleanup',
    () async {
      final adapters = <ApplicationUpdateAdapter>[];
      final service = ApplicationUpdateService(
        createClient: () {
          final adapter = ApplicationUpdateAdapter();
          adapters.add(adapter);
          return Dio()..httpClientAdapter = adapter;
        },
        currentVersion: () => '1.0.0',
      );
      final parent = RequestScope();
      final firstScope = RequestScope(parent: parent);
      final first = expectLater(
        service.check(scope: firstScope),
        throwsA(isA<RequestCancelled>()),
      );
      final second = expectLater(
        service.check(scope: parent),
        throwsA(isA<RequestCancelled>()),
      );
      await pumpEventQueue();
      firstScope.cancel();
      await adapters.first.draining.future;
      expect(parent.isCancelled, isFalse);
      expect(adapters.last.draining.isCompleted, isFalse);
      var finished = false;
      final close = service.closeAndWait();
      expect(identical(close, service.closeAndWait()), isTrue);
      final closing = close.then((_) => finished = true);
      await adapters.last.draining.future;
      adapters.last.released.complete();
      await pumpEventQueue();
      expect(finished, isFalse);
      adapters.first.released.complete();
      await Future.wait([first, second, closing]);
      await expectLater(service.check(), throwsStateError);
      expect(parent.isCancelled, isFalse);
      firstScope.dispose();
      parent.dispose();
    },
  );

  test(
    'cancellation during successful response cleanup cannot publish an update',
    () async {
      final adapter = ApplicationUpdateAdapter();
      final service = ApplicationUpdateService(
        createClient: () => Dio()..httpClientAdapter = adapter,
        currentVersion: () => '1.0.0',
      );
      final checked = expectLater(
        service.check(),
        throwsA(isA<RequestCancelled>()),
      );
      await adapter.entered.future;
      adapter.complete({'tag_name': 'v2.0.0'});
      await adapter.draining.future;
      final closing = service.closeAndWait();
      adapter.released.complete();
      await Future.wait([checked, closing]);
    },
  );

  for (final invalid in <Object>[
    'not a release document',
    {'message': 'upstream error'},
    [
      {'tag_name': ''},
    ],
    [null],
  ]) {
    test(
      'malformed metadata remains a failure rather than no update: $invalid',
      () async {
        final adapter = ApplicationUpdateAdapter()..released.complete();
        final service = ApplicationUpdateService(
          createClient: () => Dio()..httpClientAdapter = adapter,
          currentVersion: () => '1.0.0',
        );
        final checked = expectLater(
          service.check(),
          throwsA(
            isA<OperationFailure>().having(
              (failure) => failure.cause,
              'cause',
              isA<FormatException>(),
            ),
          ),
        );
        await adapter.entered.future;
        adapter.complete(invalid);
        await checked;
        await service.closeAndWait();
        expect(adapter.closes, 1);
      },
    );
  }

  test(
    'operation and both close failures stay inspectable after repeated close',
    () async {
      final operationError = StateError('HTTP failed');
      final closeError = StateError('adapter close');
      final idleError = StateError('native idle');
      final adapter = ApplicationUpdateAdapter()..closeError = closeError;
      final service = ApplicationUpdateService(
        createClient: () => Dio()..httpClientAdapter = adapter,
        currentVersion: () => '1.0.0',
      );
      final checked = expectLater(
        service.check(),
        throwsA(
          isA<ApplicationUpdateCleanupFailure>()
              .having(
                (e) => (e.cause as DioException).error,
                'operation',
                same(operationError),
              )
              .having((e) => e.stackTrace, 'original stack', isNotNull)
              .having((e) => e.failures.map((f) => f.error), 'cleanup', [
                closeError,
                idleError,
              ]),
        ),
      );
      await adapter.entered.future;
      adapter.response.completeError(operationError);
      await adapter.draining.future;
      adapter.released.completeError(idleError);
      await checked;
      final closing = service.closeAndWait();
      await expectLater(
        closing,
        throwsA(isA<ApplicationUpdateCleanupFailure>()),
      );
      expect(identical(closing, service.closeAndWait()), isTrue);
      expect(adapter.closes, 1);
    },
  );

  test(
    'synchronous client factory reentry closes its registered request',
    () async {
      late ApplicationUpdateService service;
      late Future<void> closing;
      final adapter = ApplicationUpdateAdapter();
      service = ApplicationUpdateService(
        createClient: () {
          closing = service.closeAndWait();
          return Dio()..httpClientAdapter = adapter;
        },
        currentVersion: () => '1.0.0',
      );
      final checked = expectLater(
        service.check(),
        throwsA(isA<RequestCancelled>()),
      );
      await adapter.draining.future;
      expect(adapter.entered.isCompleted, isFalse);
      adapter.released.complete();
      await Future.wait([checked, closing]);
    },
  );
}

class _EmptyLeafReleaseAdapter extends ApplicationUpdateAdapter {
  final releasesEntered = Completer<void>();

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) {
    if (options.path.endsWith('/latest')) {
      paths.add(options.path);
      if (!entered.isCompleted) entered.complete();
      return Future.value(
        ResponseBody.fromString(
          '{"message":"Not Found"}',
          404,
          headers: {
            Headers.contentTypeHeader: ['application/json'],
          },
        ),
      );
    }
    releasesEntered.complete();
    return super.fetch(options, requestStream, cancelFuture);
  }
}
