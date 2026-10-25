import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:venera_next/foundation/appdata.dart';
import 'package:venera_next/foundation/comic_layout.dart';
import 'package:venera_next/foundation/reader_settings.dart';

void main() {
  test(
    'unavailable image policy defaults off and inherits validated scope settings',
    () {
      final defaults = ReaderSettings.resolve(global: {});
      expect(defaults.autoReadingSkipUnavailableImages, false);
      expect(defaults.autoReadingImageWaitSeconds, 10);
      final global = {
        'autoReadingSkipUnavailableImages': true,
        'autoReadingImageWaitSeconds': 20,
      };
      final device = {
        'enabled': true,
        'autoReadingSkipUnavailableImages': false,
        'autoReadingImageWaitSeconds': 30,
      };
      final comic = <String, Object?>{
        'enabled': true,
        'autoReadingSkipUnavailableImages': true,
        'autoReadingImageWaitSeconds': 70,
      };
      var settings = ReaderSettings.resolve(
        global: global,
        device: device,
        comic: comic,
      );
      expect(settings.autoReadingSkipUnavailableImages, true);
      expect(settings.autoReadingImageWaitSeconds, 60);
      comic['enabled'] = false;
      settings = ReaderSettings.resolve(
        global: global,
        device: device,
        comic: comic,
      );
      expect(settings.autoReadingSkipUnavailableImages, false);
      expect(settings.autoReadingImageWaitSeconds, 30);
      device['enabled'] = false;
      settings = ReaderSettings.resolve(
        global: global,
        device: device,
        comic: comic,
      );
      expect(settings.autoReadingSkipUnavailableImages, true);
      expect(settings.autoReadingImageWaitSeconds, 20);
      expect(
        ReaderSettings.resolve(
          global: {'autoReadingImageWaitSeconds': -1},
        ).autoReadingImageWaitSeconds,
        1,
      );
    },
  );

  test('Leaf reader information defaults and validates legacy settings', () {
    final defaults = ReaderSettings.resolve(global: {});
    expect(defaults.readerInformationMode, 'footer');
    expect(defaults.readerFooterHeight, 18.0);
    expect(defaults.readerFooterHeight, isA<double>());
    expect(defaults.readerFooterFontSize, 11.0);
    expect(defaults.readerFooterFontSize, isA<double>());
    expect(defaults.readerFooterShowChapter, isFalse);
    expect(defaults.showPageNumberInReader, isTrue);
    expect(defaults.enableClockAndBatteryInfoInReader, isTrue);

    // A v1.18.1 backup has only the legacy switches. They continue to decide
    // which contents appear when the new mode falls back to its default.
    final legacy = ReaderSettings.resolve(
      global: {
        'showPageNumberInReader': false,
        'enableClockAndBatteryInfoInReader': false,
      },
    );
    expect(legacy.readerInformationMode, 'footer');
    expect(legacy.showPageNumberInReader, isFalse);
    expect(legacy.enableClockAndBatteryInfoInReader, isFalse);

    final invalid = ReaderSettings.resolve(
      global: {
        'readerInformationMode': 'unknown',
        'readerFooterHeight': 'large',
        'readerFooterFontSize': double.infinity,
        'readerFooterShowChapter': 'yes',
      },
    );
    expect(invalid.readerInformationMode, 'footer');
    expect(invalid.readerFooterHeight, 18.0);
    expect(invalid.readerFooterFontSize, 11.0);
    expect(invalid.readerFooterShowChapter, isFalse);

    final bounded = ReaderSettings.resolve(
      global: {'readerFooterHeight': 36, 'readerFooterFontSize': 14},
    );
    expect(bounded.readerFooterHeight, 25.0);
    expect(bounded.readerFooterFontSize, 13.0);

    final minimum = ReaderSettings.resolve(
      global: {'readerFooterHeight': 14, 'readerFooterFontSize': 8},
    );
    expect(minimum.readerFooterHeight, 15.0);
    expect(minimum.readerFooterFontSize, 9.0);
  });

  test(
    'Leaf reader information settings inherit global, device, and comic',
    () {
      final global = {
        'readerInformationMode': 'overlay',
        'readerFooterHeight': 22,
        'readerFooterFontSize': 12,
        'readerFooterShowChapter': true,
      };
      final device = {
        'enabled': true,
        'readerInformationMode': 'hidden',
        'readerFooterHeight': 24,
        'readerFooterFontSize': 10,
        'readerFooterShowChapter': false,
      };
      final comic = <String, Object?>{
        'enabled': true,
        'readerInformationMode': 'footer',
        'readerFooterHeight': 25,
      };

      var resolved = ReaderSettings.resolve(
        global: global,
        device: device,
        comic: comic,
      );
      expect(resolved.readerInformationMode, 'footer');
      expect(resolved.readerFooterHeight, 25.0);
      expect(resolved.readerFooterFontSize, 10.0);
      expect(resolved.readerFooterShowChapter, isFalse);

      comic['enabled'] = false;
      resolved = ReaderSettings.resolve(
        global: global,
        device: device,
        comic: comic,
      );
      expect(resolved.readerInformationMode, 'hidden');
      expect(resolved.readerFooterHeight, 24.0);
      expect(resolved.readerFooterFontSize, 10.0);
      expect(resolved.readerFooterShowChapter, isFalse);

      device['enabled'] = false;
      resolved = ReaderSettings.resolve(
        global: global,
        device: device,
        comic: comic,
      );
      expect(resolved.readerInformationMode, 'overlay');
      expect(resolved.readerFooterHeight, 22.0);
      expect(resolved.readerFooterFontSize, 12.0);
      expect(resolved.readerFooterShowChapter, isTrue);
    },
  );

  test('scope precedence skips nulls and disabled overrides', () {
    final global = {'readerSideMargin': 5, 'limitImageWidth': true};
    final device = {'enabled': true, 'readerSideMargin': 10};
    final comic = <String, Object?>{'enabled': true, 'readerSideMargin': 20};
    expect(
      ReaderSettings.resolve(
        global: global,
        device: device,
        comic: comic,
      ).readerSideMargin,
      20,
    );
    comic['readerSideMargin'] = null;
    expect(
      ReaderSettings.resolve(
        global: global,
        device: device,
        comic: comic,
      ).readerSideMargin,
      10,
    );
    device['enabled'] = false;
    expect(
      ReaderSettings.resolve(
        global: global,
        device: device,
        comic: comic,
      ).readerSideMargin,
      5,
    );
  });

  test(
    'manual comic mode and automatic device mode keep independent scopes',
    () {
      final global = {
        'autoReaderMode': true,
        'pagedReaderMode': 'galleryRightToLeft',
      };
      final comic = <String, Object?>{
        'enabled': false,
        'readerModeOverride': 'galleryTopToBottom',
      };
      expect(
        ReaderSettings.resolve(
          global: global,
          comic: comic,
          layout: ComicLayout.paged,
        ).readerMode,
        'galleryTopToBottom',
      );
      comic['readerModeOverride'] = 'default';
      expect(
        ReaderSettings.resolve(
          global: global,
          comic: comic,
          layout: ComicLayout.paged,
        ).readerMode,
        'galleryRightToLeft',
      );
    },
  );

  test('legacy long press action inherits at each enabled scope', () {
    final global = {'enableLongPressToZoom': true};
    final device = {'enabled': true, 'enableLongPressToZoom': false};
    final comic = <String, Object?>{
      'enabled': true,
      'longPressAction': 'autoReading',
    };
    expect(
      ReaderSettings.resolve(
        global: global,
        device: device,
        comic: comic,
      ).longPressAction,
      'autoReading',
    );
    comic['longPressAction'] = null;
    expect(
      ReaderSettings.resolve(
        global: global,
        device: device,
        comic: comic,
      ).longPressAction,
      'none',
    );
  });

  test(
    'invalid numeric and enum values cannot escape into reading policies',
    () {
      final settings = ReaderSettings.resolve(
        global: {
          'readerSideMargin': 500,
          'autoScrollSpeed': double.nan,
          'eInkRefreshInterval': -5,
          'readerScreenPicNumberForPortrait': 'broken',
          'readerMode': 'unknown',
          'longPressZoomPosition': 3,
        },
      );
      expect(settings.readerSideMargin, 30);
      expect(settings.autoScrollSpeed, 80);
      expect(settings.eInkRefreshInterval, 1);
      expect(settings.readerScreenPicNumberForPortrait, 1);
      expect(settings.readerMode, 'waterfallTopToBottom');
      expect(settings.longPressZoomPosition, 'press');
    },
  );

  test('snapshot neither changes persistence nor follows later mutations', () {
    final global = <String, Object?>{
      'autoScrollSpeed': 120,
      'unknownField': 'keep',
    };
    final before = jsonEncode(global);
    final snapshot = ReaderSettings.resolve(global: global);
    expect(jsonEncode(global), before);
    global['autoScrollSpeed'] = 240;
    expect(snapshot.autoScrollSpeed, 120);
    expect(global['unknownField'], 'keep');
  });

  test(
    'stored settings adapter agrees with legacy precedence and stays live',
    () {
      final settings = appdata.settings;
      final previous =
          jsonDecode(jsonEncode(appdata.toJson()['settings'])) as Map;
      addTearDown(
        () => previous.forEach((key, value) => settings[key] = value),
      );
      settings['deviceId'] = 'snapshot-test';
      settings['comicSpecificSettings'] = <String, dynamic>{};
      settings['deviceSpecificSettings'] = <String, dynamic>{};
      settings['autoScrollSpeed'] = 100;
      for (final enabled in [false, true]) {
        settings.setEnabledDeviceSpecificSettings(enabled);
        settings.setDeviceReaderSetting('autoScrollSpeed', 200);
        settings.setEnabledComicSpecificSettings('comic', 'source', enabled);
        settings.setReaderSetting('comic', 'source', 'autoScrollSpeed', 300);
        expect(
          settings.readerSettings('comic', 'source').autoScrollSpeed,
          settings.getReaderSetting('comic', 'source', 'autoScrollSpeed'),
        );
      }
    },
  );
}
