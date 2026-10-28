import 'dart:async';

import 'package:venera_next/network/request_scope.dart';

/// A mounted application's startup chain. The source service independently
/// owns shared source checks; cancellation only retires this consumer's wait.
class StartupUpdateCheck {
  StartupUpdateCheck({
    required this.reserveSourceCheck,
    required this.reserveApplicationCheck,
    required this.checkSources,
    required this.checkApplication,
    required this.applicationCheckEnabled,
  });

  final Future<bool> Function() reserveSourceCheck;
  final Future<bool> Function() reserveApplicationCheck;
  final Future<void> Function() checkSources;
  final Future<void> Function(RequestScope) checkApplication;
  final bool Function() applicationCheckEnabled;
  final _scope = RequestScope();
  Future<void>? _result;
  Future<void>? _settled;

  Future<void> start() {
    final result = _result;
    if (result != null) return result;
    final done = Completer<void>();
    _result = done.future;
    _settled = done.future
        .then<void>((_) {}, onError: (Object _, StackTrace _) {})
        .whenComplete(_scope.dispose);
    _run().then(done.complete, onError: done.completeError);
    return done.future;
  }

  Future<void> _run() => Future.wait([_runSources(), _runApplication()]);

  Future<void> _runSources() async {
    try {
      _scope.check();
      // Already admitted persistence must actually finish before stores close.
      final reserved = await reserveSourceCheck();
      _scope.check();
      if (reserved) await _scope.run(checkSources);
    } on RequestCancelled {
      // The source service owns and drains the shared request on host shutdown.
    }
  }

  Future<void> _runApplication() async {
    try {
      _scope.check();
      if (!applicationCheckEnabled()) return;
      final reserved = await reserveApplicationCheck();
      _scope.check();
      if (reserved) await checkApplication(_scope);
    } on RequestCancelled {
      // The application callback joins its accepted request before returning.
    }
  }

  void cancel() => _scope.cancel();

  Future<void> closeAndWait() {
    cancel();
    return _settled ?? Future.value();
  }
}
