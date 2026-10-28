import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:venera_next/foundation/app.dart';
import 'package:venera_next/foundation/app_data_sync_fields.dart';
import 'package:venera_next/foundation/appdata.dart';
import 'package:venera_next/foundation/application_configuration.dart';
import 'package:venera_next/foundation/application_preferences.dart';
import 'package:venera_next/foundation/eink_theme.dart';
import 'package:venera_next/foundation/global_preference_store.dart';

void main() {
  App.dataPath = Directory.systemTemp.path;
  test('T5 E-Ink mode defaults on and rejects non-bool values', () {
    expect(AppearanceConfiguration.read((_) => null).eInkMode, isTrue);
    for (final bad in [1, 'false', 0, <Object>[], 'true']) {
      expect(
        AppearanceConfiguration.read((_) => bad).eInkMode,
        isTrue,
        reason: '$bad',
      );
    }
    expect(AppearanceConfiguration.read((_) => false).eInkMode, isFalse);
    final on = AppearanceConfiguration.read((_) => true);
    expect(on.einkTheme, isTrue);
    expect(on.reduceMotion, isTrue);
    final off = AppearanceConfiguration.read((_) => false);
    expect(off.einkTheme, isFalse);
    expect(off.reduceMotion, isFalse);
    expect(AppearancePreferences.all, contains(AppearancePreferences.eInkMode));
    expect(applicationPreferenceDefaults['eInkMode'], isTrue);
    expect(GlobalPreferenceStore(appdata.settings).appearance.eInkMode, isTrue);
  });

  group('persisted state', () {
    late Directory dir;
    late AppdataImportCheckpoint checkpoint;
    final previousPath = Directory.systemTemp.path;

    setUp(() {
      dir = Directory.systemTemp.createTempSync('venera-eink-pref-');
      checkpoint = appdata.captureImportCheckpoint();
      App.dataPath = dir.path;
      appdata.settings['disableSyncFields'] = '';
    });

    tearDown(() async {
      await appdata.restoreImportCheckpoint(checkpoint, persist: false);
      App.dataPath = previousPath;
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    });

    test('T7 upgrade from a file without the key turns the mode on', () async {
      File(p.join(dir.path, 'appdata.json')).writeAsStringSync(
        jsonEncode({
          'settings': {'theme_mode': 'dark', 'color': 'orange'},
          'searchHistory': <String>[],
        }),
      );
      await appdata.loadDataForTesting(dir.path);
      final appearance = GlobalPreferenceStore(appdata.settings).appearance;
      expect(appearance.eInkMode, isTrue);
      expect(EInkPreferences.einkTheme, isTrue);
      expect(EInkPreferences.reduceMotion, isTrue);
      expect(appdata.settings['theme_mode'], 'dark');
      expect(appdata.settings['color'], 'orange');
    });

    test('T7 a stored false survives a reload', () async {
      File(p.join(dir.path, 'appdata.json')).writeAsStringSync(
        jsonEncode({
          'settings': {'eInkMode': false, 'theme_mode': 'light'},
          'searchHistory': <String>[],
        }),
      );
      await appdata.loadDataForTesting(dir.path);
      expect(EInkPreferences.einkTheme, isFalse);
      expect(EInkPreferences.reduceMotion, isFalse);
      expect(appdata.settings['theme_mode'], 'light');
    });

    test(
      'T8 import neither flips nor receives the local E-Ink choice',
      () async {
        expect(appDataLocalFields, contains('eInkMode'));
        appdata.settings['eInkMode'] = false;
        await appdata.syncData({
          'settings': {'theme_mode': 'dark'},
          'searchHistory': <String>[],
        });
        expect(appdata.settings['eInkMode'], isFalse);
        expect(appdata.settings['theme_mode'], 'dark');
        await appdata.syncData({
          'settings': {'eInkMode': true},
          'searchHistory': <String>[],
        });
        expect(appdata.settings['eInkMode'], isFalse);
        appdata.settings['eInkMode'] = true;
        await appdata.syncData({
          'settings': {'eInkMode': false},
          'searchHistory': <String>[],
        });
        expect(appdata.settings['eInkMode'], isTrue);
      },
    );
  });
}
