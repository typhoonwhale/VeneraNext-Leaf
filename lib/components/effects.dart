import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:venera_next/foundation/eink_theme.dart';

class BlurEffect extends StatelessWidget {
  final Widget child;

  final double blur;

  final BorderRadius? borderRadius;

  const BlurEffect({
    required this.child,
    this.borderRadius,
    this.blur = 15,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    if (context.isEInk) return child;
    return ClipRRect(
      borderRadius: borderRadius ?? BorderRadius.zero,
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(
          sigmaX: blur,
          sigmaY: blur,
          tileMode: ui.TileMode.mirror,
        ),
        child: child,
      ),
    );
  }
}
