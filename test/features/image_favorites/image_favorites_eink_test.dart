import 'dart:ui' as ui;
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:venera_next/features/history/image_favorites.dart';
import 'package:venera_next/features/history/image_favorites_provider.dart';
import 'package:venera_next/components/gesture.dart';
import 'package:venera_next/features/image_favorites/image_favorites_item.dart';
import 'package:venera_next/features/image_favorites/image_favorites_gallery_page.dart';
import 'package:venera_next/foundation/app.dart';
import 'package:venera_next/foundation/eink_theme.dart';
import '../history/image_favorites_repository_test.dart' show comic;

class _Images extends ChangeNotifier implements ImageFavoriteManager {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  setUpAll(() {
    App.cachePath = Directory.systemTemp.path;
    App.dataPath = Directory.systemTemp.path;
  });
  for (final eink in [true, false]) {
    testWidgets('real favorite thumbnails and selection eink=$eink', (
      tester,
    ) async {
      final root = Directory.systemTemp.createTempSync('favorite-eink-');
      final oldCache = App.cachePath;
      App.cachePath = root.path;
      final manager = _Images();
      addTearDown(() {
        manager.dispose();
        App.cachePath = oldCache;
        root.deleteSync(recursive: true);
      });
      final model = comic('preview');
      final favorite = model.images.single;
      final recorder = ui.PictureRecorder();
      Canvas(
        recorder,
      ).drawRect(const Rect.fromLTWH(0, 0, 8, 8), Paint()..color = Colors.grey);
      final picture = recorder.endRecording();
      final image = (await tester.runAsync(() => picture.toImage(8, 8)))!;
      picture.dispose();
      PaintingBinding.instance.imageCache.putIfAbsent(
        ImageFavoritesProvider(favorite),
        () =>
            OneFrameImageStreamCompleter(Future.value(ImageInfo(image: image))),
      );
      addTearDown(() => PaintingBinding.instance.imageCache.clear());
      Widget app(Widget child) => MaterialApp(
        theme: eink ? applyEInkTheme(ThemeData.light()) : ThemeData.light(),
        builder: (_, child) => EInkReduceMotion(enabled: eink, child: child!),
        home: Scaffold(body: child),
      );
      void checkThumbnail() {
        final hero = find.byType(Hero);
        expect(hero, findsOneWidget);
        final containers = tester
            .widgetList<Container>(
              find.ancestor(of: hero, matching: find.byType(Container)),
            )
            .toList();
        final imageBox = containers.firstWhere(
          (c) => c.clipBehavior == Clip.antiAlias,
        );
        final decoration = imageBox.decoration! as BoxDecoration;
        expect(
          decoration.borderRadius,
          eink ? BorderRadius.zero : BorderRadius.circular(8),
        );
        final borders = containers
            .map((c) => c.foregroundDecoration)
            .whereType<BoxDecoration>()
            .map((d) => d.border)
            .whereType<Border>();
        if (eink) {
          expect(borders, hasLength(1));
          expect(borders.single.top.color, Colors.black);
          expect(borders.single.top.width, EInkStyle.strokeWidth);
        } else {
          expect(borders, isEmpty);
        }
      }

      var selected = 0;
      await tester.pumpWidget(
        app(
          ImageFavoritesItem(
            imageFavoritesComic: model,
            selectedImageFavorites: const {},
            addSelected: (_) => selected++,
            multiSelectMode: true,
          ),
        ),
      );
      await tester.pump();
      checkThumbnail();
      await tester.tap(
        find
            .ancestor(
              of: find.byType(Hero),
              matching: find.byType(ClickInkWell),
            )
            .first,
      );
      expect(selected, 1);
      await tester.pumpWidget(
        app(ImageFavoritesGalleryPage(comic: model, manager: manager)),
      );
      await tester.pump();
      checkThumbnail();
      await tester.tap(find.byIcon(Icons.checklist));
      await tester.pump();
      expect(find.byIcon(Icons.radio_button_unchecked), findsOneWidget);
      await tester.tap(
        find
            .ancestor(
              of: find.byType(Hero),
              matching: find.byType(ClickInkWell),
            )
            .first,
      );
      await tester.pump();
      expect(find.byIcon(Icons.check_circle), findsOneWidget);
      checkThumbnail();
      await tester.pumpWidget(const SizedBox());
      expect(tester.takeException(), isNull);
    });
  }
}
