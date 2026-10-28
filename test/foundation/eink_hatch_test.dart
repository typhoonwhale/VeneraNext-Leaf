import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:venera_next/foundation/eink_theme.dart';

void main() {
  group('einkHatchSegments', () {
    test('count follows size and perpendicular spacing', () {
      // c = k * 10 * sqrt2 < 200  ->  k = 1..14
      expect(einkHatchSegments(const Size(100, 100), 10), hasLength(14));
      expect(einkHatchSegments(const Size(100, 100), 20), hasLength(7));
      expect(einkHatchSegments(Size.zero, 10), isEmpty);
    });

    test(
      'segments are 45 degrees, bottom-left to top-right, inside bounds',
      () {
        const size = Size(120, 40);
        final segs = einkHatchSegments(size, 10);
        expect(segs, isNotEmpty);
        for (final (a, b) in segs) {
          for (final p in [a, b]) {
            expect(p.dx, inInclusiveRange(0, size.width));
            expect(p.dy, inInclusiveRange(0, size.height));
          }
          expect(b.dx, greaterThan(a.dx));
          expect(a.dy, greaterThan(b.dy));
          expect(b.dx - a.dx, closeTo(a.dy - b.dy, 1e-9));
        }
        final d =
            (segs[1].$1.dx + segs[1].$1.dy) - (segs[0].$1.dx + segs[0].$1.dy);
        expect(d / math.sqrt2, closeTo(10, 1e-9));
      },
    );
  });

  test('painter clips drawing to the shape', () async {
    const size = Size(100, 40);
    final recorder = PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawColor(const Color(0xFF00FF00), BlendMode.src);
    const EInkHatchPainter(shape: StadiumBorder()).paint(canvas, size);
    final image = await recorder.endRecording().toImage(100, 40);
    final data = (await image.toByteData())!;
    int px(int x, int y) => data.getUint32((y * 100 + x) * 4);
    // Corner is outside the stadium: the green backdrop must survive.
    expect(px(0, 0), 0x00FF00FF);
    // Center is inside: painted white or black, never the backdrop.
    expect(px(50, 20), anyOf(0xFFFFFFFF, 0x000000FF));
  });
}
