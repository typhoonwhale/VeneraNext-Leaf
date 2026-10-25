import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:venera_next/components/application_update_dialog.dart';
import 'package:venera_next/components/application_update_prompt.dart';
import 'package:venera_next/foundation/application_update_service.dart';
import 'package:venera_next/foundation/application_update_download.dart';
import 'package:venera_next/foundation/application_update_release.dart';

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
  Completer<void>? cleanup;
  @override
  bool get isSupported => supported;
  @override
  Future<void> initialize() async {}
  @override
  Future<void> cancelAndClear() async {
    cleared++;
    await cleanup?.future;
    state = ApplicationUpdateDownloadState.idle;
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
    await tester.tap(find.text('Download update'));
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
      expect(find.text('Download update'), findsNothing);
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
    expect(find.text('Download update'), findsNothing);
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
    expect(find.text('Download update'), findsNothing);
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
}
