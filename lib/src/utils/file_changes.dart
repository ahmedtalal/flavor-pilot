import 'dart:io';
import 'dart:typed_data';

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

  /// New binary file contents (such as icons), by absolute path.
  final _binaryWrites = <String, Uint8List>{};

  /// Folders to delete before the writes happen.
  final _deletedDirs = <String>[];

  /// Single files to delete before the writes happen.
  final _deletedFiles = <String>[];

  /// Human-readable summaries ("Added 3 flavors to ..."), printed after
  /// [apply] succeeds.
  final _notes = <String>[];

  /// Plans to write [content] to the file at [path].
  void write(String path, String content) => _writes[path] = content;

  /// Plans to write the binary [bytes] to the file at [path].
  void writeBytes(String path, Uint8List bytes) => _binaryWrites[path] = bytes;

  /// Plans to delete the folder at [path] and everything inside it.
  void deleteDirectory(String path) => _deletedDirs.add(path);

  /// Plans to delete the file at [path]. Its folder is removed too if that
  /// leaves it empty.
  void deleteFile(String path) => _deletedFiles.add(path);

  /// Adds a summary line to show once the changes are applied.
  void note(String message) => _notes.add(message);

  /// Summaries added with [note], in order.
  List<String> get notes => List.unmodifiable(_notes);

  /// Every planned text file (absolute path → new content), in the order
  /// added. Used by `doctor` to compare the plan with what's on disk.
  Map<String, String> get writes => Map.unmodifiable(_writes);

  /// Every planned binary file (absolute path → new bytes). Used by `doctor`.
  Map<String, Uint8List> get binaryWrites => Map.unmodifiable(_binaryWrites);

  /// Every file planned for deletion. Used by `doctor`.
  List<String> get deletedFiles => List.unmodifiable(_deletedFiles);

  /// Writes everything to disk: deletions first, then file contents.
  /// Missing parent folders are created.
  void apply() {
    for (final path in _deletedDirs) {
      final dir = Directory(path);
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    }
    for (final path in _deletedFiles) {
      final file = File(path);
      if (!file.existsSync()) continue;
      file.deleteSync();
      if (file.parent.listSync().isEmpty) file.parent.deleteSync();
    }
    _writes.forEach((path, content) {
      File(path)
        ..parent.createSync(recursive: true)
        ..writeAsStringSync(content);
    });
    _binaryWrites.forEach((path, bytes) {
      File(path)
        ..parent.createSync(recursive: true)
        ..writeAsBytesSync(bytes);
    });
  }
}
