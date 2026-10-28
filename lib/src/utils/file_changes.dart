import 'dart:io';

/// Collects file changes in memory and applies them all at once.
///
/// Generators record what they want to change here instead of writing to
/// disk directly. Nothing is written until [apply] is called, so if any
/// generator fails (for example because of a hand-made flavor), the project
/// is left exactly as it was: no half-finished setup.
class FileChanges {
  /// New file contents, by absolute path. Writing the same path twice keeps
  /// the last content.
  final _writes = <String, String>{};

  /// Folders to delete before the writes happen.
  final _deletedDirs = <String>[];

  /// Human-readable summaries ("Added 3 flavors to ..."), printed after
  /// [apply] succeeds.
  final _notes = <String>[];

  /// Plans to write [content] to the file at [path].
  void write(String path, String content) => _writes[path] = content;

  /// Plans to delete the folder at [path] and everything inside it.
  void deleteDirectory(String path) => _deletedDirs.add(path);

  /// Adds a summary line to show once the changes are applied.
  void note(String message) => _notes.add(message);

  /// Summaries added with [note], in order.
  List<String> get notes => List.unmodifiable(_notes);

  /// Every planned file (absolute path → new content), in the order added.
  /// Used by `doctor` to compare the plan with what's on disk.
  Map<String, String> get writes => Map.unmodifiable(_writes);

  /// Writes everything to disk: deletions first, then file contents.
  /// Missing parent folders are created.
  void apply() {
    for (final path in _deletedDirs) {
      final dir = Directory(path);
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    }
    _writes.forEach((path, content) {
      File(path)
        ..parent.createSync(recursive: true)
        ..writeAsStringSync(content);
    });
  }
}
