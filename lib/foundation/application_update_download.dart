import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../network/app_dio.dart' show RHttpAdapter;
import 'application_update_installer.dart';
import 'application_update_release.dart';
import 'log.dart';

enum ApplicationUpdateDownloadState {
  idle,
  downloading,
  verifying,
  ready,
  installing,
  blocked,
  failed,
}

/// One application-owned serial lane for every update file operation.
class ApplicationUpdateDownload extends ChangeNotifier {
  ApplicationUpdateDownload({
    required String cacheRoot,
    required this.repository,
    required this.dioFactory,
    ApplicationUpdateInstaller? installer,
    this.networkTimeout = const Duration(seconds: 30),
    this.holdDownloadQueue,
  }) : directory = Directory('$cacheRoot/updates'),
       installer = installer ?? const MethodChannelApplicationUpdateInstaller();

  final Duration networkTimeout;
  final Directory directory;
  final String repository;
  final Dio Function() dioFactory;
  final ApplicationUpdateInstaller installer;

  /// Stops other downloads from starting on their own during one update round;
  /// returns that round's release callback.
  final VoidCallback Function()? holdDownloadQueue;
  ApplicationUpdateDownloadState state = ApplicationUpdateDownloadState.idle;
  ApplicationUpdateRelease? candidate;
  int progress = 0;
  int received = 0;
  String? error;

  /// Untranslated system message accompanying [error], such as an installer
  /// failure reason.
  String? errorDetail;

  /// The system confirmation was left open; the user may reopen or cancel it.
  bool awaitingConfirmation = false;
  bool get isSupported => _supported;
  bool get busy =>
      state == ApplicationUpdateDownloadState.downloading ||
      state == ApplicationUpdateDownloadState.verifying ||
      state == ApplicationUpdateDownloadState.installing;
  bool _supported = false;
  bool _initialized = false;
  bool _closed = false;
  bool _occupied = false;
  // Blocked only by an installation session, which can end while Leaf runs.
  bool _sessionPending = false;
  int _generation = 0;
  String? _attemptId;
  Future<void> _tail = Future.value();
  CancelToken? _cancel;
  VoidCallback? _downloadQueueHold;
  File get _part => File('${directory.path}/update.apk.part');
  File get _apk => File('${directory.path}/update.apk');
  File get _pending => File('${directory.path}/pending.json');
  File get _temporary => File('${directory.path}/pending.json.tmp');

  void _set(
    ApplicationUpdateDownloadState value, [
    String? message,
    String? detail,
  ]) {
    state = value;
    error = message;
    errorDetail = detail;
    awaitingConfirmation = false;
    if (!_closed) notifyListeners();
  }

  Future<void> _serial(Future<void> Function() operation) {
    final future = _tail.then((_) => operation());
    _tail = future.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return future;
  }

  Future<void> _safeDirectory() async {
    final type = await FileSystemEntity.type(
      directory.path,
      followLinks: false,
    );
    if (type != FileSystemEntityType.notFound &&
        type != FileSystemEntityType.directory) {
      throw StateError('Update directory is not a private directory');
    }
    await directory.create(recursive: true);
    for (final file in [_part, _apk, _pending, _temporary]) {
      final type = await FileSystemEntity.type(file.path, followLinks: false);
      if (type != FileSystemEntityType.notFound &&
          type != FileSystemEntityType.file) {
        throw StateError('Unexpected update cache entry');
      }
    }
  }

  Future<void> _delete(File file) async {
    if (await file.exists()) await file.delete();
  }

  Future<void> _clear() async {
    if (_occupied) throw StateError('Previous installation is unconfirmed');
    await _delete(_part);
    await _delete(_apk);
    await _delete(_pending);
    await _delete(_temporary);
    candidate = null;
    _attemptId = null;
  }

  Future<void> _persist(String phase, {int? versionCode}) async {
    await _temporary.writeAsString(
      jsonEncode({
        'release': candidate!.toJson(),
        'phase': phase,
        'versionCode': versionCode,
        'attemptId': _attemptId,
      }),
      flush: true,
    );
    await _temporary.rename(_pending.path);
  }

  Future<void> initialize() => _serial(() async {
    // Re-read the session before presenting a candidate it blocked earlier.
    final recheck =
        _sessionPending && state == ApplicationUpdateDownloadState.blocked;
    if (recheck) {
      _sessionPending = false;
      _initialized = false;
      _occupied = false;
      state = ApplicationUpdateDownloadState.idle;
      error = null;
      errorDetail = null;
    }
    await _initialize();
    if (recheck && !_closed) notifyListeners();
  });
  Future<void> _initialize() async {
    if (_initialized) return;
    try {
      await _safeDirectory();
      await _delete(_part);
      await _delete(_temporary);
      final current = await installer.current();
      _supported = !current.debug;
      if (await _apk.exists()) {
        _occupied = true;
        try {
          // Static native inspection is valid even when the candidate is older.
          final inspection = await installer.inspect(partial: false);
          if (inspection.installedVersionCode >= inspection.versionCode &&
              !current.installationPending) {
            _occupied = false;
            await _clear();
            _initialized = true;
            return;
          }
          final json =
              jsonDecode(await _pending.readAsString()) as Map<String, dynamic>;
          candidate = ApplicationUpdateRelease.fromJson(
            json['release'] as Map<String, dynamic>,
            repository: repository,
          );
          _attemptId = json['attemptId'] as String?;
          await _verify(_apk, partial: false, requireNewer: false);
        } catch (failure) {
          // Committed sessions hold their own copy; without an active session
          // nothing else reads this file, so an unverifiable one is discarded.
          if (current.installationPending) {
            _sessionPending = true;
            rethrow;
          }
          Log.error(
            'Application update',
            'Discarding unverifiable candidate: ${failure.runtimeType}',
          );
          _occupied = false;
          await _clear();
          _initialized = true;
          return;
        }
        // Session state, not the recorded phase, decides whether it is in use.
        _occupied = current.installationPending;
        _sessionPending = _occupied;
        _set(
          _occupied
              ? ApplicationUpdateDownloadState.blocked
              : ApplicationUpdateDownloadState.ready,
          _occupied ? 'Previous installation is unconfirmed' : null,
        );
      } else if (current.installationPending) {
        // The session holds its own copy after an eviction; keep the record
        // and wait for that session instead of starting another.
        _occupied = true;
        _sessionPending = true;
        _set(
          ApplicationUpdateDownloadState.blocked,
          'Previous installation is unconfirmed',
        );
      } else {
        await _delete(_pending);
      }
      _initialized = true;
    } catch (failure, stack) {
      Log.error(
        'Application update',
        'Cache recovery failed: ${failure.runtimeType}\n$stack',
      );
      _set(
        ApplicationUpdateDownloadState.blocked,
        'Update cache could not be recovered safely',
      );
      // Keep the complete file immutable when its ownership cannot be proved.
      _occupied = true;
    }
  }

  Future<ApplicationUpdateInspection> _verify(
    File file, {
    required bool partial,
    required bool requireNewer,
  }) async {
    final release = candidate!;
    final asset = release.asset;
    if (asset == null || await file.length() != asset.size) {
      throw StateError('Package size mismatch');
    }
    final digest = await sha256.bind(file.openRead()).first;
    if (digest.toString().toLowerCase() != asset.sha256.toLowerCase()) {
      throw StateError('Package digest mismatch');
    }
    final inspection = await installer.inspect(partial: partial);
    if (inspection.versionName != release.version ||
        (requireNewer &&
            inspection.versionCode <= inspection.installedVersionCode)) {
      throw StateError('Package version mismatch');
    }
    return inspection;
  }

  /// Each round releases only its own hold, so a stale callback from an older
  /// round cannot lift the restriction of a newer one.
  VoidCallback _holdDownloadQueue() {
    _downloadQueueHold?.call();
    VoidCallback? release;
    try {
      release = holdDownloadQueue?.call();
    } catch (failure, stack) {
      Log.error('Application update', failure, stack);
    }
    late final VoidCallback hold;
    hold = () {
      if (identical(_downloadQueueHold, hold)) _downloadQueueHold = null;
      final callback = release;
      release = null;
      callback?.call();
    };
    return _downloadQueueHold = hold;
  }

  void _checkCancellation() {
    if (_cancel?.isCancelled == true) throw StateError('Update cancelled');
  }

  Future<void> download(ApplicationUpdateRelease release) {
    if (_closed || busy) return Future.value();
    final generation = _generation;
    // Set synchronously so a second click cannot queue a second transfer.
    _set(ApplicationUpdateDownloadState.downloading);
    final queueHold = _holdDownloadQueue();
    return _serial(() async {
      Dio? dio;
      RandomAccessFile? file;
      Future<void> stopNetwork() async {
        final client = dio;
        if (client == null) return;
        dio = null;
        final adapter = client.httpClientAdapter;
        client.close(force: true);
        if (adapter is RHttpAdapter) await adapter.waitForIdle();
      }

      try {
        await _initialize();
        if (_closed || generation != _generation) return;
        if (!_supported || _occupied || !_initialized) {
          throw StateError('Application update is unavailable');
        }
        await _safeDirectory();
        await _clear();
        // Cancellation can arrive during directory checks or old-file removal,
        // before this transfer has a token to cancel.
        if (_closed || generation != _generation) return;
        candidate = release;
        final asset = release.asset;
        if (asset == null ||
            asset.size <= 0 ||
            !isAllowedUpdateDownloadUri(
              asset.url,
              initial: true,
              repository: repository,
            )) {
          throw StateError('Invalid release asset');
        }
        received = 0;
        progress = 0;
        _cancel = CancelToken();
        _set(ApplicationUpdateDownloadState.downloading);
        final client = dioFactory();
        dio = client;
        // A dedicated factory supplies proxy transport, never source cookies.
        client.options.headers.clear();
        client.interceptors.clear();
        var uri = asset.url;
        Response<ResponseBody>? response;
        for (var redirects = 0; redirects <= 5; redirects++) {
          _checkCancellation();
          response = await client
              .getUri<ResponseBody>(
                uri,
                cancelToken: _cancel,
                options: Options(
                  responseType: ResponseType.stream,
                  receiveTimeout: networkTimeout,
                  followRedirects: false,
                  validateStatus: (_) => true,
                  headers: {'Accept': 'application/octet-stream'},
                ),
              )
              .timeout(
                networkTimeout,
                onTimeout: () {
                  _cancel?.cancel('Update response timed out');
                  throw TimeoutException('Update response timed out');
                },
              );
          final status = response.statusCode!;
          if (status >= 300 && status < 400) {
            await response.data!.stream.listen((_) {}).cancel();
            final location = response.headers.value('location');
            if (location == null || redirects == 5) {
              throw StateError('Invalid download redirect');
            }
            uri = uri.resolve(location);
            if (!isAllowedUpdateDownloadUri(
              uri,
              initial: false,
              repository: repository,
            )) {
              throw StateError('Unsafe download redirect');
            }
            continue;
          }
          if (status != 200) {
            await response.data!.stream.listen((_) {}).cancel();
            throw StateError('Download HTTP $status');
          }
          break;
        }
        final body = response!.data!;
        final length = response.headers.value('content-length');
        if (length != null && int.tryParse(length) != asset.size) {
          await body.stream.listen((_) {}).cancel();
          throw StateError('Package size mismatch');
        }
        file = await _part.open(mode: FileMode.write);
        final progressClock = Stopwatch()..start();
        await for (final chunk in body.stream.timeout(networkTimeout)) {
          _checkCancellation();
          received += chunk.length;
          if (received > asset.size) {
            throw StateError('Package exceeds declared size');
          }
          await file.writeFrom(chunk);
          final percent = received * 100 ~/ asset.size;
          if (percent != progress &&
              (percent == 100 || progressClock.elapsedMilliseconds >= 250)) {
            progress = percent;
            progressClock.reset();
            if (!_closed) notifyListeners();
          }
        }
        await file.close();
        file = null;
        _checkCancellation();
        _set(ApplicationUpdateDownloadState.verifying);
        final inspection = await _verify(
          _part,
          partial: true,
          requireNewer: true,
        );
        _checkCancellation();
        await _part.rename(_apk.path);
        await _persist('ready', versionCode: inspection.versionCode);
        _set(ApplicationUpdateDownloadState.ready);
      } catch (failure, stack) {
        Log.error(
          'Application update',
          'Download/verify failed for ${candidate?.version}: ${failure is DioException
              ? failure.type.name
              : failure is StateError
              ? failure.message
              : failure.runtimeType}; HTTP ${failure is DioException ? failure.response?.statusCode : null}\n$stack',
        );
        try {
          await stopNetwork();
        } catch (_) {
          _occupied = true;
        }
        if (file != null) {
          try {
            await file.close();
          } catch (_) {
            _occupied = true;
          }
        }
        if (!_occupied) {
          try {
            await _clear();
          } catch (_) {
            _occupied = true;
          }
        }
        _set(
          _occupied
              ? ApplicationUpdateDownloadState.blocked
              : ApplicationUpdateDownloadState.failed,
          _occupied
              ? 'Update cache is occupied or cannot be cleaned'
              : 'Update download or verification failed',
        );
      } finally {
        try {
          await stopNetwork();
        } catch (_) {
          _occupied = true;
          _set(
            ApplicationUpdateDownloadState.blocked,
            'Download transport could not be closed',
          );
        }
        _cancel = null;
        // A verified package keeps the hold until it is handed to the installer.
        if (_closed ||
            generation != _generation ||
            state != ApplicationUpdateDownloadState.ready) {
          queueHold();
        }
      }
    });
  }

  Future<void> install() async {
    if (_closed ||
        state != ApplicationUpdateDownloadState.ready ||
        !_supported) {
      return;
    }
    final generation = _generation;
    final queueHold = _downloadQueueHold;
    _set(ApplicationUpdateDownloadState.installing);
    // Permission and system UI futures are outside the file lane: closing the
    // app must not wait indefinitely for a user to return from another app.
    try {
      if (!await installer.canInstall()) {
        await installer.requestPermission();
        if (_closed || generation != _generation) return;
        if (!await installer.canInstall()) {
          queueHold?.call();
          _set(
            ApplicationUpdateDownloadState.ready,
            'Permission to install updates was denied',
          );
          return;
        }
      }
      if (_closed || generation != _generation) return;
      String? attempt;
      await _serial(() async {
        if (_closed || generation != _generation) return;
        await _safeDirectory();
        if ((await installer.current()).installationPending) {
          _occupied = true;
          _sessionPending = true;
          throw StateError('Previous installation is unconfirmed');
        }
        final inspection = await _verify(
          _apk,
          partial: false,
          requireNewer: true,
        );
        _attemptId = const Uuid().v4();
        await _persist('installing', versionCode: inspection.versionCode);
        _occupied = true;
        attempt = _attemptId;
      });
      if (attempt == null || _closed || generation != _generation) return;
      queueHold?.call();
      final awaiting = installer.awaitingConfirmation.listen((id) {
        if (id != attempt ||
            _closed ||
            generation != _generation ||
            state != ApplicationUpdateDownloadState.installing) {
          return;
        }
        awaitingConfirmation = true;
        notifyListeners();
      });
      final ApplicationUpdateInstallationResult result;
      try {
        result = await installer.install(
          version: candidate!.version,
          attemptId: attempt!,
        );
      } finally {
        await awaiting.cancel();
        awaitingConfirmation = false;
      }
      if (_closed || generation != _generation) return;
      await _serial(() async {
        if (_closed ||
            generation != _generation ||
            result.attemptId != _attemptId) {
          return;
        }
        if (result.status == 'cancelled' || result.status == 'failed') {
          _occupied = (await installer.current()).installationPending;
          if (_occupied) {
            _sessionPending = true;
            _set(
              ApplicationUpdateDownloadState.blocked,
              'Previous installation is unconfirmed',
            );
            return;
          }
          _attemptId = null;
          await _persist('ready');
          _set(
            ApplicationUpdateDownloadState.ready,
            'Installation ${result.status}',
            result.status == 'failed' ? result.message : null,
          );
        } else {
          final inspection = await installer.inspect(partial: false);
          if (inspection.installedVersionCode >= inspection.versionCode) {
            _occupied = false;
            await _clear();
            _set(ApplicationUpdateDownloadState.idle);
          } else {
            _sessionPending = true;
            _set(
              ApplicationUpdateDownloadState.blocked,
              'Previous installation is unconfirmed',
            );
          }
        }
      });
    } catch (failure, stack) {
      Log.error(
        'Application update',
        'Install failed for ${candidate?.version}: ${failure.runtimeType}\n$stack',
      );
      queueHold?.call();
      if (_occupied) {
        // Only an active session keeps the file; otherwise nothing reads it.
        try {
          _occupied = (await installer.current()).installationPending;
        } catch (_) {}
        _sessionPending = _occupied;
      }
      if (!_occupied) {
        await _serial(() async {
          try {
            await _clear();
          } catch (_) {
            _occupied = true;
          }
        });
      }
      _set(
        _occupied
            ? ApplicationUpdateDownloadState.blocked
            : ApplicationUpdateDownloadState.failed,
        _occupied
            ? 'Previous installation is unconfirmed'
            : 'Unable to prepare installation',
      );
    }
  }

  Future<void> reopenConfirmation() => _resolveConfirmation(
    (id) => installer.reopenConfirmation(attemptId: id),
    'Unable to reopen installation confirmation',
  );

  /// The pending [install] then completes as cancelled and keeps the package.
  Future<void> cancelInstallation() => _resolveConfirmation(
    (id) => installer.cancelInstallation(attemptId: id),
    'Unable to cancel installation',
  );

  Future<void> _resolveConfirmation(
    Future<void> Function(String attemptId) action,
    String failure,
  ) async {
    final id = _attemptId;
    if (_closed || !awaitingConfirmation || id == null) return;
    awaitingConfirmation = false;
    error = null;
    notifyListeners();
    try {
      await action(id);
    } catch (_) {
      if (_closed ||
          id != _attemptId ||
          state != ApplicationUpdateDownloadState.installing) {
        return;
      }
      awaitingConfirmation = true;
      error = failure;
      notifyListeners();
    }
  }

  Future<void> cancelAndClear() {
    _generation++;
    _downloadQueueHold?.call();
    _cancel?.cancel('Update cancelled');
    return _serial(() async {
      if (!_initialized) await _initialize();
      if (_occupied) {
        _set(
          ApplicationUpdateDownloadState.blocked,
          'Previous installation is unconfirmed',
        );
        return;
      }
      try {
        await _safeDirectory();
        await _clear();
        _set(ApplicationUpdateDownloadState.idle);
      } catch (_) {
        _occupied = true;
        _set(
          ApplicationUpdateDownloadState.blocked,
          'Update cache cannot be cleaned',
        );
      }
    });
  }

  Future<void> closeAndWait() async {
    _closed = true;
    await cancelAndClear();
  }
}
