import 'package:flutter/material.dart';
import 'package:venera_next/components/menu.dart';
import 'package:venera_next/features/comic_source/comic_source_api.dart';
import 'package:venera_next/features/history/history_api.dart';
import 'package:venera_next/foundation/translations.dart';

enum ChapterMarkAction { read, unread, previous }

List<MenuEntry> chapterMarkMenu({
  required ComicChapterPosition position,
  required History? history,
  required void Function(ChapterMarkAction action) onSelected,
}) {
  final read =
      history != null &&
      isChapterRead(
        history,
        position.historyKey,
        legacyRawKey: position.group == null ? null : '${position.index}',
      );
  final viewed = history?.viewedEpisode.contains(position.historyKey) ?? false;
  return [
    if (!read)
      MenuEntry(
        text: 'Mark as read'.tl,
        icon: Icons.done,
        onClick: () => onSelected(ChapterMarkAction.read),
      ),
    if (read || viewed)
      MenuEntry(
        text: 'Mark as unread'.tl,
        icon: Icons.remove_done,
        onClick: () => onSelected(ChapterMarkAction.unread),
      ),
    if (!position.isFirstInGroup)
      MenuEntry(
        text: 'Mark previous chapters as read'.tl,
        icon: Icons.done_all,
        onClick: () => onSelected(ChapterMarkAction.previous),
      ),
  ];
}

/// Work on a detached record so a failed write cannot change visible state.
History prepareChapterMark({
  required ComicDetails comic,
  required History? latest,
  required ComicChapterPosition position,
  required ChapterMarkAction action,
}) {
  final item =
      latest?.copy() ?? History.fromModel(model: comic, ep: 0, page: 0);
  switch (action) {
    case ChapterMarkAction.read:
      markChaptersRead(item, [position.historyKey]);
    case ChapterMarkAction.unread:
      markChapterUnread(
        item,
        position.historyKey,
        legacyRawKey: position.group == null ? null : '${position.index}',
      );
    case ChapterMarkAction.previous:
      markChaptersRead(item, [
        for (var chapter = 1; chapter < position.chapter; chapter++)
          position.group == null ? '$chapter' : '${position.group}-$chapter',
      ]);
  }
  return item;
}
