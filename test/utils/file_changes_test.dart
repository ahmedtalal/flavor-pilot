import 'dart:io';

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

  test('keeps notes in order', () {
    final changes = FileChanges()
      ..note('first')
      ..note('second');
    expect(changes.notes, ['first', 'second']);
  });
}
