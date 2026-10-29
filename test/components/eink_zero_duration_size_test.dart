import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:venera_next/components/button.dart';
import 'package:venera_next/features/reader/brightness.dart';

void main() {
  for (final disabled in [true, false]) {
    testWidgets(
      'Button loading toggle relayouts, disableAnimations=$disabled',
      (tester) async {
        var loading = false;
        late StateSetter setState;
        await tester.pumpWidget(
          MaterialApp(
            home: MediaQuery(
              data: MediaQueryData(disableAnimations: disabled),
              child: Scaffold(
                body: StatefulBuilder(
                  builder: (context, set) {
                    setState = set;
                    return ListTile(
                      title: const Text('setting'),
                      trailing: Button.normal(
                        isLoading: loading,
                        onPressed: () {},
                        child: const Text('a much longer action label'),
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        );
        for (final next in [true, false, true]) {
          setState(() => loading = next);
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 300));
        }
        expect(tester.takeException(), isNull);
        expect(
          find.byType(AnimatedSize),
          disabled ? findsNothing : findsOneWidget,
        );
      },
    );
  }

  for (final disabled in [true, false]) {
    testWidgets('brightness slider toggle, disableAnimations=$disabled', (
      tester,
    ) async {
      var enabled = false;
      late StateSetter setState;
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(disableAnimations: disabled),
            child: Scaffold(
              body: StatefulBuilder(
                builder: (context, set) {
                  setState = set;
                  return ReaderBrightnessControl(
                    enabled: enabled,
                    brightness: 50,
                    onEnabledChanged: (_) {},
                    onBrightnessChanged: (_) {},
                  );
                },
              ),
            ),
          ),
        ),
      );
      for (final next in [true, false, true]) {
        setState(() => enabled = next);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
      }
      expect(tester.takeException(), isNull);
      expect(
        find.byType(AnimatedSize),
        disabled ? findsNothing : findsOneWidget,
      );
    });
  }
}
