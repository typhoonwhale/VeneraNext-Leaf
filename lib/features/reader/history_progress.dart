import 'package:venera_next/features/comic_source/comic_source_api.dart';
import 'package:venera_next/features/history/history_api.dart';
import 'page_layout.dart';
import 'read_progress_tracker.dart';

/// Map a loaded viewport to the existing persisted history coordinates.
/// The caller gates loading and owns persistence scheduling.
void applyReaderHistoryProgress({
  required History history,
  required int page,
  required int imageCount,
  required int chapter,
  required ComicChapters? chapters,
  required ReaderPageLayout layout,
  required DateTime time,
  Iterable<ReaderReadVerdict> verdicts = const [],
}) {
  history.page = layout.historyImage(page, imageCount);
  history.maxPage = imageCount;
  history.maxChapter = null;
  history.chapterTitle = null;
  history.groupTitle = null;
  if (chapters != null && chapter >= 1 && chapter <= chapters.length) {
    final position = chapters.positionAt(chapter);
    history.maxChapter = position.groupLength;
    if (position.group case final group?) {
      history.groupTitle = chapters.groups.elementAt(group - 1);
      history.chapterTitle = chapters
          .getGroupByIndex(group - 1)
          .values
          .elementAt(position.chapter - 1);
    } else {
      history.chapterTitle = chapters.allChapters.values.elementAt(chapter - 1);
    }
  }
  if (chapters?.isGrouped ?? false) {
    final position = chapters!.positionAt(chapter);
    history.ep = position.chapter;
    history.group = position.group;
  } else {
    history.ep = chapter;
    // Preserve the existing ungrouped update contract: do not rewrite group.
  }
  history.time = time;
  applyReaderReadVerdicts(history, verdicts);
}

/// Also used by a visible tail/failed forward turn, which must not move ep/page.
void applyReaderReadVerdicts(
  History history,
  Iterable<ReaderReadVerdict> verdicts,
) {
  for (final verdict in verdicts) {
    if (verdict.completed) {
      markChaptersRead(history, [verdict.key]);
    } else if (!isChapterRead(
      history,
      verdict.key,
      legacyRawKey: verdict.legacyRawKey,
    )) {
      history.viewedEpisode.add(verdict.key);
    }
  }
}
