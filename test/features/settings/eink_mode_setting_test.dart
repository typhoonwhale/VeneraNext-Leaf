import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:venera_next/features/settings/appearance.dart';
import 'package:venera_next/foundation/app.dart';
import 'package:venera_next/foundation/appdata.dart';
import 'package:venera_next/foundation/context.dart';

Future<void> _flush(WidgetTester tester, Future<void> operation) async {
  var done = false;
  Object? error;
  operation.then(
    (_) => done = true,
    onError: (Object e) {
      done = true;
      error = e;
    },
  );
  for (var i = 0; i < 500 && !done; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump();
  }
  expect(done, isTrue);
  expect(error, isNull);
  await tester.pump();
}

Map _saved(Directory root) =>
    (jsonDecode(File('${root.path}/appdata.json').readAsStringSync())
            as Map)['settings']
        as Map;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  App.dataPath = Directory.systemTemp.path;

  testWidgets('T6 switch persists and locks the theme choices', (tester) async {
    final root = Directory.systemTemp.createTempSync('eink-setting-');
    final previous =
        jsonDecode(jsonEncode(appdata.toJson()['settings'])) as Map;
    final previousPath = App.dataPath;
    App.dataPath = root.path;
    appdata.settings['disableSyncFields'] = '';
    appdata.settings['language'] = 'en-US';
    appdata.settings['theme_mode'] = 'dark';
    appdata.settings['color'] = 'orange';
    appdata.settings['eInkMode'] = true;
    registerShowMessageHandler((_, _) {});
    addTearDown(() {
      previous.forEach((key, value) => appdata.settings[key] = value);
      App.dataPath = previousPath;
      root.deleteSync(recursive: true);
    });
    await tester.binding.setSurfaceSize(const Size(500, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final before = Map<String, dynamic>.of(
      jsonDecode(jsonEncode(appdata.toJson()['settings']))
          as Map<String, dynamic>,
    );

    Widget host() => MaterialApp(home: Scaffold(body: AppearanceSettings()));
    // The page re-reads the preference when the app rebuilds.
    final rebuild = ValueNotifier(0);
    await tester.pumpWidget(
      ValueListenableBuilder<int>(
        valueListenable: rebuild,
        builder: (_, _, _) => host(),
      ),
    );
    expect(find.text('E-Ink mode'), findsOneWidget);
    expect(
      find.text('Fixed to black and white in E-Ink mode'),
      findsNWidgets(2),
    );
    final tiles = tester.widgetList<ListTile>(find.byType(ListTile)).toList();
    expect(tiles.where((t) => !t.enabled), hasLength(2));
    final toggle = find.byType(Switch);
    expect(tester.widget<Switch>(toggle).value, isTrue);

    tester.widget<Switch>(toggle).onChanged!(false);
    await _flush(tester, Future<void>.value());
    for (var i = 0; i < 50 && _savedOrNull(root)?['eInkMode'] != false; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
    }
    expect(_saved(root)['eInkMode'], isFalse);
    expect(appdata.settings['eInkMode'], isFalse);
    // Only the switch's own key changed; stored theme choices are untouched.
    expect(_saved(root)['theme_mode'], 'dark');
    expect(_saved(root)['color'], 'orange');
    for (final key in before.keys) {
      if (key == 'eInkMode') continue;
      expect(
        jsonEncode(_saved(root)[key]),
        jsonEncode(before[key]),
        reason: key,
      );
    }
    expect(
      _saved(root).keys.where(
        (k) =>
            k.startsWith('readerFooter') ||
            k.startsWith('eInkRefresh') ||
            k == 'enablePageAnimation',
      ),
      everyElement(
        predicate(
          (String k) => jsonEncode(_saved(root)[k]) == jsonEncode(before[k]),
        ),
      ),
    );

    rebuild.value++;
    await tester.pump();
    expect(find.text('Fixed to black and white in E-Ink mode'), findsNothing);
    expect(
      tester
          .widgetList<ListTile>(find.byType(ListTile))
          .where((t) => !t.enabled),
      isEmpty,
    );

    await _flush(tester, appdata.loadDataForTesting(root.path));
    expect(appdata.settings['eInkMode'], isFalse);
    await tester.pumpWidget(const SizedBox());
  });
}

Map? _savedOrNull(Directory root) {
  final file = File('${root.path}/appdata.json');
  if (!file.existsSync()) return null;
  try {
    return (jsonDecode(file.readAsStringSync()) as Map)['settings'] as Map;
  } catch (_) {
    return null;
  }
}
