import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:venera_next/foundation/application_update_installer.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('leaf/application_update');
  const installer = MethodChannelApplicationUpdateInstaller();
  final calls = <MethodCall>[];
  setUp(() {
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          switch (call.method) {
            case 'current':
              return {
                'packageName': 'leaf',
                'versionCode': 1,
                'versionName': '1.0.0',
                'debug': false,
                'installationPending': true,
                'attemptId': 'attempt',
                'awaitingConfirmation': true,
              };
            case 'inspect':
              return {
                'versionCode': 2,
                'versionName': '2.0.0',
                'installedVersionCode': 1,
              };
            case 'reopenConfirmation':
            case 'cancelInstallation':
              return null;
            case 'canInstall':
            case 'requestPermission':
              return true;
            case 'install':
              return {
                'attemptId': (call.arguments as Map)['attemptId'],
                'status': 'failed',
                'message': 'INSTALL_FAILED_INSUFFICIENT_STORAGE',
              };
            case 'installationStatus':
              return {
                'attemptId': (call.arguments as Map)['attemptId'],
                'status': 'cancelled',
              };
          }
          throw MissingPluginException();
        });
  });
  tearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null),
  );
  test('bridge uses fixed paths and correlated attempt identity', () async {
    expect((await installer.current()).debug, false);
    expect((await installer.current()).installationPending, true);
    expect((await installer.current()).attemptId, 'attempt');
    expect((await installer.current()).awaitingConfirmation, true);
    expect((await installer.inspect(partial: true)).versionCode, 2);
    expect(calls.last.arguments, {'partial': true});
    expect(await installer.canInstall(), true);
    expect(await installer.requestPermission(), true);
    final installed = await installer.install(
      version: '2.0.0',
      attemptId: 'one',
    );
    expect(installed.attemptId, 'one');
    expect(installed.message, 'INSTALL_FAILED_INSUFFICIENT_STORAGE');
    expect(calls.last.arguments, {'version': '2.0.0', 'attemptId': 'one'});
    final status = await installer.installationStatus(attemptId: 'one');
    expect(status.status, 'cancelled');
    // Older bridges send no message field.
    expect(status.message, isNull);
  });
  test('native confirmation notices and actions carry the attempt', () async {
    final notices = <String>[];
    final subscription = installer.awaitingConfirmation.listen(notices.add);
    addTearDown(subscription.cancel);
    await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage(
          channel.name,
          channel.codec.encodeMethodCall(
            const MethodCall('awaitingConfirmation', {'attemptId': 'one'}),
          ),
          (_) {},
        );
    expect(notices, ['one']);
    await installer.reopenConfirmation(attemptId: 'one');
    expect(calls.last.method, 'reopenConfirmation');
    expect(calls.last.arguments, {'attemptId': 'one'});
    await installer.cancelInstallation(attemptId: 'one');
    expect(calls.last.method, 'cancelInstallation');
  });
}
