import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:venera_next/features/favorites/favorites_manager.dart';
import 'package:venera_next/features/local_comics/local.dart';
import 'package:venera_next/features/local_comics/local_comics_summary.dart';
import 'package:venera_next/foundation/app.dart';
import 'package:venera_next/routing/app_navigation.dart';

void main() {
  late Directory root;

  setUp(() async {
    root = Directory.systemTemp.createTempSync('local-summary-');
    App.dataPath = root.path;
    App.cachePath = root.path;
    LocalManager.current?.dispose();
    LocalManager(initializeSources: () async {});
  });
  tearDown(() async {
    await LocalFavoritesManager().closeAndWait();
    await LocalManager().pendingDownloadTaskWrites;
    LocalManager.current?.dispose();
    root.deleteSync(recursive: true);
  });

  testWidgets('the import dialog offers no option to skip copying', (
    tester,
  ) async {
    await tester.runAsync(() async {
      await LocalManager().init();
      await LocalFavoritesManager().init();
    });
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: appNavigation.rootNavigatorKey,
        // The test font is wider than the fixed-width help button.
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(0.5)),
          child: child!,
        ),
        home: const Scaffold(
          body: CustomScrollView(slivers: [LocalComicsSummary()]),
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.text('Import'));
    await tester.pumpAndSettle();
    expect(find.text('Import Comics'), findsOneWidget);
    // Every folder-based method imports a copy into the library.
    for (final method in [
      'Single Comic',
      'Multiple Comics',
      'EhViewer downloads',
    ]) {
      await tester.tap(find.text(method));
      await tester.pumpAndSettle();
      expect(find.byType(CheckboxListTile), findsNothing, reason: method);
      expect(find.text('Copy to app local path'), findsNothing);
    }
  });
}
