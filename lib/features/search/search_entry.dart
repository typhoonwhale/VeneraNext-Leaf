import 'package:venera_next/foundation/eink_theme.dart';
import 'package:flutter/material.dart';
import 'package:venera_next/components/gesture.dart';
import 'package:venera_next/foundation/app.dart';
import 'package:venera_next/foundation/context.dart';
import 'package:venera_next/foundation/translations.dart';
import 'package:venera_next/foundation/widget_utils.dart';

import 'search_page.dart';

class SearchEntry extends StatelessWidget {
  const SearchEntry({super.key});

  @override
  Widget build(BuildContext context) {
    return SliverToBoxAdapter(
      child: Container(
        height: App.isMobile ? 52 : 46,
        width: double.infinity,
        margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        child: Material(
          color: context.colorScheme.surfaceContainerHigh,
          borderRadius: context.isEInk ? null : BorderRadius.circular(32),
          shape: context.isEInk
              ? const StadiumBorder(
                  side: BorderSide(
                    color: Colors.black,
                    width: EInkStyle.strokeWidth,
                  ),
                )
              : null,
          child: ClickInkWell(
            borderRadius: BorderRadius.circular(32),
            onTap: () {
              context.to(() => const SearchPage());
            },
            child: Row(
              children: [
                const SizedBox(width: 16),
                const Icon(Icons.search),
                const SizedBox(width: 8),
                Text('Search'.tl, style: ts.s16),
                const Spacer(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
