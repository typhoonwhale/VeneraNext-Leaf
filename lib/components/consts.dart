import 'package:flutter/widgets.dart';

const fastAnimationDuration = Duration(milliseconds: 160);

/// [normal], or zero when animations are disabled (the E-Ink reduce-motion
/// switch sets the MediaQuery flag).
Duration tweenDuration(
  BuildContext context, [
  Duration normal = fastAnimationDuration,
]) => MediaQuery.disableAnimationsOf(context) ? Duration.zero : normal;
