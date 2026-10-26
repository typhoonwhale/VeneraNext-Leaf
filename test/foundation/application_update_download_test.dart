import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:venera_next/foundation/application_update_download.dart';
import 'package:venera_next/foundation/application_update_installer.dart';
import 'package:venera_next/foundation/application_update_release.dart';

class FakeInstaller implements ApplicationUpdateInstaller {
  int installedCode = 1;
  bool debug = false;
  bool installationPending = false;
  bool permitted = true;
  Completer<void>? permission;
  String status = 'unknown';
  String? message;
  Object? installError;
  final attempts = <String>[];
  Completer<ApplicationUpdateInstallationResult>? installation;
  @override
  Future<ApplicationUpdateIdentity> current() async =>
      ApplicationUpdateIdentity(
        versionCode: installedCode,
        versionName: '1.0.0',
        debug: debug,
        installationPending: installationPending,
      );
  @override
  Future<ApplicationUpdateInspection> inspect({required bool partial}) async =>
      ApplicationUpdateInspection(
        versionCode: 2,
        versionName: '2.0.0',
        installedVersionCode: installedCode,
      );
  @override
  Future<bool> canInstall() async => permitted;
  @override
  Future<bool> requestPermission() async {
    await permission?.future;
    return permitted;
  }

  @override
  Future<ApplicationUpdateInstallationResult> install({
    required String version,
    required String attemptId,
  }) async {
    attempts.add(attemptId);
    if (installError != null) throw installError!;
    if (status == 'installed') installedCode = 2;
    return installation == null
        ? ApplicationUpdateInstallationResult(attemptId, status, message)
        : installation!.future;
  }

  @override
  Future<ApplicationUpdateInstallationResult> installationStatus({
    required String attemptId,
  }) async => ApplicationUpdateInstallationResult(attemptId, status);
}

class BytesAdapter implements HttpClientAdapter {
  BytesAdapter(this.stream, {this.status = 200, this.headers = const {}});
  final Stream<Uint8List> Function() stream;
  final int status;
  final Map<String, List<String>> headers;
  int calls = 0;
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    calls++;
    expect(
      options.headers.keys.map((key) => key.toLowerCase()),
      isNot(contains('range')),
    );
    return ResponseBody(stream(), status, headers: headers);
  }

  @override
  void close({bool force = false}) {}
}

class StalledHeaderAdapter extends BytesAdapter {
  StalledHeaderAdapter() : super(() => const Stream.empty());
  bool cancelled = false;
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    await cancelFuture;
    cancelled = true;
    throw DioException(requestOptions: options, type: DioExceptionType.cancel);
  }
}

class HookDirectory implements Directory {
  HookDirectory(this.real);
  final Directory real;
  void Function()? onCreate;
  @override
  String get path => real.path;
  @override
  Future<Directory> create({bool recursive = false}) async {
    final result = await real.create(recursive: recursive);
    onCreate?.call();
    return result;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late Directory root;
  late FakeInstaller native;
  late ApplicationUpdateDownload controller;
  late Set<int> queueHolds;
  var holdCount = 0;
  final bytes = utf8.encode('fixture APK bytes');
  ApplicationUpdateRelease release() => ApplicationUpdateRelease(
    version: '2.0.0',
    notes: 'fixture',
    pageUrl: 'https://github.com/example/leaf/releases/tag/v2.0.0',
    asset: ApplicationUpdateAsset(
      name: 'Leaf-2.0.0-2-release-arm64-v8a.apk',
      url: Uri.parse(
        'https://github.com/example/leaf/releases/download/v2.0.0/Leaf-2.0.0-2-release-arm64-v8a.apk',
      ),
      size: bytes.length,
      sha256: sha256.convert(bytes).toString(),
    ),
  );
  ApplicationUpdateDownload make(BytesAdapter adapter) =>
      ApplicationUpdateDownload(
        cacheRoot: root.path,
        repository: 'example/leaf',
        installer: native,
        networkTimeout: const Duration(milliseconds: 100),
        dioFactory: () => Dio()..httpClientAdapter = adapter,
        holdDownloadQueue: () {
          final hold = ++holdCount;
          queueHolds.add(hold);
          return () => queueHolds.remove(hold);
        },
      );
  File file(String name) => File('${root.path}/updates/$name');
  setUp(() async {
    root = await Directory.systemTemp.createTemp('leaf-updates-test-');
    native = FakeInstaller();
    queueHolds = {};
    holdCount = 0;
  });
  tearDown(() async {
    await controller.closeAndWait();
    await root.delete(recursive: true);
  });

  test(
    'streams bytes, verifies, renames and clears only dedicated directory',
    () async {
      final sentinel = File('${root.path}/sentinel');
      await sentinel.writeAsString('keep');
      controller = make(
        BytesAdapter(() => Stream.value(Uint8List.fromList(bytes))),
      );
      await controller.download(release());
      expect(controller.state, ApplicationUpdateDownloadState.ready);
      expect(await file('update.apk').readAsBytes(), bytes);
      expect(await file('update.apk.part').exists(), false);
      await controller.cancelAndClear();
      expect(await file('update.apk').exists(), false);
      expect(await sentinel.readAsString(), 'keep');
    },
  );

  test('oversized and corrupted streams cannot become ready', () async {
    controller = make(
      BytesAdapter(() => Stream.value(Uint8List.fromList([...bytes, 1]))),
    );
    await controller.download(release());
    expect(controller.state, ApplicationUpdateDownloadState.failed);
    expect(await file('update.apk.part').exists(), false);
    expect(await file('update.apk').exists(), false);
  });

  test(
    'cancellation joins an active response and removes partial bytes',
    () async {
      final chunks = StreamController<Uint8List>();
      final adapter = BytesAdapter(() => chunks.stream);
      controller = make(adapter);
      final active = controller.download(release());
      while (adapter.calls == 0) {
        await Future<void>.delayed(Duration.zero);
      }
      chunks.add(Uint8List.fromList(bytes.sublist(0, 3)));
      while (controller.received == 0) {
        await Future<void>.delayed(Duration.zero);
      }
      await controller.cancelAndClear().timeout(const Duration(seconds: 2));
      await active;
      await chunks.close();
      expect(controller.state, ApplicationUpdateDownloadState.idle);
      expect(await file('update.apk.part').exists(), false);
    },
  );

  test('stalled response headers time out and cancel the transport', () async {
    final adapter = StalledHeaderAdapter();
    controller = make(adapter);
    await controller.download(release()).timeout(const Duration(seconds: 2));
    expect(controller.state, ApplicationUpdateDownloadState.failed);
    expect(adapter.cancelled, true);
    expect(await file('update.apk.part').exists(), false);
  });

  test(
    'stalled body times out and removes partial after cancelling stream',
    () async {
      final chunks = StreamController<Uint8List>();
      controller = make(BytesAdapter(() => chunks.stream));
      final active = controller.download(release());
      chunks.add(Uint8List.fromList(bytes.sublist(0, 3)));
      await active.timeout(const Duration(seconds: 2));
      expect(controller.state, ApplicationUpdateDownloadState.failed);
      expect(await file('update.apk.part').exists(), false);
      await chunks.close();
    },
  );

  test(
    'cancellation during filesystem preparation prevents token creation and network',
    () async {
      final hooked = HookDirectory(Directory('${root.path}/updates'));
      final adapter = BytesAdapter(
        () => Stream.value(Uint8List.fromList(bytes)),
      );
      IOOverrides.runZoned(() {
        controller = make(adapter);
      }, createDirectory: (_) => hooked);
      await controller.initialize();
      Future<void>? cancellation;
      hooked.onCreate = () {
        hooked.onCreate = null;
        cancellation = controller.cancelAndClear();
      };
      await controller.download(release());
      await cancellation;
      expect(adapter.calls, 0);
      expect(controller.state, ApplicationUpdateDownloadState.idle);
      expect(await file('update.apk.part').exists(), false);
    },
  );

  test('digest mismatch removes the complete but invalid response', () async {
    controller = make(
      BytesAdapter(() => Stream.value(Uint8List(bytes.length))),
    );
    await controller.download(release());
    expect(controller.state, ApplicationUpdateDownloadState.failed);
    expect(await file('update.apk.part').exists(), false);
    expect(await file('update.apk').exists(), false);
  });

  test('HTTP failure remains failure and leaves no partial', () async {
    controller = make(BytesAdapter(() => const Stream.empty(), status: 404));
    await controller.download(release());
    expect(controller.state, ApplicationUpdateDownloadState.failed);
    expect(await file('update.apk.part').exists(), false);
  });

  test(
    'duplicate clicks and early cancellation never create a second request',
    () async {
      final adapter = BytesAdapter(
        () => Stream.value(Uint8List.fromList(bytes)),
      );
      controller = make(adapter);
      final first = controller.download(release());
      final second = controller.download(release());
      await controller.cancelAndClear();
      await Future.wait([first, second]);
      expect(adapter.calls, lessThanOrEqualTo(1));
      expect(controller.state, ApplicationUpdateDownloadState.idle);
      expect(await file('update.apk.part').exists(), false);
    },
  );

  test(
    'startup removes partial and discards unverifiable orphan without a session',
    () async {
      await file('update.apk').parent.create(recursive: true);
      await file('update.apk').writeAsString('orphan');
      await file('update.apk.part').writeAsString('partial');
      final adapter = BytesAdapter(
        () => Stream.value(Uint8List.fromList(bytes)),
      );
      controller = make(adapter);
      await controller.initialize();
      expect(controller.state, ApplicationUpdateDownloadState.idle);
      expect(await file('update.apk').exists(), false);
      expect(await file('update.apk.part').exists(), false);
      await controller.download(release());
      expect(controller.state, ApplicationUpdateDownloadState.ready);
      expect(await file('update.apk').readAsBytes(), bytes);
    },
  );

  test('active session preserves an orphan and blocks replacement', () async {
    await file('update.apk').parent.create(recursive: true);
    await file('update.apk').writeAsBytes(bytes);
    await file('update.apk.part').writeAsString('partial');
    native.installationPending = true;
    controller = make(
      BytesAdapter(() => Stream.value(Uint8List.fromList(bytes))),
    );
    await controller.initialize();
    expect(controller.state, ApplicationUpdateDownloadState.blocked);
    expect(await file('update.apk.part').exists(), false);
    await controller.download(release());
    await controller.cancelAndClear();
    expect(await file('update.apk').readAsBytes(), bytes);
  });

  test(
    'installed same or newer version clears orphan without metadata or network',
    () async {
      await file('update.apk').parent.create(recursive: true);
      await file('update.apk').writeAsBytes(bytes);
      native.installedCode = 3;
      final adapter = BytesAdapter(() => throw StateError('must not download'));
      controller = make(adapter);
      await controller.initialize();
      expect(await file('update.apk').exists(), false);
      expect(adapter.calls, 0);
    },
  );

  test(
    'ready crash fixture is reverified and can initialize repeatedly',
    () async {
      await file('update.apk').parent.create(recursive: true);
      await file('update.apk').writeAsBytes(bytes);
      await file('pending.json').writeAsString(
        jsonEncode({
          'release': release().toJson(),
          'phase': 'ready',
          'versionCode': 2,
          'attemptId': null,
        }),
      );
      controller = make(
        BytesAdapter(() => throw StateError('must not download')),
      );
      await Future.wait([controller.initialize(), controller.initialize()]);
      expect(controller.state, ApplicationUpdateDownloadState.ready);
      expect(controller.candidate?.version, '2.0.0');
    },
  );

  test(
    'evicted APK with native handoff remains blocked and retains pending',
    () async {
      await file('pending.json').parent.create(recursive: true);
      await file('pending.json').writeAsString('original handoff record');
      native.installationPending = true;
      final adapter = BytesAdapter(
        () => Stream.value(Uint8List.fromList(bytes)),
      );
      controller = make(adapter);
      await controller.initialize();
      expect(controller.state, ApplicationUpdateDownloadState.blocked);
      await controller.download(release());
      await controller.cancelAndClear();
      expect(controller.state, ApplicationUpdateDownloadState.blocked);
      expect(adapter.calls, 0);
      expect(
        await file('pending.json').readAsString(),
        'original handoff record',
      );
      expect(await file('update.apk.part').exists(), false);
    },
  );

  test('ready metadata cannot override native unknown handoff', () async {
    await file('update.apk').parent.create(recursive: true);
    await file('update.apk').writeAsBytes(bytes);
    final record = jsonEncode({
      'release': release().toJson(),
      'phase': 'ready',
      'attemptId': null,
    });
    await file('pending.json').writeAsString(record);
    native.installationPending = true;
    final adapter = BytesAdapter(() => Stream.value(Uint8List.fromList(bytes)));
    controller = make(adapter);
    await controller.initialize();
    expect(controller.state, ApplicationUpdateDownloadState.blocked);
    await controller.download(release());
    await controller.cancelAndClear();
    expect(adapter.calls, 0);
    expect(await file('update.apk').readAsBytes(), bytes);
    expect(await file('pending.json').readAsString(), record);
  });

  test(
    'terminal callback cannot release another native unknown handoff',
    () async {
      controller = make(
        BytesAdapter(() => Stream.value(Uint8List.fromList(bytes))),
      );
      await controller.download(release());
      native.installation = Completer();
      final installing = controller.install();
      String? attempt;
      while (attempt == null) {
        final record =
            jsonDecode(await file('pending.json').readAsString()) as Map;
        attempt = record['attemptId'] as String?;
        await Future<void>.delayed(Duration.zero);
      }
      native.installationPending = true;
      native.installation!.complete(
        ApplicationUpdateInstallationResult(attempt, 'cancelled'),
      );
      await installing;
      await controller.cancelAndClear();
      expect(controller.state, ApplicationUpdateDownloadState.blocked);
      expect(await file('update.apk').exists(), true);
    },
  );

  test(
    'close racing startup still preserves an unknown complete file',
    () async {
      await file('update.apk').parent.create(recursive: true);
      await file('update.apk').writeAsBytes(bytes);
      native.installationPending = true;
      controller = make(
        BytesAdapter(() => throw StateError('must not download')),
      );
      await Future.wait([controller.initialize(), controller.closeAndWait()]);
      expect(await file('update.apk').readAsBytes(), bytes);
    },
  );

  test(
    'pending session keeps candidate across restart until the session ends',
    () async {
      final adapter = BytesAdapter(
        () => Stream.value(Uint8List.fromList(bytes)),
      );
      controller = make(adapter);
      await controller.download(release());
      native.status = 'pending';
      await controller.install();
      expect(controller.state, ApplicationUpdateDownloadState.blocked);
      await controller.closeAndWait();
      expect(await file('update.apk').exists(), true);
      native.installationPending = true;
      controller = make(adapter);
      await controller.initialize();
      expect(controller.state, ApplicationUpdateDownloadState.blocked);
      expect(controller.candidate?.version, '2.0.0');
      await controller.initialize();
      expect(controller.state, ApplicationUpdateDownloadState.blocked);
      // The user declined in the system UI while Leaf was in the background.
      native.installationPending = false;
      await controller.initialize();
      expect(controller.state, ApplicationUpdateDownloadState.ready);
      expect(controller.candidate?.version, '2.0.0');
      native.status = 'cancelled';
      await controller.install();
      expect(controller.state, ApplicationUpdateDownloadState.ready);
      expect(adapter.calls, 1);
      expect(native.attempts.toSet(), hasLength(2));
    },
  );

  test('cancelled session retries from the local file', () async {
    final adapter = BytesAdapter(() => Stream.value(Uint8List.fromList(bytes)));
    controller = make(adapter);
    await controller.download(release());
    native.status = 'cancelled';
    await controller.install();
    expect(controller.state, ApplicationUpdateDownloadState.ready);
    expect(controller.error, 'Installation cancelled');
    expect(await file('update.apk').readAsBytes(), bytes);
    native.status = 'installed';
    await controller.install();
    expect(adapter.calls, 1);
    expect(native.attempts, hasLength(2));
    expect(native.attempts.first, isNot(native.attempts.last));
    expect(controller.state, ApplicationUpdateDownloadState.idle);
    expect(await file('update.apk').exists(), false);
    expect(await file('pending.json').exists(), false);
  });

  test('failed session keeps the package and exposes system message', () async {
    controller = make(
      BytesAdapter(() => Stream.value(Uint8List.fromList(bytes))),
    );
    await controller.download(release());
    native.status = 'failed';
    native.message = 'INSTALL_FAILED_INSUFFICIENT_STORAGE';
    await controller.install();
    expect(controller.state, ApplicationUpdateDownloadState.ready);
    expect(controller.error, 'Installation failed');
    expect(controller.errorDetail, 'INSTALL_FAILED_INSUFFICIENT_STORAGE');
    expect(await file('update.apk').exists(), true);
  });

  test('installed result is confirmed by the installed version code', () async {
    controller = make(
      BytesAdapter(() => Stream.value(Uint8List.fromList(bytes))),
    );
    await controller.download(release());
    native.status = 'unknown';
    native.installation = Completer();
    final installing = controller.install();
    while (native.attempts.isEmpty) {
      await Future<void>.delayed(Duration.zero);
    }
    native.installedCode = 2;
    native.installation!.complete(
      ApplicationUpdateInstallationResult(native.attempts.single, 'installed'),
    );
    await installing;
    expect(controller.state, ApplicationUpdateDownloadState.idle);
    expect(await file('update.apk').exists(), false);
  });

  test('native rejection without an active session does not block', () async {
    controller = make(
      BytesAdapter(() => Stream.value(Uint8List.fromList(bytes))),
    );
    await controller.download(release());
    native.installError = StateError('Update version does not match release');
    await controller.install();
    expect(controller.state, ApplicationUpdateDownloadState.failed);
    expect(await file('update.apk').exists(), false);
  });

  test('close does not wait for system installation UI', () async {
    controller = make(
      BytesAdapter(() => Stream.value(Uint8List.fromList(bytes))),
    );
    await controller.download(release());
    native.installation = Completer();
    final installing = controller.install();
    while (!await file(
      'pending.json',
    ).readAsString().then((value) => value.contains('installing'))) {
      await Future<void>.delayed(Duration.zero);
    }
    await controller.closeAndWait().timeout(const Duration(seconds: 1));
    expect(await file('update.apk').exists(), true);
    native.installation!.complete(
      const ApplicationUpdateInstallationResult('stale', 'cancelled'),
    );
    await installing;
  });

  test('symbolic link is never followed or cleaned', () async {
    final outside = File('${root.path}/sentinel');
    await outside.writeAsString('keep');
    await file('update.apk').parent.create(recursive: true);
    await Link(file('update.apk').path).create(outside.path);
    controller = make(
      BytesAdapter(() => throw StateError('must not download')),
    );
    await controller.initialize();
    expect(controller.state, ApplicationUpdateDownloadState.blocked);
    expect(await outside.readAsString(), 'keep');
  });

  group('download queue hold', () {
    BytesAdapter valid() =>
        BytesAdapter(() => Stream.value(Uint8List.fromList(bytes)));

    test('lasts from download until handoff to the installer', () async {
      controller = make(valid());
      final downloading = controller.download(release());
      expect(queueHolds, {1});
      await downloading;
      expect(controller.state, ApplicationUpdateDownloadState.ready);
      expect(queueHolds, {1});
      native.installation = Completer();
      final installing = controller.install();
      while (queueHolds.isNotEmpty) {
        await Future<void>.delayed(Duration.zero);
      }
      native.installation!.complete(
        const ApplicationUpdateInstallationResult('stale', 'cancelled'),
      );
      await installing;
      expect(queueHolds, isEmpty);
    });

    test('ends with download or verification failure', () async {
      controller = make(BytesAdapter(() => const Stream.empty(), status: 404));
      await controller.download(release());
      expect(controller.state, ApplicationUpdateDownloadState.failed);
      expect(queueHolds, isEmpty);
      await controller.closeAndWait();
      controller = make(
        BytesAdapter(() => Stream.value(Uint8List(bytes.length))),
      );
      await controller.download(release());
      expect(controller.state, ApplicationUpdateDownloadState.failed);
      expect(queueHolds, isEmpty);
    });

    test('ends with cancellation during transfer and with close', () async {
      final chunks = StreamController<Uint8List>();
      final adapter = BytesAdapter(() => chunks.stream);
      controller = make(adapter);
      final active = controller.download(release());
      while (adapter.calls == 0) {
        await Future<void>.delayed(Duration.zero);
      }
      await controller.cancelAndClear();
      expect(queueHolds, isEmpty);
      await active;
      await chunks.close();
      await controller.closeAndWait();
      controller = make(valid());
      await controller.download(release());
      expect(queueHolds, {2});
      await controller.closeAndWait();
      expect(queueHolds, isEmpty);
    });

    test('ends when install permission is denied', () async {
      controller = make(valid());
      await controller.download(release());
      native.permitted = false;
      await controller.install();
      expect(controller.error, 'Permission to install updates was denied');
      expect(queueHolds, isEmpty);
    });

    test('an older round cannot release the next round', () async {
      controller = make(valid());
      await controller.download(release());
      native.permitted = false;
      native.permission = Completer();
      final installing = controller.install();
      await Future<void>.delayed(Duration.zero);
      await controller.cancelAndClear();
      expect(queueHolds, isEmpty);
      await controller.download(release());
      expect(queueHolds, {2});
      native.permission!.complete();
      await installing;
      expect(queueHolds, {2});
    });
  });
}
