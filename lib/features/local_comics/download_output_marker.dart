import 'dart:math';

import 'package:path/path.dart' as p;
import 'package:venera_next/foundation/file_system.dart';
import 'package:venera_next/foundation/log.dart';

/// Ownership evidence a download task leaves in a directory it created: a
/// marker file holding the task's random token. A task deletes such a
/// directory only while the marker still holds its token.
abstract final class DownloadOwnerToken {
  static final pattern = RegExp(r'^[0-9a-f]{32}$');

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
