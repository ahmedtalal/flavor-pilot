import 'dart:io';
import 'dart:typed_data';

import 'package:flavorpilot/src/utils/file_changes.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../helpers.dart';

void main() {
  test('writes nothing until apply is called', () {
    final dir = createEmptyDir();
    final changes = FileChanges()..write(p.join(dir, 'a.txt'), 'hello');

    expect(File(p.join(dir, 'a.txt')).existsSync(), isFalse);

    changes.apply();
    expect(readFile(dir, 'a.txt'), 'hello');
  });

  test('creates missing parent folders', () {
    final dir = createEmptyDir();
    FileChanges()
      ..write(p.join(dir, 'x', 'y', 'b.txt'), 'deep')
      ..apply();

    expect(readFile(dir, 'x/y/b.txt'), 'deep');
  });

  test('deletes folders before writing, so new files survive', () {
    final dir = createEmptyDir();
    writeFile(dir, 'gen/old.txt', 'stale');

    FileChanges()
      ..deleteDirectory(p.join(dir, 'gen'))
      ..write(p.join(dir, 'gen', 'new.txt'), 'fresh')
      ..apply();

    expect(File(p.join(dir, 'gen', 'old.txt')).existsSync(), isFalse);
    expect(readFile(dir, 'gen/new.txt'), 'fresh');
  });

  test('writes binary files without changing their bytes', () {
    final dir = createEmptyDir();
    final bytes = Uint8List.fromList([0, 255, 128, 10]);

    FileChanges()
      ..writeBytes(p.join(dir, 'x', 'a.bin'), bytes)
      ..apply();

    expect(File(p.join(dir, 'x', 'a.bin')).readAsBytesSync(), bytes);
  });

  test('deleting a file removes its folder only when it becomes empty', () {
    final dir = createEmptyDir();
    writeFile(dir, 'empty/a.txt', 'a');
    writeFile(dir, 'kept/a.txt', 'a');
    writeFile(dir, 'kept/b.txt', 'b');

    FileChanges()
      ..deleteFile(p.join(dir, 'empty', 'a.txt'))
      ..deleteFile(p.join(dir, 'kept', 'a.txt'))
      ..deleteFile(p.join(dir, 'missing', 'a.txt'))
      ..apply();

    expect(Directory(p.join(dir, 'empty')).existsSync(), isFalse);
    expect(readFile(dir, 'kept/b.txt'), 'b');
  });

  test('keeps notes in order', () {
    final changes = FileChanges()
      ..note('first')
      ..note('second');
    expect(changes.notes, ['first', 'second']);
  });

  group('changedNotes', () {
    test('leaves out notes about files that would not change', () {
      final dir = createEmptyDir();
      writeFile(dir, 'same.txt', 'same');
      writeFile(dir, 'old.txt', 'old');

      final changes = FileChanges()
        ..write(p.join(dir, 'same.txt'), 'same')
        ..note('same')
        ..write(p.join(dir, 'old.txt'), 'new')
        ..note('changed')
        ..write(p.join(dir, 'missing.txt'), 'x')
        ..note('created')
        ..note('no files');

      expect(changes.changedNotes, ['changed', 'created', 'no files']);
      expect(changes.notes, hasLength(4));
    });

    test('a folder emptied and filled with the same files is unchanged', () {
      final dir = createEmptyDir();
      writeFile(dir, 'out/a.txt', 'a');
      final folder = p.join(dir, 'out');

      FileChanges same() => FileChanges()
        ..deleteDirectory(folder)
        ..write(p.join(folder, 'a.txt'), 'a')
        ..note('rewrote out/');
      expect(same().changedNotes, isEmpty);

      writeFile(dir, 'out/stale.txt', 'old flavor');
      expect(same().changedNotes, ['rewrote out/']);
    });

    test('deleting a file only counts when it exists', () {
      final dir = createEmptyDir();
      writeFile(dir, 'there.txt', 'x');

      final changes = FileChanges()
        ..deleteFile(p.join(dir, 'gone.txt'))
        ..note('gone')
        ..deleteFile(p.join(dir, 'there.txt'))
        ..note('there');

      expect(changes.changedNotes, ['there']);
    });
  });
}
