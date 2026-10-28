import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:venera_next/foundation/appdata.dart';
import 'package:venera_next/foundation/global_preference_store.dart';

/// Reads E-Ink derived switches without a [BuildContext].
abstract final class EInkPreferences {
  static bool get einkTheme =>
      GlobalPreferenceStore(appdata.settings).appearance.einkTheme;

  static bool get reduceMotion =>
      GlobalPreferenceStore(appdata.settings).appearance.reduceMotion;
}

/// A [CircularProgressIndicator] that stops spinning when animations are
/// disabled: an indeterminate indicator then shows a static half ring.
/// Every other argument, and a determinate [value], pass through unchanged.
class EInkProgressIndicator extends StatelessWidget {
  const EInkProgressIndicator({
    super.key,
    this.value,
    this.strokeWidth,
    this.backgroundColor,
    this.color,
    this.valueColor,
    this.semanticsLabel,
    this.semanticsValue,
    this.strokeCap,
  });

  final double? value;
  final double? strokeWidth;
  final Color? backgroundColor;
  final Color? color;
  final Animation<Color?>? valueColor;
  final String? semanticsLabel;
  final String? semanticsValue;
  final StrokeCap? strokeCap;

  @override
  Widget build(BuildContext context) {
    return CircularProgressIndicator(
      value: value ?? (MediaQuery.disableAnimationsOf(context) ? 0.5 : null),
      strokeWidth: strokeWidth,
      backgroundColor: backgroundColor,
      color: color,
      valueColor: valueColor,
      semanticsLabel: semanticsLabel,
      semanticsValue: semanticsValue,
      strokeCap: strokeCap,
    );
  }
}

/// Sets [MediaQueryData.disableAnimations] below it while [enabled]. The
/// wrapper is always in the tree, so flipping [enabled] keeps the state of
/// everything underneath; only this widget depends on the MediaQuery.
class EInkReduceMotion extends StatelessWidget {
  const EInkReduceMotion({
    super.key,
    required this.enabled,
    required this.child,
  });

  final bool enabled;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final data = MediaQuery.of(context);
    return MediaQuery(
      data: enabled ? data.copyWith(disableAnimations: true) : data,
      child: child,
    );
  }
}

/// Hatch segments (bottom-left to top-right, 45 degrees) covering [size],
/// each clipped to the rectangle. [spacing] is the perpendicular distance
/// between neighbouring lines.
List<(Offset, Offset)> einkHatchSegments(Size size, double spacing) {
  final step = spacing * math.sqrt2;
  final segments = <(Offset, Offset)>[];
  if (size.isEmpty || step <= 0) return segments;
  final total = size.width + size.height;
  for (var k = 1; k * step < total; k++) {
    final c = k * step;
    final xa = math.max(0.0, c - size.height);
    final xb = math.min(c, size.width);
    segments.add((Offset(xa, c - xa), Offset(xb, c - xb)));
  }
  return segments;
}

class EInkHatchPainter extends CustomPainter {
  const EInkHatchPainter({
    this.shape,
    this.paintBorder = false,
    this.spacing = EInkStyle.hatchSpacing,
    this.strokeWidth = EInkStyle.hatchStrokeWidth,
  });

  /// Clip shape; the plain rectangle when null.
  final ShapeBorder? shape;

  /// Also strokes [shape]'s own side on top of the hatch.
  final bool paintBorder;
  final double spacing;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.save();
    if (shape != null) canvas.clipPath(shape!.getOuterPath(rect));
    canvas.clipRect(rect);
    canvas.drawRect(rect, Paint()..color = Colors.white);
    final paint = Paint()
      ..color = Colors.black
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke;
    for (final (a, b) in einkHatchSegments(size, spacing)) {
      canvas.drawLine(a, b, paint);
    }
    canvas.restore();
    if (paintBorder && shape != null) shape!.paint(canvas, rect);
  }

  @override
  bool shouldRepaint(EInkHatchPainter old) =>
      old.shape != shape ||
      old.paintBorder != paintBorder ||
      old.spacing != spacing ||
      old.strokeWidth != strokeWidth;
}

/// White background with black 45 degree hatch lines, clipped to [shape];
/// marks a disabled control on E-Ink.
class EInkHatch extends StatelessWidget {
  const EInkHatch({
    super.key,
    this.shape,
    this.paintBorder = false,
    this.child,
  });

  final ShapeBorder? shape;
  final bool paintBorder;
  final Widget? child;

  @override
  Widget build(BuildContext context) => CustomPaint(
    painter: EInkHatchPainter(shape: shape, paintBorder: paintBorder),
    child: child,
  );
}

/// White outline of [EInkStyle.hatchHaloWidth] around text; the stroke is
/// drawn under the black glyphs, so it takes twice the halo width.
Paint einkHaloPaint() => Paint()
  ..style = PaintingStyle.stroke
  ..strokeWidth = 2 * EInkStyle.hatchHaloWidth
  ..strokeJoin = StrokeJoin.round
  ..color = Colors.white;

/// White ring around icon glyphs, made of hard shadows in 16 directions.
IconThemeData einkHaloIconTheme() => IconThemeData(
  shadows: [
    for (var i = 0; i < 16; i++)
      Shadow(
        color: Colors.white,
        offset: Offset.fromDirection(i * math.pi / 8, EInkStyle.hatchHaloWidth),
      ),
  ],
);

/// Overlays [top] on [halo], which must lay out identically to it. The halo
/// layer is a decoration: its tickers are muted, it has no semantics and
/// takes no input.
Widget einkHaloStack(Widget halo, Widget top) => Stack(
  clipBehavior: Clip.none,
  children: [
    TickerMode(
      enabled: false,
      child: ExcludeSemantics(child: IgnorePointer(child: halo)),
    ),
    top,
  ],
);

/// Whether [child] can be built a second time as a halo layer. The walk goes
/// through the widgets visible from here and refuses stateful widgets,
/// progress indicators and anything carrying a GlobalKey: those would run
/// twice or collide on the key. Widgets that build their own subtree are
/// not looked into; the halo layer's tickers are muted for them.
bool einkHaloSafe(Widget? child) {
  if (child == null) return true;
  if (child.key is GlobalKey) return false;
  if (child is StatefulWidget ||
      child is ProgressIndicator ||
      child is EInkProgressIndicator) {
    return false;
  }
  if (child is Text && child.textSpan != null) {
    var safe = true;
    child.textSpan!.visitChildren((span) {
      if (span is WidgetSpan && !einkHaloSafe(span.child)) safe = false;
      return safe;
    });
    return safe;
  }
  if (child is SingleChildRenderObjectWidget) {
    return einkHaloSafe(child.child);
  }
  if (child is MultiChildRenderObjectWidget) {
    return child.children.every(einkHaloSafe);
  }
  if (child is ProxyWidget) return einkHaloSafe(child.child);
  return true;
}

/// Keeps a disabled control's label readable on top of the hatch: text and
/// icons get a white halo, so the hatch lines stop at the glyph edges. A
/// child that cannot be duplicated safely (see [einkHaloSafe]) is returned
/// as is: the hatch stays, the halo is skipped.
Widget einkHaloLabel(Widget child) => !einkHaloSafe(child)
    ? child
    : Builder(
        builder: (context) {
          final base = DefaultTextStyle.of(context);
          return einkHaloStack(
            DefaultTextStyle(
              style: base.style.copyWith(foreground: einkHaloPaint()),
              textAlign: base.textAlign,
              softWrap: base.softWrap,
              overflow: base.overflow,
              maxLines: base.maxLines,
              textWidthBasis: base.textWidthBasis,
              textHeightBehavior: base.textHeightBehavior,
              child: IconTheme.merge(data: einkHaloIconTheme(), child: child),
            ),
            child,
          );
        },
      );

/// Theme-carried E-Ink flag and the shared selected-state colors.
@immutable
class EInkStyle extends ThemeExtension<EInkStyle> {
  /// Outline width for tags, badges, cards, inputs, chips and buttons.
  static const double strokeWidth = 2.0;

  /// Outline width for dialogs, sheets and the FAB.
  static const double strongStrokeWidth = 3.0;

  /// Stroke width of the hatch lines on disabled controls.
  static const double hatchStrokeWidth = strokeWidth;

  /// Width of the white halo around the label of a disabled hatched control.
  static const double hatchHaloWidth = 3.0;

  /// Perpendicular distance between hatch line centers on disabled controls.
  static const double hatchSpacing = 10.0;

  const EInkStyle({
    this.enabled = false,
    this.selectedBackground = Colors.black,
    this.selectedForeground = Colors.white,
  });

  final bool enabled;
  final Color selectedBackground;
  final Color selectedForeground;

  @override
  EInkStyle copyWith({
    bool? enabled,
    Color? selectedBackground,
    Color? selectedForeground,
  }) => EInkStyle(
    enabled: enabled ?? this.enabled,
    selectedBackground: selectedBackground ?? this.selectedBackground,
    selectedForeground: selectedForeground ?? this.selectedForeground,
  );

  @override
  EInkStyle lerp(ThemeExtension<EInkStyle>? other, double t) {
    if (other is! EInkStyle) return this;
    return t < 0.5 ? this : other;
  }
}

extension EInkContext on BuildContext {
  bool get isEInk => Theme.of(this).extension<EInkStyle>()?.enabled ?? false;

  /// Solid badge fill: black on E-Ink, [color] otherwise.
  Color einkBadgeColor(Color color) => isEInk ? Colors.black : color;

  /// Outline used by E-Ink in place of fills that become indistinguishable
  /// on a white surface; null for the regular theme.
  Border? einkBorder({double width = EInkStyle.strokeWidth}) =>
      isEInk ? Border.all(color: Colors.black, width: width) : null;

  /// Heavier weight for hard-coded small text, which does not inherit the
  /// E-Ink text theme; unchanged on the regular theme.
  TextStyle einkSmallText(TextStyle style) =>
      isEInk ? style.copyWith(fontWeight: FontWeight.w600) : style;

  /// Comic covers are square-cornered on E-Ink so the outline reads as a frame.
  BorderRadius einkCoverRadius(BorderRadius normal) =>
      isEInk ? BorderRadius.zero : normal;

  /// Selected-state colors for E-Ink; only meaningful when [isEInk] is true.
  EInkStyle get einkStyle =>
      Theme.of(this).extension<EInkStyle>() ?? const EInkStyle();
}

ColorScheme einkColorScheme() => const ColorScheme(
  brightness: Brightness.light,
  primary: Colors.black,
  onPrimary: Colors.white,
  primaryContainer: Colors.white,
  onPrimaryContainer: Colors.black,
  secondary: Colors.black,
  onSecondary: Colors.white,
  secondaryContainer: Colors.white,
  onSecondaryContainer: Colors.black,
  tertiary: Colors.black,
  onTertiary: Colors.white,
  tertiaryContainer: Colors.white,
  onTertiaryContainer: Colors.black,
  error: Colors.black,
  onError: Colors.white,
  errorContainer: Colors.white,
  onErrorContainer: Colors.black,
  surface: Colors.white,
  onSurface: Colors.black,
  onSurfaceVariant: Colors.black,
  surfaceDim: Colors.white,
  surfaceBright: Colors.white,
  surfaceContainerLowest: Colors.white,
  surfaceContainerLow: Colors.white,
  surfaceContainer: Colors.white,
  surfaceContainerHigh: Colors.white,
  surfaceContainerHighest: Colors.white,
  outline: Colors.black,
  outlineVariant: Colors.black,
  shadow: Colors.transparent,
  scrim: Colors.black,
  surfaceTint: Colors.transparent,
  inverseSurface: Colors.black,
  onInverseSurface: Colors.white,
  inversePrimary: Colors.white,
);

/// Route builder that shows the destination immediately.
class _NoTransitionsBuilder extends PageTransitionsBuilder {
  const _NoTransitionsBuilder();

  // MaterialPageRoute reads both durations from the builder; the default of
  // 300 ms would keep the old page on screen after a pop.
  @override
  Duration get transitionDuration => Duration.zero;

  @override
  Duration get reverseTransitionDuration => Duration.zero;

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) => child;
}

/// Raises weights so thin strokes survive the E-Ink panel: every style is at
/// least w500 and small (<= 12) styles are w600. Font sizes are unchanged.
TextTheme _einkTextTheme(TextTheme t) {
  TextStyle? bump(TextStyle? s) {
    if (s == null) return null;
    final small = (s.fontSize ?? 14) <= 12;
    final floor = small ? FontWeight.w600 : FontWeight.w500;
    final current = s.fontWeight;
    final weight = current == null || current.value < floor.value
        ? floor
        : current;
    return s.copyWith(fontWeight: weight);
  }

  return t.copyWith(
    displayLarge: bump(t.displayLarge),
    displayMedium: bump(t.displayMedium),
    displaySmall: bump(t.displaySmall),
    headlineLarge: bump(t.headlineLarge),
    headlineMedium: bump(t.headlineMedium),
    headlineSmall: bump(t.headlineSmall),
    titleLarge: bump(t.titleLarge),
    titleMedium: bump(t.titleMedium),
    titleSmall: bump(t.titleSmall),
    bodyLarge: bump(t.bodyLarge),
    bodyMedium: bump(t.bodyMedium),
    bodySmall: bump(t.bodySmall),
    labelLarge: bump(t.labelLarge),
    labelMedium: bump(t.labelMedium),
    labelSmall: bump(t.labelSmall),
  );
}

/// Applies the E-Ink component overrides on top of a base theme.
ThemeData applyEInkTheme(ThemeData base) {
  const border = BorderSide(color: Colors.black, width: EInkStyle.strokeWidth);
  const strongBorder = BorderSide(
    color: Colors.black,
    width: EInkStyle.strongStrokeWidth,
  );
  final shape = RoundedRectangleBorder(
    side: border,
    borderRadius: BorderRadius.circular(12),
  );
  final strongShape = RoundedRectangleBorder(
    side: strongBorder,
    borderRadius: BorderRadius.circular(12),
  );
  const buttonShape = StadiumBorder(side: border);
  final buttonSide = const WidgetStatePropertyAll<BorderSide>(border);
  final disabledForeground = WidgetStateProperty.resolveWith<Color?>(
    (states) => states.contains(WidgetState.disabled) ? Colors.black : null,
  );
  // Clip the hatch and stroke the outline here: on device the button
  // Material did not clip a disabled FilledButton nor keep its side visible.
  Widget hatchBackground(
    BuildContext context,
    Set<WidgetState> states,
    Widget? child,
  ) => states.contains(WidgetState.disabled)
      ? EInkHatch(shape: buttonShape, paintBorder: true, child: child)
      : child ?? const SizedBox.shrink();
  Widget hatchForeground(
    BuildContext context,
    Set<WidgetState> states,
    Widget? child,
  ) => states.contains(WidgetState.disabled) && child != null
      ? einkHaloLabel(child)
      : child ?? const SizedBox.shrink();
  return base.copyWith(
    textTheme: _einkTextTheme(base.textTheme),
    primaryTextTheme: _einkTextTheme(base.primaryTextTheme),
    textButtonTheme: TextButtonThemeData(
      style: ButtonStyle(
        shape: const WidgetStatePropertyAll(buttonShape),
        side: buttonSide,
        foregroundColor: disabledForeground,
        backgroundBuilder: hatchBackground,
        foregroundBuilder: hatchForeground,
        padding: const WidgetStatePropertyAll(
          EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: ButtonStyle(
        shape: const WidgetStatePropertyAll(buttonShape),
        side: buttonSide,
        foregroundColor: disabledForeground,
        backgroundBuilder: hatchBackground,
        foregroundBuilder: hatchForeground,
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: ButtonStyle(
        shape: const WidgetStatePropertyAll(buttonShape),
        side: buttonSide,
        foregroundColor: disabledForeground,
        backgroundBuilder: hatchBackground,
        foregroundBuilder: hatchForeground,
        backgroundColor: WidgetStateProperty.resolveWith<Color?>(
          (states) =>
              states.contains(WidgetState.disabled) ? Colors.white : null,
        ),
      ),
    ),
    chipTheme: base.chipTheme.copyWith(side: border),
    switchTheme: base.switchTheme.copyWith(
      trackOutlineColor: const WidgetStatePropertyAll(Colors.black),
      trackOutlineWidth: const WidgetStatePropertyAll(EInkStyle.strokeWidth),
      // Switch tracks are too narrow for hatch lines: disabled is a white
      // track with a hollow ring thumb.
      trackColor: WidgetStateProperty.resolveWith<Color?>(
        (states) => states.contains(WidgetState.disabled) ? Colors.white : null,
      ),
      thumbColor: WidgetStateProperty.resolveWith<Color?>(
        (states) => states.contains(WidgetState.disabled) ? Colors.white : null,
      ),
      thumbIcon: WidgetStateProperty.resolveWith<Icon?>(
        (states) => states.contains(WidgetState.disabled)
            ? const Icon(Icons.circle_outlined, color: Colors.black)
            : null,
      ),
    ),
    // Material greys disabled text and icons with disabledColor (black38 on
    // the light theme); keep them black, the hatch marks the disabled state.
    disabledColor: Colors.black,
    iconButtonTheme: IconButtonThemeData(
      style: ButtonStyle(foregroundColor: disabledForeground),
    ),
    inputDecorationTheme: base.inputDecorationTheme.copyWith(
      labelStyle: WidgetStateTextStyle.resolveWith(
        (states) => TextStyle(
          color: states.contains(WidgetState.disabled) ? Colors.black : null,
        ),
      ),
      floatingLabelStyle: WidgetStateTextStyle.resolveWith(
        (states) => TextStyle(
          color: states.contains(WidgetState.disabled) ? Colors.black : null,
        ),
      ),
      helperStyle: WidgetStateTextStyle.resolveWith(
        (states) => TextStyle(
          color: states.contains(WidgetState.disabled) ? Colors.black : null,
        ),
      ),
      hintStyle: WidgetStateTextStyle.resolveWith(
        (states) => TextStyle(
          color: states.contains(WidgetState.disabled) ? Colors.black : null,
        ),
      ),
      prefixIconColor: WidgetStateColor.resolveWith((_) => Colors.black),
      suffixIconColor: WidgetStateColor.resolveWith((_) => Colors.black),
    ),
    checkboxTheme: base.checkboxTheme.copyWith(
      side: border,
      fillColor: WidgetStateProperty.resolveWith<Color?>(
        (states) => states.contains(WidgetState.disabled)
            ? (states.contains(WidgetState.selected)
                  ? Colors.black
                  : Colors.white)
            : null,
      ),
      checkColor: WidgetStateProperty.resolveWith<Color?>(
        (states) => states.contains(WidgetState.disabled) ? Colors.white : null,
      ),
    ),
    sliderTheme: base.sliderTheme.copyWith(
      disabledActiveTrackColor: Colors.black,
      disabledInactiveTrackColor: Colors.white,
      disabledThumbColor: Colors.black,
    ),
    splashFactory: NoSplash.splashFactory,
    highlightColor: Colors.transparent,
    pageTransitionsTheme: PageTransitionsTheme(
      builders: {
        for (final platform in TargetPlatform.values)
          platform: const _NoTransitionsBuilder(),
      },
    ),
    dialogTheme: DialogThemeData(
      barrierColor: Colors.transparent,
      elevation: 0,
      shape: strongShape,
    ),
    cardTheme: CardThemeData(elevation: 0, shape: shape),
    popupMenuTheme: PopupMenuThemeData(elevation: 0, shape: shape),
    snackBarTheme: SnackBarThemeData(elevation: 0, shape: shape),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      elevation: 0,
      focusElevation: 0,
      hoverElevation: 0,
      highlightElevation: 0,
      disabledElevation: 0,
      backgroundColor: Colors.white,
      foregroundColor: Colors.black,
      shape: RoundedRectangleBorder(
        side: strongBorder,
        borderRadius: BorderRadius.all(Radius.circular(16)),
      ),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        backgroundColor: WidgetStateProperty.resolveWith(
          (states) =>
              states.contains(WidgetState.selected) &&
                  !states.contains(WidgetState.disabled)
              ? Colors.black
              : Colors.white,
        ),
        foregroundColor: WidgetStateProperty.resolveWith(
          (states) =>
              states.contains(WidgetState.selected) &&
                  !states.contains(WidgetState.disabled)
              ? Colors.white
              : Colors.black,
        ),
        side: const WidgetStatePropertyAll(border),
        overlayColor: const WidgetStatePropertyAll(Colors.transparent),
      ),
    ),
    extensions: [...base.extensions.values, const EInkStyle(enabled: true)],
  );
}
