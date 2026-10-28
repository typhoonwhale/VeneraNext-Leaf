import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:venera_next/features/local_comics/local_deletion_paths.dart';

void main() {
  test(
    'preserves overlapping references and library ancestors with normalized aliases',
    () {
      final root = p.absolute('fixture');
      final library = p.join(root, 'library');
      String path(String part) => p.join(library, part);
      expect(
        localDirectoriesToDelete(
          libraryPath: library,
          candidates: [
            root,
            library,
            path('shared'),
            path('parent'),
            path('child/a'),
            path('free'),
            path('free/../free'),
          ],
          retained: [path('shared/.'), path('parent/book'), path('child')],
        ),
        [path('free')],
      );
    },
  );

  test('never selects a folder outside the library', () {
    final root = p.absolute('fixture');
    final library = p.join(root, 'library');
    final candidates = [
      p.join(root, 'outside'),
      p.join(library, '..', 'outside'),
      p.join(root, 'library-sibling'),
      library,
      p.join(library, 'inside'),
    ];
    expect(
      localDirectoriesToDelete(
        libraryPath: library,
        candidates: candidates,
        retained: const [],
      ),
      [p.join(library, 'inside')],
    );
    // Only clearing a previous root may select outside the current one.
    expect(
      localDirectoriesToDelete(
        libraryPath: library,
        candidates: candidates,
        retained: const [],
        allowOutsideLibrary: true,
      ),
      [
        p.join(root, 'outside'),
        p.join(root, 'library-sibling'),
        p.join(library, 'inside'),
      ],
    );
  });

  test(
    'rejects aliases that resolve outside or to the library root',
    () async {
      final root = Directory.systemTemp.createTempSync('deletion-outside-');
      try {
        final library = Directory(p.join(root.path, 'library'))..createSync();
        final outside = Directory(p.join(root.path, 'outside'))..createSync();
        final sentinel = File(p.join(outside.path, 'keep'))
          ..writeAsStringSync('keep');
        final toOutside = p.join(library.path, 'to-outside');
        final toLibrary = p.join(library.path, 'to-library');
        final inside = Directory(p.join(library.path, 'inside'))..createSync();
        Link(toOutside).createSync(outside.path);
        Link(toLibrary).createSync(library.path);
        final selected = await resolveLocalDirectoriesToDelete(
          libraryPath: library.path,
          candidates: [
            toOutside,
            toLibrary,
            outside.path,
            library.path,
            inside.path,
          ],
          retained: const [],
          resolvePath: resolveLocalNativePath,
        );
        expect(selected, [inside.path]);
        for (final directory in [toOutside, toLibrary, outside.path]) {
          expect(
            await isLocalDirectoryInsideLibrary(
              directory: directory,
              libraryPath: library.path,
              resolvePath: resolveLocalNativePath,
            ),
            isFalse,
            reason: directory,
          );
        }
        expect(
          await isLocalDirectoryInsideLibrary(
            directory: library.path,
            libraryPath: library.path,
            resolvePath: resolveLocalNativePath,
          ),
          isFalse,
        );
        expect(
          await isLocalDirectoryInsideLibrary(
            directory: inside.path,
            libraryPath: library.path,
            resolvePath: resolveLocalNativePath,
          ),
          isTrue,
        );
        // An identity that cannot be resolved counts as outside.
        expect(
          await isLocalDirectoryInsideLibrary(
            directory: inside.path,
            libraryPath: library.path,
            resolvePath: (path) async =>
                throw FileSystemException('denied', path),
          ),
          isFalse,
        );
        expect(sentinel.readAsStringSync(), 'keep');
      } finally {
        root.deleteSync(recursive: true);
      }
    },
    skip: Platform.isWindows ? 'needs symbolic links' : false,
  );

  test(
    'resolves missing suffixes through an existing native ancestor',
    () async {
      final root = Directory.systemTemp.createTempSync('deletion-identity-');
      try {
        final actual = await root.resolveSymbolicLinks();
        expect(
          await resolveLocalNativePath(p.join(root.path, 'missing', 'child')),
          p.join(actual, 'missing', 'child'),
        );
      } finally {
        root.deleteSync(recursive: true);
      }
    },
  );

  test('identity lookup failure prevents producing a cleanup list', () async {
    final root = p.absolute('fixture');
    await expectLater(
      resolveLocalDirectoriesToDelete(
        libraryPath: p.join(root, 'library'),
        candidates: [p.join(root, 'library', 'delete')],
        retained: [p.join(root, 'unreadable')],
        resolvePath: (path) async {
          if (path.endsWith('unreadable')) throw const FileSystemException();
          return path;
        },
      ),
      throwsA(isA<FileSystemException>()),
    );
  });
}
