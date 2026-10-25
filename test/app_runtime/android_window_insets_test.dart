import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:venera_next/app_shell/android_window_insets.dart';

void main() {
  for (final metrics in [
    const MediaQueryData(
      size: Size(720, 1080),
      systemGestureInsets: EdgeInsets.only(bottom: 24),
    ),
    const MediaQueryData(
      size: Size(360, 540),
      devicePixelRatio: 2,
      padding: EdgeInsets.only(bottom: 24),
      viewPadding: EdgeInsets.only(bottom: 24),
    ),
    const MediaQueryData(
      padding: EdgeInsets.fromLTRB(32, 24, 8, 20),
      viewPadding: EdgeInsets.fromLTRB(32, 24, 8, 20),
    ),
    const MediaQueryData(
      padding: EdgeInsets.only(top: 24),
      viewPadding: EdgeInsets.only(top: 24, bottom: 20),
      viewInsets: EdgeInsets.only(bottom: 280),
    ),
  ]) {
    testWidgets('valid platform metrics pass through unchanged: $metrics', (
      tester,
    ) async {
      MediaQueryData? received;
      await tester.pumpWidget(
        MediaQuery(
          data: metrics,
          child: AndroidWindowInsets(
            child: Builder(
              builder: (context) {
                received = MediaQuery.of(context);
                return const SizedBox();
              },
            ),
          ),
        ),
      );
      expect(received, metrics);
    });
  }

  testWidgets('freeform top correction preserves other edges and IME insets', (
    tester,
  ) async {
    const metrics = MediaQueryData(
      size: Size(400, 700),
      devicePixelRatio: 2,
      padding: EdgeInsets.fromLTRB(30, 640, 10, 0),
      viewPadding: EdgeInsets.fromLTRB(30, 640, 10, 24),
      viewInsets: EdgeInsets.only(bottom: 280),
      systemGestureInsets: EdgeInsets.only(bottom: 32),
    );
    MediaQueryData? received;
    await tester.pumpWidget(
      MediaQuery(
        data: metrics,
        child: AndroidWindowInsets(
          child: Builder(
            builder: (context) {
              received = MediaQuery.of(context);
              return const SizedBox();
            },
          ),
        ),
      ),
    );
    expect(
      received,
      metrics.copyWith(
        padding: metrics.padding.copyWith(top: 15),
        viewPadding: metrics.viewPadding.copyWith(top: 15),
      ),
    );
  });
}
