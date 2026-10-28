import 'dart:async';
import 'dart:convert';

import 'package:venera_next/network/app_dio.dart'
    show Dio, Options, RHttpAdapter;
import 'package:venera_next/network/request_scope.dart';

import 'application_update_release.dart';
import 'operation_failure.dart';
import 'release_version.dart';

/// Owns actual HTTP completion independently of the page showing its result.
class ApplicationUpdateService {
  ApplicationUpdateService({
    required Dio Function() createClient,
    required String Function() currentVersion,
    this.releaseRepository = defaultReleaseRepository,
  }) : _createClient = createClient,
       _currentVersion = currentVersion {
    final configuredRepository = releaseRepository;
    if (configuredRepository != null &&
        !_repositoryPattern.hasMatch(configuredRepository)) {
      throw ArgumentError.value(
        releaseRepository,
        'releaseRepository',
        'Expected a GitHub owner/repository path',
      );
    }
  }

  static const defaultReleaseRepository = 'CyrilPeng/venera-next';
  static const androidDefaultReleaseRepository = 'typhoonwhale/VeneraNext-Leaf';
  static final _repositoryPattern = RegExp(
    r'^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$',
  );

  final Dio Function() _createClient;
  final String Function() _currentVersion;
  final String? releaseRepository;
  final _pending = <RequestScope, Future<void>>{};
  final _cleanupFailures = <ApplicationUpdateCleanupFailure>[];
  bool _closed = false;
  Future<void>? _closing;

  bool get isEnabled => releaseRepository != null;

  String? get releasePageUrl => releaseRepository == null
      ? null
      : 'https://github.com/$releaseRepository/releases';

  Future<String?> check({RequestScope? scope}) =>
      _checkWith<String>(scope, (version, _) => version);

  Future<ApplicationUpdateRelease?> checkRelease({RequestScope? scope}) =>
      _checkWith<ApplicationUpdateRelease>(
        scope,
        (_, release) => ApplicationUpdateRelease.fromReleaseMetadata(
          release,
          repository: releaseRepository!,
        ),
      );

  Future<T?> _checkWith<T>(
    RequestScope? scope,
    T Function(String version, Map release) select,
  ) {
    if (_closed) {
      return Future.error(StateError('Application updates are closed'));
    }
    if (!isEnabled) return Future.value(null);
    final owned = RequestScope(parent: scope);
    final completion = Completer<T?>();
    final settled = completion.future
        .then<void>((_) {}, onError: (Object _, StackTrace _) {})
        .whenComplete(() {
          owned.dispose();
          _pending.remove(owned);
        });
    // Registration precedes injected callbacks, which may reenter close.
    _pending[owned] = settled;
    _check<T>(
      owned,
      select,
    ).then(completion.complete, onError: completion.completeError);
    return completion.future;
  }

  Future<T?> _check<T>(
    RequestScope scope,
    T Function(String version, Map release) select,
  ) async {
    scope.check();
    final version = _currentVersion();
    scope.check();
    final dio = _createClient();
    final adapter = dio.httpClientAdapter;
    Object? cause;
    StackTrace? causeStack;
    T? available;
    try {
      scope.check();
      final includePrerelease = allowsPrereleaseUpdates(version);
      final repository = releaseRepository!;
      final isLeafStableCheck =
          !includePrerelease &&
          repository.toLowerCase() ==
              androidDefaultReleaseRepository.toLowerCase();
      final releasesUri = Uri.https(
        'api.github.com',
        '/repos/$repository/releases',
        {'per_page': '20'},
      );
      var response = await dio.getUri<Object?>(
        includePrerelease
            ? releasesUri
            : Uri.https('api.github.com', '/repos/$repository/releases/latest'),
        cancelToken: scope.cancelToken,
        options: Options(
          headers: {'Accept': 'application/vnd.github+json'},
          connectTimeout: const Duration(seconds: 15),
          receiveTimeout: const Duration(seconds: 30),
          sendTimeout: const Duration(seconds: 30),
          validateStatus: isLeafStableCheck
              ? (status) =>
                    status != null &&
                    ((status >= 200 && status < 300) || status == 404)
              : null,
        ),
      );
      scope.check();
      if (isLeafStableCheck && response.statusCode == 404) {
        // A new repository has no /latest release yet. Confirm with the
        // collection endpoint: an empty list means no update, while missing
        // repositories, permissions and HTTP errors remain failures.
        response = await dio.getUri<Object?>(
          releasesUri,
          cancelToken: scope.cancelToken,
          options: Options(
            headers: {'Accept': 'application/vnd.github+json'},
            connectTimeout: const Duration(seconds: 15),
            receiveTimeout: const Duration(seconds: 30),
            sendTimeout: const Duration(seconds: 30),
          ),
        );
        scope.check();
      }
      if (response.statusCode != 200) {
        throw FormatException(
          'Unexpected release status: ${response.statusCode}',
        );
      }
      final data = response.data is String
          ? jsonDecode(response.data as String)
          : response.data;
      if (data is! Map && data is! List) {
        throw const FormatException('Invalid release response');
      }
      final releases = data is List ? data : [data];
      for (final release in releases) {
        if (release is! Map ||
            release['tag_name'] is! String ||
            !_semanticVersionTag.hasMatch(release['tag_name'] as String)) {
          throw const FormatException('Invalid release metadata');
        }
      }
      final latest = selectPublishedReleaseVersion(
        data,
        includePrerelease: includePrerelease,
      );
      if (latest != null && shouldNotifyRelease(latest, version)) {
        final release = _findPublishedRelease(
          data,
          version: latest,
          includePrerelease: includePrerelease,
        );
        if (release == null) {
          throw const FormatException('Selected release metadata not found');
        }
        available = select(latest, release);
      }
    } catch (error, stack) {
      cause = error;
      causeStack = stack;
      if (scope.isCancelled) throw const RequestCancelled();
      Error.throwWithStackTrace(
        OperationFailure(
          message: 'Failed to check application updates',
          cause: error,
          stackTrace: stack,
        ),
        stack,
      );
    } finally {
      final failures = <({Object error, StackTrace stack})>[];
      Future<void> release(FutureOr<void> Function() action) async {
        try {
          await action();
        } catch (error, stack) {
          failures.add((error: error, stack: stack));
        }
      }

      await release(() => dio.close(force: true));
      if (adapter is RHttpAdapter) await release(adapter.waitForIdle);
      if (failures.isNotEmpty) {
        final failure = ApplicationUpdateCleanupFailure(
          failures,
          cause: cause,
          stackTrace: causeStack,
        );
        _cleanupFailures.add(failure);
        throw failure;
      }
    }
    scope.check();
    return available;
  }

  static final _semanticVersionTag = RegExp(
    r'^[vV]?(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)'
    r'(?:-(?:0|[1-9][0-9]*|[0-9A-Za-z-]*[A-Za-z-][0-9A-Za-z-]*)'
    r'(?:\.(?:0|[1-9][0-9]*|[0-9A-Za-z-]*[A-Za-z-][0-9A-Za-z-]*))*'
    r')?(?:\+[0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*)?$',
  );

  Map? _findPublishedRelease(
    Object? data, {
    required String version,
    required bool includePrerelease,
  }) {
    final releases = data is List ? data : [data];
    for (final release in releases) {
      if (release is! Map ||
          release['draft'] == true ||
          (!includePrerelease && release['prerelease'] == true)) {
        continue;
      }
      final tag = release['tag_name'];
      if (tag is String && tag.replaceFirst(RegExp(r'^[vV]'), '') == version) {
        return release;
      }
    }
    return null;
  }

  Future<void> closeAndWait() {
    final closing = _closing;
    if (closing != null) return closing;
    _closed = true;
    final done = Completer<void>();
    _closing = done.future;
    for (final scope in _pending.keys.toList()) {
      scope.cancel();
    }
    _drain().then(done.complete, onError: done.completeError);
    return done.future;
  }

  Future<void> _drain() async {
    while (_pending.isNotEmpty) {
      await Future.wait(_pending.values.toList());
    }
    if (_cleanupFailures.isNotEmpty) {
      throw ApplicationUpdateCleanupFailure([
        for (final failure in _cleanupFailures)
          (error: failure, stack: failure.stackTrace ?? StackTrace.current),
      ]);
    }
  }
}

class ApplicationUpdateCleanupFailure implements FailureDetails {
  ApplicationUpdateCleanupFailure(
    Iterable<({Object error, StackTrace stack})> failures, {
    this.cause,
    this.stackTrace,
  }) : failures = List.unmodifiable(failures);

  final List<({Object error, StackTrace stack})> failures;
  @override
  final Object? cause;
  @override
  final StackTrace? stackTrace;
  @override
  FailureKind get kind => FailureKind.failed;
  @override
  String get message =>
      'Application update cleanup failed: '
      '${failures.map((failure) => failure.error).join('; ')}';
  @override
  String toString() => message;
}
