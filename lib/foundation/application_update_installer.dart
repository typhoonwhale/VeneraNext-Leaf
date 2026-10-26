import 'dart:async';

import 'package:flutter/services.dart';

/// Native checks always use fixed private update paths, never caller paths.
class ApplicationUpdateIdentity {
  const ApplicationUpdateIdentity({
    required this.versionCode,
    required this.versionName,
    this.debug = false,
    this.installationPending = false,
    this.attemptId,
    this.awaitingConfirmation = false,
  });
  final int versionCode;
  final String versionName;
  final bool debug;
  final bool installationPending;

  /// The recorded attempt while [installationPending].
  final String? attemptId;

  /// The system confirmation of [attemptId] can be reopened or cancelled.
  final bool awaitingConfirmation;
  factory ApplicationUpdateIdentity.fromJson(Map<dynamic, dynamic> value) =>
      ApplicationUpdateIdentity(
        versionCode: value['versionCode'] as int,
        versionName: value['versionName'] as String,
        debug: value['debug'] == true,
        installationPending: value['installationPending'] == true,
        attemptId: value['attemptId'] as String?,
        awaitingConfirmation: value['awaitingConfirmation'] == true,
      );
}

class ApplicationUpdateInspection {
  const ApplicationUpdateInspection({
    required this.versionCode,
    required this.versionName,
    required this.installedVersionCode,
  });
  final int versionCode;
  final String versionName;
  final int installedVersionCode;
  factory ApplicationUpdateInspection.fromJson(Map<dynamic, dynamic> value) =>
      ApplicationUpdateInspection(
        versionCode: value['versionCode'] as int,
        versionName: value['versionName'] as String,
        installedVersionCode: value['installedVersionCode'] as int,
      );
}

/// Status is installed, cancelled, failed, pending (session still active) or
/// unknown (not the recorded attempt). Failures may carry the system message.
class ApplicationUpdateInstallationResult {
  const ApplicationUpdateInstallationResult(
    this.attemptId,
    this.status, [
    this.message,
  ]);
  final String attemptId;
  final String status;
  final String? message;
  factory ApplicationUpdateInstallationResult.fromJson(
    Map<dynamic, dynamic> value,
  ) => ApplicationUpdateInstallationResult(
    value['attemptId'] as String,
    value['status'] as String,
    value['message'] as String?,
  );
}

abstract class ApplicationUpdateInstaller {
  Future<ApplicationUpdateIdentity> current();
  Future<ApplicationUpdateInspection> inspect({required bool partial});
  Future<bool> canInstall();
  Future<bool> requestPermission();
  Future<ApplicationUpdateInstallationResult> install({
    required String version,
    required String attemptId,
  });
  Future<ApplicationUpdateInstallationResult> installationStatus({
    required String attemptId,
  });

  /// Attempt IDs whose system confirmation was left without a result.
  Stream<String> get awaitingConfirmation;

  /// Restarts the saved confirmation, or a new session from the local APK.
  Future<void> reopenConfirmation({required String attemptId});

  /// Abandons the open session; the pending [install] completes as cancelled.
  Future<void> cancelInstallation({required String attemptId});
}

class MethodChannelApplicationUpdateInstaller
    implements ApplicationUpdateInstaller {
  const MethodChannelApplicationUpdateInstaller({
    this.channel = const MethodChannel('leaf/application_update'),
  });
  final MethodChannel channel;
  static final _awaiting = StreamController<String>.broadcast();
  static bool _listening = false;
  @override
  Stream<String> get awaitingConfirmation {
    if (!_listening) {
      _listening = true;
      channel.setMethodCallHandler((call) async {
        if (call.method == 'awaitingConfirmation') {
          _awaiting.add((call.arguments as Map)['attemptId'] as String);
        }
      });
    }
    return _awaiting.stream;
  }

  @override
  Future<void> reopenConfirmation({required String attemptId}) => channel
      .invokeMethod<void>('reopenConfirmation', {'attemptId': attemptId});
  @override
  Future<void> cancelInstallation({required String attemptId}) => channel
      .invokeMethod<void>('cancelInstallation', {'attemptId': attemptId});
  @override
  Future<ApplicationUpdateIdentity> current() async =>
      ApplicationUpdateIdentity.fromJson(
        (await channel.invokeMapMethod<dynamic, dynamic>('current'))!,
      );
  @override
  Future<ApplicationUpdateInspection> inspect({required bool partial}) async =>
      ApplicationUpdateInspection.fromJson(
        (await channel.invokeMapMethod<dynamic, dynamic>('inspect', {
          'partial': partial,
        }))!,
      );
  @override
  Future<bool> canInstall() async =>
      await channel.invokeMethod<bool>('canInstall') ?? false;
  @override
  Future<bool> requestPermission() async =>
      await channel.invokeMethod<bool>('requestPermission') ?? false;
  @override
  Future<ApplicationUpdateInstallationResult> install({
    required String version,
    required String attemptId,
  }) async => ApplicationUpdateInstallationResult.fromJson(
    (await channel.invokeMapMethod<dynamic, dynamic>('install', {
      'version': version,
      'attemptId': attemptId,
    }))!,
  );
  @override
  Future<ApplicationUpdateInstallationResult> installationStatus({
    required String attemptId,
  }) async => ApplicationUpdateInstallationResult.fromJson(
    (await channel.invokeMapMethod<dynamic, dynamic>('installationStatus', {
      'attemptId': attemptId,
    }))!,
  );
}
