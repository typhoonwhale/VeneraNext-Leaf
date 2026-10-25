import 'package:flutter/widgets.dart';

/// Android window metrics compatibility at the application boundary.
class AndroidWindowInsets extends StatelessWidget {
  const AndroidWindowInsets({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    // Zero is valid in immersive mode. Never infer bottom/side obstruction
    // from the top inset. Retain only the existing oversized-top workaround
    // for Xiaomi freeform windows: https://github.com/flutter/flutter/issues/161086
    if (media.viewPadding.top > 200) {
      return MediaQuery(
        data: media.copyWith(
          viewPadding: media.viewPadding.copyWith(top: 15),
          padding: media.padding.top > 200
              ? media.padding.copyWith(
                  top: (15 - media.viewInsets.top).clamp(0, 15).toDouble(),
                )
              : media.padding,
        ),
        child: child,
      );
    }
    return child;
  }
}
