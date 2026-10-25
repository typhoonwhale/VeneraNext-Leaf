import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'status_info.dart';

/// A measured, opaque information region outside the reading gesture viewport.
/// Reserve worst-case page/status widths; let actual text determine row height.
/// Narrow screens use two information rows, followed by independent bottom space.
class ReaderInformationFooter extends StatelessWidget {
  const ReaderInformationFooter({
    super.key,
    required this.page,
    required this.maxPage,
    required this.showPage,
    required this.showStatus,
    required this.bottomSpacing,
    this.dividerGap = 2,
    required this.fontSize,
    this.title,
    this.chapterTitle,
    this.hideInformation = false,
  });

  static const _minimumPageDigits = 5;

  final int page, maxPage;
  final bool showPage, showStatus, hideInformation;
  final double bottomSpacing, fontSize, dividerGap;
  final String? title;
  final String? chapterTitle;

  @override
  Widget build(BuildContext context) {
    final safe = MediaQuery.paddingOf(context);
    final theme = Theme.of(context);
    final light = theme.brightness == Brightness.light;
    final style = TextStyle(
      fontSize: fontSize,
      height: 1.2,
      color: light ? Colors.black : theme.colorScheme.onSurface,
    );
    final displayTitle = [
      if (title?.trim().isNotEmpty == true) title!.trim(),
      if (chapterTitle?.trim().isNotEmpty == true) chapterTitle!.trim(),
    ].join('｜');
    return ColoredBox(
      color: light ? Colors.white : theme.colorScheme.surface,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final contentWidth = math.max(
            0.0,
            constraints.maxWidth - 24 - safe.left - safe.right,
          );
          Size measure(String text, double width) {
            final painter = TextPainter(
              text: TextSpan(
                text: text,
                style: DefaultTextStyle.of(context).style.merge(style),
              ),
              textDirection: Directionality.of(context),
              textScaler: MediaQuery.textScalerOf(context),
            )..layout(maxWidth: width);
            final size = painter.size;
            painter.dispose();
            return size;
          }

          final widestDigit = List.generate(10, (i) => '$i').reduce(
            (a, b) =>
                measure(a, double.infinity).width >=
                    measure(b, double.infinity).width
                ? a
                : b,
          );
          // Keep the viewport stable across ordinary chapter lengths. Beyond
          // 99,999 pages, grow rather than truncate accessible page numbers.
          final digits =
              widestDigit *
              math.max(_minimumPageDigits, maxPage.toString().length);
          final pageSample = '$digits/$digits';
          final statusSample =
              '${widestDigit * 2}:${widestDigit * 2} ${widestDigit * 3}% +';
          final pageWidth = showPage
              ? measure(pageSample, double.infinity).width
              : 0.0;
          final statusWidth = showStatus
              ? measure(statusSample, double.infinity).width
              : 0.0;
          final titleMinimumWidth = displayTitle.isNotEmpty
              ? measure('…', double.infinity).width
              : 0.0;
          final stacked =
              showStatus &&
              (showPage
                  ? pageWidth +
                            statusWidth +
                            (displayTitle.isNotEmpty
                                ? 12 + titleMinimumWidth
                                : 12) >
                        contentWidth
                  : displayTitle.isNotEmpty &&
                        statusWidth + 12 + titleMinimumWidth > contentWidth);
          Widget pageInfo() => LayoutBuilder(
            builder: (context, bounds) {
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (showPage)
                    SizedBox(
                      width: math.min(pageWidth, bounds.maxWidth),
                      child: Text(
                        '${page.clamp(1, maxPage)}/$maxPage',
                        style: style,
                      ),
                    ),
                  if (displayTitle.isNotEmpty)
                    Expanded(
                      child: Text(
                        displayTitle,
                        key: const ValueKey('reader-footer-title'),
                        style: style,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
              );
            },
          );
          Widget statusInfo() => ReaderStatusInfo(
            key: const ValueKey('reader-footer-status'),
            footerFontSize: fontSize,
          );
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                height: 1,
                child: ColoredBox(
                  key: const ValueKey('reader-footer-divider'),
                  color: light ? Colors.black : theme.colorScheme.onSurface,
                ),
              ),
              SizedBox(
                key: const ValueKey('reader-footer-divider-gap'),
                height: dividerGap,
              ),
              Padding(
                padding: EdgeInsets.fromLTRB(
                  12 + safe.left,
                  0,
                  12 + safe.right,
                  0,
                ),
                child: Visibility(
                  key: const ValueKey('reader-footer-information'),
                  visible: !hideInformation,
                  maintainState: true,
                  maintainAnimation: true,
                  maintainSize: true,
                  child: DefaultTextStyle.merge(
                    style: style,
                    child: stacked
                        ? Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              pageInfo(),
                              const SizedBox(height: 4),
                              Align(
                                alignment: Alignment.centerRight,
                                child: statusInfo(),
                              ),
                            ],
                          )
                        : Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (showPage || displayTitle.isNotEmpty)
                                Expanded(child: pageInfo())
                              else
                                const Spacer(),
                              if (showStatus) ...[
                                if (showPage)
                                  const SizedBox(width: 12)
                                else if (displayTitle.isNotEmpty)
                                  SizedBox(
                                    width: math.min(
                                      12,
                                      math.max(0, contentWidth - statusWidth),
                                    ),
                                  ),
                                SizedBox(
                                  width: math.min(statusWidth, contentWidth),
                                  child: statusInfo(),
                                ),
                              ],
                            ],
                          ),
                  ),
                ),
              ),
              SizedBox(
                key: const ValueKey('reader-footer-bottom-spacing'),
                height: bottomSpacing,
              ),
              SizedBox(
                key: const ValueKey('reader-footer-safe-bottom'),
                height: safe.bottom,
              ),
            ],
          );
        },
      ),
    );
  }
}
