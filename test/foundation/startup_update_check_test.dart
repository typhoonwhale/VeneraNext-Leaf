import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:venera_next/foundation/startup_update_check.dart';

void main() {
  test(
    'closing waits accepted persistence and starts no later checks',
    () async {
      final reserved = Completer<bool>();
      var sources = 0;
      var applications = 0;
      final check = StartupUpdateCheck(
        reserveSourceCheck: () => reserved.future,
        reserveApplicationCheck: () => reserved.future,
        checkSources: () async {
          sources++;
        },
        checkApplication: (_) async {
          applications++;
        },
        applicationCheckEnabled: () => true,
      );
      final started = check.start();
      expect(identical(started, check.start()), isTrue);
      var closed = false;
      final closing = check.closeAndWait().then((_) => closed = true);
      await pumpEventQueue();
      expect(closed, isFalse);
      reserved.complete(true);
      await Future.wait([started, closing]);
      expect(sources, 0);
      expect(applications, 0);
    },
  );

  test(
    'slow shared source does not block application and keeps its owner',
    () async {
      final sourceEntered = Completer<void>();
      final sourceDone = Completer<void>();
      var versions = 0;
      final check = StartupUpdateCheck(
        reserveSourceCheck: () async => true,
        reserveApplicationCheck: () async => true,
        checkSources: () {
          sourceEntered.complete();
          return sourceDone.future;
        },
        checkApplication: (_) async {
          versions++;
        },
        applicationCheckEnabled: () => true,
      );
      final started = check.start();
      await sourceEntered.future;
      await pumpEventQueue();
      expect(versions, 1);
      await check.closeAndWait();
      expect(sourceDone.isCompleted, isFalse);
      sourceDone.complete();
      await started;
      await pumpEventQueue();
      expect(versions, 1);
    },
  );

  test('application request actually drains after its cancellation', () async {
    final entered = Completer<void>();
    final released = Completer<void>();
    final check = StartupUpdateCheck(
      reserveSourceCheck: () async => true,
      reserveApplicationCheck: () async => true,
      checkSources: () async {},
      checkApplication: (scope) async {
        entered.complete();
        await scope.whenCancelled;
        await released.future;
      },
      applicationCheckEnabled: () => true,
    );
    final started = check.start();
    await entered.future;
    var closed = false;
    final closing = check.closeAndWait().then((_) => closed = true);
    await pumpEventQueue();
    expect(closed, isFalse);
    released.complete();
    await Future.wait([started, closing]);
  });

  test(
    'source reservation and application enablement are independent',
    () async {
      for (final reserved in [false, true]) {
        for (final enabled in [false, true]) {
          final events = <String>[];
          final check = StartupUpdateCheck(
            reserveSourceCheck: () async {
              events.add('reserveSource');
              return reserved;
            },
            reserveApplicationCheck: () async {
              events.add('reserveApplication');
              return true;
            },
            checkSources: () async {
              events.add('sources');
            },
            checkApplication: (_) async {
              events.add('version');
            },
            applicationCheckEnabled: () => enabled,
          );
          await check.start();
          expect(
            events,
            unorderedEquals([
              'reserveSource',
              if (enabled) 'reserveApplication',
              if (reserved) 'sources',
              if (enabled) 'version',
            ]),
          );
          await check.closeAndWait();
        }
      }
    },
  );

  test(
    'persistence failure is reported but close still joins the completed task',
    () async {
      final failure = StateError('save failed');
      final check = StartupUpdateCheck(
        reserveSourceCheck: () async => throw failure,
        reserveApplicationCheck: () async => false,
        checkSources: () async => fail('no source check'),
        checkApplication: (_) async => fail('no version check'),
        applicationCheckEnabled: () => true,
      );
      await expectLater(check.start(), throwsA(same(failure)));
      await check.closeAndWait();
    },
  );
  test(
    'source failure does not block application and close waits its drain',
    () async {
      final entered = Completer<void>();
      final drained = Completer<void>();
      final failure = StateError('source failed');
      final check = StartupUpdateCheck(
        reserveSourceCheck: () async => true,
        reserveApplicationCheck: () async => true,
        checkSources: () async => throw failure,
        checkApplication: (scope) async {
          entered.complete();
          await scope.whenCancelled;
          await drained.future;
        },
        applicationCheckEnabled: () => true,
      );
      final result = expectLater(check.start(), throwsA(same(failure)));
      await entered.future;
      var closed = false;
      final closing = check.closeAndWait().then((_) => closed = true);
      await pumpEventQueue();
      expect(closed, isFalse);
      drained.complete();
      await Future.wait([result, closing]);
    },
  );
}
