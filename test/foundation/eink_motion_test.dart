import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:venera_next/components/loading.dart';
import 'package:venera_next/components/menu.dart';
import 'package:venera_next/components/message.dart';
import 'package:venera_next/components/pop_up_widget.dart';
import 'package:venera_next/foundation/app_page_route.dart';
import 'package:venera_next/foundation/appdata.dart';
import 'package:venera_next/foundation/eink_theme.dart';
import 'package:venera_next/foundation/res.dart';
import 'package:venera_next/network/request_scope.dart';

/// Mirrors the structure `MaterialApp.builder` in main.dart uses for
/// `reduceMotion`.
Widget _app(Widget home) => MaterialApp(
  builder: (context, child) =>
      EInkReduceMotion(enabled: EInkPreferences.reduceMotion, child: child!),
  home: home,
);

/// One more frame may flush bookkeeping after the content is visible, but no
/// ticker may keep scheduling frames after that.
Future<void> _expectIdle(WidgetTester tester) async {
  await tester.pump();
  expect(tester.binding.hasScheduledFrame, isFalse);
}

void _setMode(bool on) {
  final previous = appdata.settings['eInkMode'];
  appdata.settings['eInkMode'] = on;
  addTearDown(() => appdata.settings['eInkMode'] = previous);
}

class _StateProbe extends StatefulWidget {
  const _StateProbe();

  @override
  State<_StateProbe> createState() => _StateProbeState();
}

class _StateProbeState extends State<_StateProbe> {
  @override
  Widget build(BuildContext context) =>
      Text(MediaQuery.disableAnimationsOf(context) ? 'off' : 'on');
}

class _Loading extends StatefulWidget {
  const _Loading();

  @override
  State<_Loading> createState() => _LoadingState();
}

class _LoadingState extends LoadingState<_Loading, String> {
  @override
  Future<Res<String>> loadData(RequestScope scope) =>
      Completer<Res<String>>().future;

  @override
  Widget buildContent(BuildContext context, String data) => Text(data);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('T9 reduce motion without the platform flag', () {
    testWidgets('flipping the switch keeps the state below it', (tester) async {
      Widget tree(bool enabled) => MaterialApp(
        builder: (context, child) =>
            EInkReduceMotion(enabled: enabled, child: child!),
        home: const _StateProbe(),
      );
      await tester.pumpWidget(tree(false));
      final state = tester.state(find.byType(_StateProbe));
      expect(find.text('on'), findsOneWidget);
      await tester.pumpWidget(tree(true));
      expect(tester.state(find.byType(_StateProbe)), same(state));
      expect(find.text('off'), findsOneWidget);
      await tester.pumpWidget(tree(false));
      expect(tester.state(find.byType(_StateProbe)), same(state));
      expect(find.text('on'), findsOneWidget);
    });

    testWidgets('the platform flag is off and the app switch still wins', (
      tester,
    ) async {
      _setMode(true);
      late BuildContext inner;
      await tester.pumpWidget(
        _app(
          Builder(
            builder: (context) {
              inner = context;
              return const SizedBox();
            },
          ),
        ),
      );
      expect(
        tester.platformDispatcher.accessibilityFeatures.disableAnimations,
        isFalse,
      );
      expect(MediaQuery.disableAnimationsOf(inner), isTrue);
    });

    testWidgets('AppPageRoute shows and removes the page within one frame', (
      tester,
    ) async {
      _setMode(true);
      late BuildContext home;
      await tester.pumpWidget(
        _app(
          Builder(
            builder: (context) {
              home = context;
              return const Text('home');
            },
          ),
        ),
      );
      expect(
        tester.platformDispatcher.accessibilityFeatures.disableAnimations,
        isFalse,
      );
      for (var i = 0; i < 2; i++) {
        final route = AppPageRoute<void>(
          builder: (_) => const Scaffold(body: Text('second')),
        );
        expect(route.transitionDuration, Duration.zero);
        expect(route.reverseTransitionDuration, Duration.zero);
        Navigator.of(home).push(route);
        await tester.pump();
        expect(find.text('second'), findsOneWidget);
        expect(route.animation!.value, 1);
        Navigator.of(home).pop();
        await tester.pump();
        expect(find.text('second'), findsNothing);
        await _expectIdle(tester);
      }
    });

    testWidgets('AppPageRoute keeps its transition when the switch is off', (
      tester,
    ) async {
      _setMode(false);
      late BuildContext home;
      await tester.pumpWidget(
        _app(
          Builder(
            builder: (context) {
              home = context;
              return const Text('home');
            },
          ),
        ),
      );
      final route = AppPageRoute<void>(
        builder: (_) => const Scaffold(body: Text('second')),
      );
      expect(route.transitionDuration, const Duration(milliseconds: 300));
      Navigator.of(home).push(route);
      await tester.pump();
      expect(route.animation!.value, lessThan(1));
      expect(tester.binding.hasScheduledFrame, isTrue);
      await tester.pumpAndSettle();
    });

    testWidgets('dialogs open, close and reopen one frame at a time', (
      tester,
    ) async {
      _setMode(true);
      late BuildContext home;
      await tester.pumpWidget(
        _app(
          Builder(
            builder: (context) {
              home = context;
              return const Scaffold(body: Text('home'));
            },
          ),
        ),
      );
      for (var i = 0; i < 2; i++) {
        showDialogMessage(home, 'Title', 'Body text');
        await tester.pump();
        expect(find.text('Body text'), findsOneWidget);
        await _expectIdle(tester);
        await tester.tap(find.byType(FilledButton));
        await tester.pump();
        expect(find.text('Body text'), findsNothing);
        await _expectIdle(tester);
      }
      var confirmed = 0;
      showConfirmDialog(
        context: home,
        title: 'Sure',
        content: 'Really',
        onConfirm: () => confirmed++,
      );
      await tester.pump();
      expect(find.text('Really'), findsOneWidget);
      await tester.tap(find.byType(FilledButton));
      await tester.pump();
      expect(find.text('Really'), findsNothing);
      expect(confirmed, 1);
    });

    testWidgets('context menus open, close and reopen one frame at a time', (
      tester,
    ) async {
      _setMode(true);
      late BuildContext home;
      await tester.pumpWidget(
        _app(
          Builder(
            builder: (context) {
              home = context;
              return const Scaffold(body: Text('home'));
            },
          ),
        ),
      );
      final menus = MenuRouteController();
      final calls = <int>[];
      for (var i = 0; i < 2; i++) {
        final handle = menus.show(home, const Offset(100, 100), [
          MenuEntry(text: 'Action', onClick: () => calls.add(i)),
        ])!;
        await tester.pump();
        await tester.pump();
        expect(find.text('Action'), findsOneWidget);
        await _expectIdle(tester);
        await tester.tap(find.text('Action'));
        await tester.pump();
        await tester.pump();
        expect(find.text('Action'), findsNothing);
        expect(handle.isCurrent, isFalse);
      }
      expect(calls, [0, 1]);
      menus.dispose();
    });

    testWidgets('PopUpWidget opens, closes and reopens one frame at a time', (
      tester,
    ) async {
      _setMode(true);
      late BuildContext home;
      await tester.pumpWidget(
        _app(
          Builder(
            builder: (context) {
              home = context;
              return const Scaffold(body: Text('home'));
            },
          ),
        ),
      );
      for (var i = 0; i < 2; i++) {
        final route = PopUpWidget<void>(const Scaffold(body: Text('popup')));
        expect(route.transitionDuration, Duration.zero);
        Navigator.of(home, rootNavigator: true).push(route);
        await tester.pump();
        expect(find.text('popup'), findsOneWidget);
        expect(route.animation!.value, 1);
        Navigator.of(home, rootNavigator: true).pop();
        await tester.pump();
        expect(find.text('popup'), findsNothing);
      }
    });
  });

  group('T10 looping animations are stopped', () {
    for (final (name, child) in <(String, Widget)>[
      ('ListLoadingIndicator', const ListLoadingIndicator()),
      ('FiveDotLoadingAnimation', const FiveDotLoadingAnimation()),
      ('EInkProgressIndicator', const EInkProgressIndicator()),
      ('LoadingState', const _Loading()),
    ]) {
      testWidgets('$name schedules no frames once built', (tester) async {
        _setMode(true);
        await tester.pumpWidget(_app(Scaffold(body: Center(child: child))));
        await tester.pump();
        await tester.pump();
        expect(tester.binding.hasScheduledFrame, isFalse, reason: name);
        await tester.pumpWidget(const SizedBox());
      });
    }

    testWidgets('the same widgets keep animating when the switch is off', (
      tester,
    ) async {
      _setMode(false);
      await tester.pumpWidget(
        _app(const Scaffold(body: ListLoadingIndicator())),
      );
      await tester.pump();
      expect(tester.binding.hasScheduledFrame, isTrue);
      await tester.pumpWidget(
        _app(const Scaffold(body: EInkProgressIndicator())),
      );
      await tester.pump();
      expect(tester.binding.hasScheduledFrame, isTrue);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('determinate progress passes through unchanged', (
      tester,
    ) async {
      _setMode(true);
      await tester.pumpWidget(
        _app(const Scaffold(body: EInkProgressIndicator(value: 0.25))),
      );
      expect(
        tester
            .widget<CircularProgressIndicator>(
              find.byType(CircularProgressIndicator),
            )
            .value,
        0.25,
      );
    });

    testWidgets('every argument reaches the wrapped indicator', (tester) async {
      _setMode(false);
      final animation = AlwaysStoppedAnimation<Color?>(Colors.red);
      await tester.pumpWidget(
        _app(
          Scaffold(
            body: EInkProgressIndicator(
              value: 0.4,
              strokeWidth: 2,
              backgroundColor: Colors.blue,
              color: Colors.green,
              valueColor: animation,
              semanticsLabel: 'l',
              semanticsValue: '40',
              strokeCap: StrokeCap.round,
            ),
          ),
        ),
      );
      final inner = tester.widget<CircularProgressIndicator>(
        find.byType(CircularProgressIndicator),
      );
      expect(inner.value, 0.4);
      expect(inner.strokeWidth, 2);
      expect(inner.backgroundColor, Colors.blue);
      expect(inner.color, Colors.green);
      expect(inner.valueColor, same(animation));
      expect(inner.semanticsLabel, 'l');
      expect(inner.semanticsValue, '40');
      expect(inner.strokeCap, StrokeCap.round);
      await tester.pumpWidget(
        _app(const Scaffold(body: EInkProgressIndicator())),
      );
      final plain = tester.widget<CircularProgressIndicator>(
        find.byType(CircularProgressIndicator),
      );
      expect(plain.value, isNull);
      expect(plain.strokeWidth, isNull);
    });

    testWidgets('static dots are black', (tester) async {
      _setMode(true);
      await tester.pumpWidget(
        _app(const Scaffold(body: ListLoadingIndicator())),
      );
      final colors = tester
          .widgetList<Container>(find.byType(Container))
          .map((c) => (c.decoration as BoxDecoration?)?.color)
          .whereType<Color>();
      expect(colors, isNotEmpty);
      expect(colors.every((c) => c == Colors.black), isTrue);
    });
  });
}
