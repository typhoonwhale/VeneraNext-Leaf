import 'dart:math';

import 'package:path/path.dart' as p;
import 'package:venera_next/foundation/file_system.dart';
import 'package:venera_next/foundation/log.dart';

/// Ownership evidence a download task leaves in a directory it created: a
/// marker file holding the task's random token. A task deletes such a
/// directory only while the marker still holds its token.
abstract final class DownloadOwnerToken {
  static final pattern = RegExp(r'^[0-9a-f]{32}$');

  /// Marker names of image and archive downloads. Dot files are ignored by
  /// comic storage.
  static const imagesMarker = '.venera-images-download';
  static const archiveMarker = '.venera-archive-download';
  static const _markers = [imagesMarker, archiveMarker];

  /// Whether [directory] carries a well-formed marker of either task kind.
  static bool hasOutputMarker(String directory) =>
      outputToken(directory) != null;

  /// The token of the first well-formed marker in [directory], if any.
  static String? outputToken(String directory) {
    for (final marker in _markers) {
      final path = FilePath.join(directory, marker);
      try {
        if (FileSystemEntity.typeSync(path, followLinks: false) ==
            FileSystemEntityType.file) {
          final token = File(path).readAsStringSync();
          if (pattern.hasMatch(token)) return token;
        }
      } catch (error, stack) {
        Log.error('Download', error, stack);
      }
    }
    return null;
  }

  /// Real directories directly under [root] that carry a download marker but
  /// belong to no restored task and no registered comic: outputs left by a
  /// task that no longer exists. A marker holding one of [tokens] belongs to
  /// a restored task even if that task's path names another folder. Links
  /// are never followed.
  static List<Directory> orphanOutputs({
    required String root,
    required Iterable<String> referenced,
    Iterable<String> tokens = const [],
  }) {
    String normalize(String path) => p.normalize(p.absolute(path));
    final kept = referenced.map(normalize).toList();
    final keptTokens = tokens.toSet();
    final orphans = <Directory>[];
    for (final entry in Directory(root).listSync(followLinks: false)) {
      if (entry is! Directory) continue;
      final path = normalize(entry.path);
      if (!p.equals(p.dirname(path), normalize(root)) ||
          p.basename(path).startsWith('.venera-delete-') ||
          kept.any(
            (other) =>
                p.equals(other, path) ||
                p.isWithin(other, path) ||
                p.isWithin(path, other),
          )) {
        continue;
      }
      final token = outputToken(entry.path);
      if (token == null || keptTokens.contains(token)) continue;
      orphans.add(entry);
    }
    return orphans;
  }

  static String create() {
    final random = Random.secure();
    return List.generate(
      16,
      (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
  }

  /// Whether [path] is a regular file holding exactly [token].
  static bool isHeldBy(String path, String token) =>
      FileSystemEntity.typeSync(path, followLinks: false) ==
          FileSystemEntityType.file &&
      File(path).readAsStringSync() == token;

  static Future<void> write(String path, String token) =>
      File(path).writeAsString(token, flush: true);

  /// An output is the task's only if it is a real directory directly under
  /// [root] that still carries [marker] with [token].
  static bool ownsOutput({
    required String root,
    required String outputPath,
    required String marker,
    required String token,
  }) {
    try {
      final name = p.basename(outputPath);
      return name != '.' &&
          name != '..' &&
          p.equals(p.dirname(outputPath), root) &&
          FileSystemEntity.typeSync(outputPath, followLinks: false) ==
              FileSystemEntityType.directory &&
          isHeldBy(FilePath.join(outputPath, marker), token);
    } catch (error, stack) {
      Log.error('Download', error, stack);
      return false;
    }
  }
}
