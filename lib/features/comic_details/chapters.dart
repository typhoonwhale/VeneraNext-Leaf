import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:venera_next/components/appbar.dart';
import 'package:venera_next/components/gesture.dart';
import 'package:venera_next/components/layout.dart';
import 'package:venera_next/components/settings_save_state.dart';
import 'package:venera_next/features/comic_source/comic_source_api.dart';
import 'package:venera_next/features/history/history_api.dart';
import 'package:venera_next/foundation/appdata.dart';
import 'package:venera_next/foundation/application_preferences.dart';
import 'package:venera_next/foundation/global_preference_store.dart';
import 'package:venera_next/foundation/context.dart';
import 'package:venera_next/foundation/eink_theme.dart';
import 'package:venera_next/foundation/translations.dart';
import 'package:venera_next/foundation/widget_utils.dart';

const _einkChapterShape = RoundedRectangleBorder(
  side: BorderSide(color: Colors.black, width: EInkStyle.strokeWidth),
  borderRadius: BorderRadius.all(Radius.circular(4)),
);

enum _EInkChapterState { unread, read, last }

_EInkChapterState _einkChapterState(bool visited, bool last) => last
    ? _EInkChapterState.last
    : visited
    ? _EInkChapterState.read
    : _EInkChapterState.unread;

Color _einkChapterFill(BuildContext context, _EInkChapterState state) =>
    state == _EInkChapterState.last
    ? context.einkStyle.selectedBackground
    : Colors.white;

TextStyle _einkChapterTextStyle(
  BuildContext context,
  _EInkChapterState state,
) => TextStyle(
  color: state == _EInkChapterState.last
      ? context.einkStyle.selectedForeground
      : Colors.black,
  fontWeight: FontWeight.w600,
);

Widget _einkChapterLabel(
  BuildContext context,
  String title,
  _EInkChapterState state,
) {
  final style = _einkChapterTextStyle(context, state);
  final text = Text(
    title,
    maxLines: 1,
    textAlign: TextAlign.center,
    overflow: TextOverflow.ellipsis,
    style: style,
  );
  if (state != _EInkChapterState.read) return text;
  return Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Text('\u2713 ', style: style),
      Flexible(child: text),
    ],
  );
}

class ComicChaptersView extends StatefulWidget {
  const ComicChaptersView({
    super.key,
    required this.chapters,
    this.history,
    required this.readChapter,
  });

  final ComicChapters chapters;

  final History? history;

  final void Function(int chapter) readChapter;

  @override
  State<ComicChaptersView> createState() => _ComicChaptersViewState();
}

class _ComicChaptersViewState extends SettingsSaveState<ComicChaptersView> {
  bool? _preview;
  int _request = 0;

  bool get reverse =>
      _preview ??
      GlobalPreferenceStore(
        appdata.settings,
      ).read(AppPreferences.reverseChapterOrder);

  @override
  void initState() {
    super.initState();
    appdata.settings.addListener(_refresh);
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  void _setReverse(bool value) {
    if (!acceptsSettingsChanges || value == reverse) return;
    final request = ++_request;
    setState(() => _preview = value);
    saveSetting(
      AppPreferences.reverseChapterOrder.key,
      () => appdata.updateSettings((draft) {
        GlobalPreferenceStore(
          draft,
        ).write(AppPreferences.reverseChapterOrder, value);
      }),
      onSaved: () {
        if (request == _request) setState(() => _preview = null);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final orderControl = protectSettings(
      Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          settingsSaveStatus,
          _ChapterOrderSegment(reverse: reverse, onChanged: _setReverse),
        ],
      ),
    );
    return widget.chapters.isGrouped
        ? _GroupedComicChapters(
            chapters: widget.chapters,
            history: widget.history,
            readChapter: widget.readChapter,
            reverse: reverse,
            orderControl: orderControl,
          )
        : _NormalComicChapters(
            chapters: widget.chapters,
            history: widget.history,
            readChapter: widget.readChapter,
            reverse: reverse,
            orderControl: orderControl,
          );
  }

  @override
  void dispose() {
    appdata.settings.removeListener(_refresh);
    super.dispose();
  }
}

class _NormalComicChapters extends StatefulWidget {
  const _NormalComicChapters({
    required this.chapters,
    this.history,
    required this.readChapter,
    required this.reverse,
    required this.orderControl,
  });

  final ComicChapters chapters;
  final bool reverse;
  final Widget orderControl;

  final History? history;

  final void Function(int chapter) readChapter;

  @override
  State<_NormalComicChapters> createState() => _NormalComicChaptersState();
}

class _NormalComicChaptersState extends State<_NormalComicChapters> {
  bool showAll = false;

  late History? history;

  @override
  void initState() {
    super.initState();
    history = widget.history;
  }

  @override
  void didUpdateWidget(covariant _NormalComicChapters oldWidget) {
    super.didUpdateWidget(oldWidget);
    setState(() {
      history = widget.history;
    });
  }

  @override
  Widget build(BuildContext context) {
    final chapters = widget.chapters;
    return SliverLayoutBuilder(
      builder: (context, constrains) {
        int length = chapters.length;
        bool canShowAll = showAll;
        if (!showAll) {
          var width = constrains.crossAxisExtent - 16;
          var crossItems = width ~/ 200;
          if (width % 200 != 0) {
            crossItems += 1;
          }
          length = math.min(length, crossItems * 8);
          if (length == chapters.length) {
            canShowAll = true;
          }
        }

        return SliverMainAxisGroup(
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                child: Wrap(
                  spacing: 16,
                  runSpacing: 8,
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      "Chapters".tl,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    widget.orderControl,
                  ],
                ),
              ),
            ),
            SliverGrid(
              delegate: SliverChildBuilderDelegate((context, i) {
                if (widget.reverse) {
                  i = chapters.length - i - 1;
                }
                var key = chapters.ids.elementAt(i);
                var value = chapters[key]!;
                bool visited =
                    history?.readEpisode.contains((i + 1).toString()) ?? false;
                final state = _einkChapterState(
                  visited,
                  history != null && history!.ep == i + 1,
                );
                return Padding(
                  padding: const EdgeInsets.fromLTRB(4, 4, 4, 4),
                  child: Material(
                    color: context.isEInk
                        ? _einkChapterFill(context, state)
                        : context.colorScheme.surfaceContainer,
                    borderRadius: context.isEInk
                        ? null
                        : BorderRadius.circular(16),
                    shape: context.isEInk ? _einkChapterShape : null,
                    child: ClickInkWell(
                      onTap: () => widget.readChapter(i + 1),
                      borderRadius: BorderRadius.circular(16),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        child: Center(
                          child: context.isEInk
                              ? _einkChapterLabel(context, value, state)
                              : Text(
                                  value,
                                  maxLines: 1,
                                  textAlign: TextAlign.center,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: visited
                                        ? context.colorScheme.outline
                                        : null,
                                  ),
                                ),
                        ),
                      ),
                    ),
                  ),
                );
              }, childCount: length),
              gridDelegate: const SliverGridDelegateWithFixedHeight(
                maxCrossAxisExtent: 250,
                itemHeight: 48,
              ),
            ).sliverPadding(const EdgeInsets.symmetric(horizontal: 8)),
            if (!canShowAll)
              SliverToBoxAdapter(
                child: Align(
                  alignment: Alignment.center,
                  child: TextButton.icon(
                    icon: const Icon(Icons.arrow_drop_down),
                    onPressed: () {
                      setState(() {
                        showAll = true;
                      });
                    },
                    label: Text("${"Show all".tl} (${chapters.length})"),
                  ).paddingTop(12),
                ),
              ),
            const SliverToBoxAdapter(child: Divider()),
          ],
        );
      },
    );
  }
}

class _GroupedComicChapters extends StatefulWidget {
  const _GroupedComicChapters({
    required this.chapters,
    this.history,
    required this.readChapter,
    required this.reverse,
    required this.orderControl,
  });

  final ComicChapters chapters;
  final bool reverse;
  final Widget orderControl;

  final History? history;

  final void Function(int chapter) readChapter;

  @override
  State<_GroupedComicChapters> createState() => _GroupedComicChaptersState();
}

class _GroupedComicChaptersState extends State<_GroupedComicChapters>
    with TickerProviderStateMixin {
  bool showAll = false;

  late History? history;

  late TabController tabController;

  late int index;
  late List<String> _groups;

  @override
  void initState() {
    super.initState();
    history = widget.history;
    _groups = widget.chapters.groups.toList();
    index = ((history?.group ?? 1) - 1).clamp(
      0,
      math.max(0, _groups.length - 1),
    );
    _createTabs();
  }

  void _createTabs() {
    tabController = TabController(
      initialIndex: index,
      length: _groups.length,
      vsync: this,
    );
    tabController.addListener(onTabChange);
  }

  void onTabChange() {
    if (index != tabController.index) {
      setState(() {
        index = tabController.index;
      });
    }
  }

  @override
  void didUpdateWidget(covariant _GroupedComicChapters oldWidget) {
    super.didUpdateWidget(oldWidget);
    final groups = widget.chapters.groups.toList();
    final previousGroup = _groups.elementAtOrNull(index);
    history = widget.history;
    if (!listEquals(groups, _groups)) {
      tabController.removeListener(onTabChange);
      tabController.dispose();
      _groups = groups;
      index = math.max(0, groups.indexOf(previousGroup ?? ''));
      showAll = false;
      _createTabs();
    }
  }

  @override
  void dispose() {
    tabController.removeListener(onTabChange);
    tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final chapters = widget.chapters;
    return SliverLayoutBuilder(
      builder: (context, constrains) {
        var group = _groups.isEmpty
            ? const <String, String>{}
            : chapters.getGroupByIndex(index);
        int length = group.length;
        bool canShowAll = showAll;
        if (!showAll) {
          var width = constrains.crossAxisExtent - 16;
          var crossItems = width ~/ 200;
          if (width % 200 != 0) {
            crossItems += 1;
          }
          length = math.min(length, crossItems * 8);
          if (length == group.length) {
            canShowAll = true;
          }
        }

        return SliverMainAxisGroup(
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                child: Wrap(
                  spacing: 16,
                  runSpacing: 8,
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      "Chapters".tl,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    widget.orderControl,
                  ],
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: AppTabBar(
                withUnderLine: false,
                controller: tabController,
                tabs: chapters.groups.map((e) => Tab(text: e)).toList(),
              ),
            ),
            SliverPadding(padding: const EdgeInsets.only(top: 8)),
            SliverGrid(
              delegate: SliverChildBuilderDelegate((context, i) {
                if (widget.reverse) {
                  i = group.length - i - 1;
                }
                var key = group.keys.elementAt(i);
                var value = group[key]!;
                var chapterIndex = 0;
                for (var j = 0; j < chapters.groupCount; j++) {
                  if (j == index) {
                    chapterIndex += i;
                    break;
                  }
                  chapterIndex += chapters.getGroupByIndex(j).length;
                }
                String rawIndex = (chapterIndex + 1).toString();
                String groupedIndex = "${index + 1}-${i + 1}";
                bool visited = false;
                bool last = false;
                if (history != null) {
                  visited =
                      history!.readEpisode.contains(groupedIndex) ||
                      history!.readEpisode.contains(rawIndex);
                  // history.ep is relative to history.group; a missing group
                  // means ep is the raw index across all groups.
                  last = history!.group == null
                      ? history!.ep == chapterIndex + 1
                      : history!.group == index + 1 && history!.ep == i + 1;
                }
                final state = _einkChapterState(visited, last);
                return Padding(
                  padding: const EdgeInsets.fromLTRB(4, 4, 4, 4),
                  child: Material(
                    color: context.isEInk
                        ? _einkChapterFill(context, state)
                        : context.colorScheme.surfaceContainerLow,
                    borderRadius: context.isEInk
                        ? null
                        : BorderRadius.circular(12),
                    shape: context.isEInk ? _einkChapterShape : null,
                    child: ClickInkWell(
                      onTap: () => widget.readChapter(chapterIndex + 1),
                      borderRadius: BorderRadius.circular(12),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        child: Center(
                          child: context.isEInk
                              ? _einkChapterLabel(context, value, state)
                              : Text(
                                  value,
                                  maxLines: 1,
                                  textAlign: TextAlign.center,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: visited
                                        ? context.colorScheme.outline
                                        : null,
                                  ),
                                ),
                        ),
                      ),
                    ),
                  ),
                );
              }, childCount: length),
              gridDelegate: const SliverGridDelegateWithFixedHeight(
                maxCrossAxisExtent: 250,
                itemHeight: 48,
              ),
            ).sliverPadding(const EdgeInsets.symmetric(horizontal: 8)),
            if (!canShowAll)
              SliverToBoxAdapter(
                child: Align(
                  alignment: Alignment.center,
                  child: TextButton.icon(
                    icon: const Icon(Icons.arrow_drop_down),
                    onPressed: () {
                      setState(() {
                        showAll = true;
                      });
                    },
                    label: Text("${"Show all".tl} (${group.length})"),
                  ).paddingTop(12),
                ),
              ),
            const SliverToBoxAdapter(child: Divider()),
          ],
        );
      },
    );
  }
}

class _ChapterOrderSegment extends StatelessWidget {
  const _ChapterOrderSegment({required this.reverse, required this.onChanged});

  final bool reverse;

  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: "Order".tl,
      child: SegmentedButton<bool>(
        selected: {reverse},
        showSelectedIcon: false,
        style: const ButtonStyle(
          visualDensity: VisualDensity.compact,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          padding: WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 10)),
        ),
        segments: [
          ButtonSegment<bool>(value: false, label: Text("Ascending".tl)),
          ButtonSegment<bool>(value: true, label: Text("Descending".tl)),
        ],
        onSelectionChanged: (selected) {
          onChanged(selected.first);
        },
      ),
    );
  }
}
