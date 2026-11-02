import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:venera_next/components/message.dart';
import 'package:venera_next/features/local_comics/import_export/pdf_import_dialog.dart';
import 'package:venera_next/foundation/eink_theme.dart';

Widget app(Widget child, bool reduced) => MaterialApp(
  builder: (_, child) => EInkReduceMotion(enabled: reduced, child: child!),
  home: child,
);

void main() {
  for (final reduced in [true, false]) {
    testWidgets('real PDF dialog route reduced=$reduced', (tester) async {
      late BuildContext context;
      await tester.pumpWidget(
        app(
          Builder(
            builder: (c) {
              context = c;
              return const Scaffold();
            },
          ),
          reduced,
        ),
      );
      showPdfImportTasksDialog(context: context);
      await tester.pump();
      final dialogContext = tester.element(find.byType(ContentDialog));
      final route = ModalRoute.of(dialogContext)!;
      expect(route.animation!.value, reduced ? 1 : 0);
      await tester.pump();
      expect(tester.binding.hasScheduledFrame, !reduced);
      await tester.pumpAndSettle();
      Navigator.of(dialogContext).pop();
      await tester.pump();
      expect(
        find.byType(ContentDialog),
        reduced ? findsNothing : findsOneWidget,
      );
      await tester.pumpAndSettle();
    });
  }

  testWidgets(
    'loading resource dialog updates size and progress without ticks',
    (tester) async {
      late BuildContext context;
      await tester.pumpWidget(
        app(
          Builder(
            builder: (c) {
              context = c;
              return const Scaffold();
            },
          ),
          true,
        ),
      );
      final controller = showLoadingDialog(context);
      await tester.pump();
      await tester.pump();
      expect(tester.binding.hasScheduledFrame, isFalse);
      expect(
        tester
            .widget<LinearProgressIndicator>(
              find.byType(LinearProgressIndicator),
            )
            .value,
        .5,
      );
      for (final value in [.2, .8]) {
        controller.setProgress(value);
        controller.setMessage('Line one\nLine two\n$value');
        await tester.pump();
        await tester.pump();
        expect(
          tester
              .widget<LinearProgressIndicator>(
                find.byType(LinearProgressIndicator),
              )
              .value,
          value,
        );
        expect(tester.binding.hasScheduledFrame, isFalse);
        expect(tester.takeException(), isNull);
      }
      controller.close();
      await tester.pump();
      await tester.pump();
      expect(find.byType(ContentDialog), findsNothing);
      expect(tester.binding.hasScheduledFrame, isFalse);
    },
  );

  testWidgets('linear unknown progress only loops in normal mode', (
    tester,
  ) async {
    for (final reduced in [true, false]) {
      await tester.pumpWidget(
        app(const Scaffold(body: EInkLinearProgressIndicator()), reduced),
      );
      await tester.pump(const Duration(milliseconds: 50));
      expect(
        tester
            .widget<LinearProgressIndicator>(
              find.byType(LinearProgressIndicator),
            )
            .value,
        reduced ? .5 : null,
      );
      expect(tester.binding.hasScheduledFrame, !reduced);
    }
    await tester.pumpWidget(const SizedBox());
  });
}
