import 'history_model.dart';

/// Mark [keys] as read and remove them from the viewed-only state.
void markChaptersRead(History history, Iterable<String> keys) {
  for (final key in keys) {
    history.readEpisode.add(key);
    history.viewedEpisode.remove(key);
  }
}

/// Remove both read states for a chapter, including its legacy flat key.
void markChapterUnread(History history, String key, {String? legacyRawKey}) {
  history.readEpisode.remove(key);
  history.viewedEpisode.remove(key);
  if (legacyRawKey != null) {
    history.readEpisode.remove(legacyRawKey);
    history.viewedEpisode.remove(legacyRawKey);
  }
}

/// Legacy flat keys remain valid alongside the current grouped chapter key.
bool isChapterRead(History history, String key, {String? legacyRawKey}) =>
    history.readEpisode.contains(key) ||
    (legacyRawKey != null && history.readEpisode.contains(legacyRawKey));
