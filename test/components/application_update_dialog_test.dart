import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:venera_next/components/application_update_dialog.dart';
import 'package:venera_next/components/application_update_prompt.dart';
import 'package:venera_next/foundation/application_update_service.dart';
import 'package:venera_next/foundation/application_update_download.dart';
import 'package:venera_next/foundation/application_update_release.dart';

import '../support/application_update_adapter.dart';

class FakeDownload extends ApplicationUpdateDownload {
  FakeDownload()
    : super(
        cacheRoot: '/unused',
        repository: 'owner/repo',
        dioFactory: Dio.new,
      );
  bool supported = true;
  int cleared = 0;
  int downloads = 0;
  int installations = 0;
  int reopened = 0;
  int cancelledInstallations = 0;
  Completer<void>? cleanup;
  @override
  Future<void> reopenConfirmation() async {
    reopened++;
    awaitingConfirmation = false;
    notifyListeners();
  }

  @override
  Future<void> cancelInstallation() async {
    cancelledInstallations++;
    state = ApplicationUpdateDownloadState.ready;
    awaitingConfirmation = false;
    error = 'Installation cancelled';
    notifyListeners();
  }

  @override
  bool get isSupported => supported;
  @override
  Future<void> initialize() async {}
  @override
  Future<void> cancelAndClear() async {
    cleared++;
    await cleanup?.future;
    state = ApplicationUpdateDownloadState.idle;
    candidate = null;
    notifyListeners();
  }

  @override
  Future<void> download(ApplicationUpdateRelease release) async {
    downloads++;
    candidate = release;
    state = ApplicationUpdateDownloadState.downloading;
    notifyListeners();
  }

  @override
  Future<void> install() async {
    installations++;
    state = ApplicationUpdateDownloadState.installing;
    notifyListeners();
  }
}

void main() {
  final release = ApplicationUpdateRelease(
    version: '2.0.0',
    notes: 'Release notes',
    pageUrl: 'https://github.com/owner/repo/releases/tag/v2.0.0',
    asset: ApplicationUpdateAsset(
      name: 'Leaf-2.0.0-20-release-arm64-v8a.apk',
      url: Uri.parse(
        'https://github.com/owner/repo/releases/download/v2.0.0/Leaf.apk',
      ),
      size: 1024 * 1024,
      sha256: '0' * 64,
    ),
  );
  Future<void> show(
    WidgetTester tester,
    FakeDownload download,
    VoidCallback close, {
    ApplicationUpdateRelease? candidate,
  }) => tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: ApplicationUpdateDialog(
          download: download,
          release: candidate ?? release,
          releasePageUrl: release.pageUrl,
          onClose: close,
        ),
      ),
    ),
  );

  ApplicationUpdateService availableService({
    VoidCallback? onRequest,
  }) => ApplicationUpdateService(
    currentVersion: () => '1.0.0',
    releaseRepository: 'owner/repo',
    createClient: () {
      onRequest?.call();
      final adapter = ApplicationUpdateAdapter()..released.complete();
      adapter.complete({
        'tag_name': 'v2.0.0',
        'assets': [
          {
            'name': release.asset!.name,
            'browser_download_url':
                'https://github.com/owner/repo/releases/download/v2.0.0/${release.asset!.name}',
            'size': release.asset!.size,
            'state': 'uploaded',
            'digest': 'sha256:${release.asset!.sha256}',
          },
        ],
      });
      return Dio()..httpClientAdapter = adapter;
    },
  );

  testWidgets(
    'manual check retires delayed startup before owning the download',
    (tester) async {
      final nav = GlobalKey<NavigatorState>();
      late BuildContext page;
      final download = FakeDownload();
      final service = availableService();
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: nav,
          home: Builder(
            builder: (context) {
              page = context;
              return const Scaffold(body: Text('Home'));
            },
          ),
        ),
      );
      final startup = ApplicationUpdatePrompt(
        context: nav.currentState!.overlay!.context,
        service: service,
        download: download,
      );
      final started = startup.check(
        silent: true,
        delay: const Duration(seconds: 2),
      );
      await tester.pump();
      final manual = ApplicationUpdatePrompt(
        context: page,
        service: service,
        download: download,
      );
      final checked = manual.check();
      await tester.pumpAndSettle();
      expect(
        find.byType(ApplicationUpdateDialog, skipOffstage: false),
        findsOneWidget,
      );
      await tester.tap(find.text('Update now'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();
      expect(
        find.byType(ApplicationUpdateDialog, skipOffstage: false),
        findsOneWidget,
      );
      await startup.closeAndWait();
      expect(download.state, ApplicationUpdateDownloadState.downloading);
      expect(download.cleared, 0);
      final closing = manual.closeAndWait();
      await tester.pumpAndSettle();
      await Future.wait([started, checked, closing]);
      await service.closeAndWait();
    },
  );

  for (final silent in [false, true]) {
    testWidgets(
      '${silent ? 'startup' : 'manual'} consumer cannot replace a displayed update or clear its download',
      (tester) async {
        final nav = GlobalKey<NavigatorState>();
        final download = FakeDownload();
        var requests = 0;
        var manualAdmissions = 0;
        final service = availableService(onRequest: () => requests++);
        await tester.pumpWidget(
          MaterialApp(
            navigatorKey: nav,
            home: const Scaffold(body: Text('Home')),
          ),
        );
        final context = nav.currentState!.overlay!.context;
        final owner = ApplicationUpdatePrompt(
          context: context,
          service: service,
          download: download,
        );
        final owning = owner.check(silent: true);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Update now'));
        await tester.pump();
        final consumer = ApplicationUpdatePrompt(
          context: context,
          service: service,
          download: download,
          onManualCheck: () async {
            manualAdmissions++;
          },
        );
        final joining = consumer.check(silent: silent);
        await tester.pumpAndSettle();
        expect(manualAdmissions, silent ? 0 : 1);
        expect(requests, 1);
        expect(
          find.byType(ApplicationUpdateDialog, skipOffstage: false),
          findsOneWidget,
        );
        final retired = consumer.closeAndWait();
        await tester.pumpAndSettle();
        await Future.wait([joining, retired]);
        expect(download.state, ApplicationUpdateDownloadState.downloading);
        expect(download.cleared, 0);
        final closing = owner.closeAndWait();
        await tester.pumpAndSettle();
        await Future.wait([owning, closing]);
        await service.closeAndWait();
      },
    );
  }

  for (final silent in [false, true]) {
    for (final updateNow in [false, true]) {
      testWidgets(
        '${silent ? 'startup' : 'manual'} discovery shares update/later actions (${updateNow ? 'update' : 'later'})',
        (tester) async {
          final download = FakeDownload();
          var attempts = 0;
          var requests = 0;
          final service = ApplicationUpdateService(
            currentVersion: () => '1.0.0',
            releaseRepository: 'owner/repo',
            createClient: () {
              requests++;
              final adapter = ApplicationUpdateAdapter()..released.complete();
              adapter.complete({
                'tag_name': 'v2.0.0',
                'body': 'Release notes',
                'assets': [
                  {
                    'name': release.asset!.name,
                    'browser_download_url':
                        'https://github.com/owner/repo/releases/download/v2.0.0/${release.asset!.name}',
                    'size': release.asset!.size,
                    'state': 'uploaded',
                    'digest': 'sha256:${release.asset!.sha256}',
                  },
                ],
              });
              return Dio()..httpClientAdapter = adapter;
            },
          );
          ApplicationUpdatePrompt? prompt;
          Future<void>? checking;
          await tester.pumpWidget(
            MaterialApp(
              home: ApplicationUpdateScope(
                service: service,
                download: download,
                onManualCheck: () async {
                  attempts++;
                },
                child: Scaffold(
                  body: Builder(
                    builder: (context) => TextButton(
                      onPressed: () {
                        prompt = ApplicationUpdatePrompt(
                          context: context,
                          service: service,
                        );
                        checking = prompt!.check(silent: silent);
                      },
                      child: const Text('Discover'),
                    ),
                  ),
                ),
              ),
            ),
          );
          await tester.tap(find.text('Discover'));
          await tester.pumpAndSettle();
          expect(attempts, silent ? 0 : 1);
          expect(requests, 1);
          expect(find.text('Update now'), findsOneWidget);
          expect(find.text('Update later'), findsOneWidget);
          expect(find.text('Open release page'), findsNothing);
          expect(download.downloads, 0);
          expect(download.installations, 0);
          await tester.tap(
            find.text(updateNow ? 'Update now' : 'Update later'),
          );
          await tester.pumpAndSettle();
          if (updateNow) {
            expect(download.downloads, 1);
            expect(download.installations, 0);
            expect(find.text('Cancel download'), findsOneWidget);
          } else {
            await checking;
            expect(find.byType(ApplicationUpdateDialog), findsNothing);
            expect(download.downloads, 0);
            expect(download.installations, 0);
            // Deferring does not permanently dismiss this version.
            await tester.tap(find.text('Discover'));
            await tester.pumpAndSettle();
            expect(requests, 2);
            expect(find.text('Update now'), findsOneWidget);
          }
          final closing = prompt!.closeAndWait();
          await tester.pumpAndSettle();
          await closing;
          await checking;
          await service.closeAndWait();
        },
      );
    }
  }

  testWidgets(
    'recovered package is shown offline through scope and closing joins cleanup',
    (tester) async {
      final download = FakeDownload()
        ..state = ApplicationUpdateDownloadState.ready
        ..candidate = release;
      var requests = 0;
      final service = ApplicationUpdateService(
        createClient: () {
          requests++;
          throw StateError('offline');
        },
        currentVersion: () => '1.0.0',
      );
      ApplicationUpdatePrompt? prompt;
      Future<void>? checking;
      await tester.pumpWidget(
        MaterialApp(
          home: ApplicationUpdateScope(
            service: service,
            download: download,
            child: Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  onPressed: () {
                    prompt = ApplicationUpdatePrompt(
                      context: context,
                      service: service,
                    );
                    checking = prompt!.check();
                  },
                  child: const Text('Check'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Check'));
      await tester.pumpAndSettle();
      expect(find.text('Install update'), findsOneWidget);
      expect(requests, 0);
      download.cleanup = Completer<void>();
      var finished = false;
      final closing = prompt!.closeAndWait().then((_) => finished = true);
      await tester.pump();
      expect(finished, isFalse);
      expect(download.cleared, 1);
      download.cleanup!.complete();
      await tester.pumpAndSettle();
      await closing;
      await checking;
      expect(finished, isTrue);
      expect(find.byType(ApplicationUpdateDialog), findsNothing);
      await service.closeAndWait();
    },
  );

  testWidgets('shows release details and joins download cleanup before close', (
    tester,
  ) async {
    final download = FakeDownload();
    var closed = false;
    await show(tester, download, () => closed = true);
    expect(find.text('Version 2.0.0'), findsOneWidget);
    expect(find.text('Release notes'), findsOneWidget);
    expect(find.text('Package size: 1.0 MB'), findsOneWidget);
    await tester.tap(find.text('Update now'));
    await tester.pump();
    expect(download.downloads, 1);
    download.cleanup = Completer<void>();
    await tester.tap(find.text('Cancel download'));
    await tester.pump();
    expect(download.cleared, 1);
    expect(closed, isFalse);
    download.cleanup!.complete();
    await tester.pump();
    expect(closed, isTrue);
  });

  for (final state in [
    ApplicationUpdateDownloadState.installing,
    ApplicationUpdateDownloadState.blocked,
  ]) {
    testWidgets('$state closes without clearing installer package', (
      tester,
    ) async {
      final download = FakeDownload()..state = state;
      var closed = false;
      await show(tester, download, () => closed = true);
      expect(find.text('Update now'), findsNothing);
      expect(find.text('Install update'), findsNothing);
      await tester.tap(find.text('Close'));
      await tester.pump();
      expect(closed, isTrue);
      expect(download.cleared, 0);
    });
  }
  testWidgets(
    'verified package offers installation and preserves permission round trip',
    (tester) async {
      final download = FakeDownload()
        ..state = ApplicationUpdateDownloadState.ready;
      await show(tester, download, () {});
      await tester.tap(find.text('Install update'));
      await tester.pump();
      expect(download.installations, 1);
      expect(download.cleared, 0);
      expect(find.text('Install update'), findsNothing);
    },
  );
  testWidgets('debug build and invalid digest explain manual fallback', (
    tester,
  ) async {
    final download = FakeDownload()..supported = false;
    await show(tester, download, () {});
    expect(find.text('Update now'), findsNothing);
    expect(find.text('Open release page'), findsOneWidget);
    expect(find.textContaining('unavailable for this build'), findsOneWidget);
    download.supported = true;
    await show(
      tester,
      download,
      () {},
      candidate: const ApplicationUpdateRelease(
        version: '2.0.0',
        notes: '',
        pageUrl: '',
        assetError: ApplicationUpdateRelease.assetInvalidDigest,
      ),
    );
    expect(
      find.text('The release package has no valid SHA-256 digest'),
      findsOneWidget,
    );
    expect(find.text('Update now'), findsNothing);
  });
  testWidgets('failed download retains release for explicit retry', (
    tester,
  ) async {
    final download = FakeDownload()
      ..state = ApplicationUpdateDownloadState.failed
      ..error = 'Update download or verification failed';
    await show(tester, download, () {});
    await tester.tap(find.text('Retry download'));
    await tester.pump();
    expect(download.downloads, 1);
    expect(download.candidate?.version, '2.0.0');
  });
  testWidgets('failed installation shows system reason and retries install', (
    tester,
  ) async {
    final download = FakeDownload()
      ..candidate = release
      ..state = ApplicationUpdateDownloadState.ready
      ..error = 'Installation failed'
      ..errorDetail = 'INSTALL_FAILED_UPDATE_INCOMPATIBLE: signatures differ';
    await show(tester, download, () {});
    expect(find.text('Installation failed'), findsOneWidget);
    expect(
      find.text('INSTALL_FAILED_UPDATE_INCOMPATIBLE: signatures differ'),
      findsOneWidget,
    );
    expect(find.text('Update now'), findsNothing);
    await tester.tap(find.text('Install update'));
    await tester.pump();
    expect(download.installations, 1);
    expect(download.downloads, 0);
  });
  testWidgets('left confirmation offers reopen and cancel without relaunch', (
    tester,
  ) async {
    final download = FakeDownload()
      ..candidate = release
      ..state = ApplicationUpdateDownloadState.installing;
    await show(tester, download, () {});
    expect(find.text('Reopen installation confirmation'), findsNothing);
    download
      ..awaitingConfirmation = true
      ..notifyListeners();
    await tester.pump();
    expect(
      find.textContaining('installation prompt was closed'),
      findsOneWidget,
    );
    await tester.tap(find.text('Reopen installation confirmation'));
    await tester.pump();
    expect(download.reopened, 1);
    expect(find.text('Reopen installation confirmation'), findsNothing);
    download
      ..awaitingConfirmation = true
      ..notifyListeners();
    await tester.pump();
    await tester.tap(find.text('Cancel installation'));
    await tester.pump();
    expect(download.cancelledInstallations, 1);
    expect(download.cleared, 0);
    expect(find.text('Install update'), findsOneWidget);
  });
}
