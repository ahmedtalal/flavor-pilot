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
  /// [apply] succeeds, each with the paths planned just before it.
  final _notes = <(String, List<String>)>[];

  /// Paths planned since the last [note]; they belong to the next one.
  var _pending = <String>[];

  /// Plans to write [content] to the file at [path].
  void write(String path, String content) {
    _writes[path] = content;
    _pending.add(path);
  }

  /// Plans to write the binary [bytes] to the file at [path].
  void writeBytes(String path, Uint8List bytes) {
    _binaryWrites[path] = bytes;
    _pending.add(path);
  }

  /// Plans to delete the folder at [path] and everything inside it.
  void deleteDirectory(String path) {
    _deletedDirs.add(path);
    _pending.add(path);
  }

  /// Plans to delete the file at [path]. Its folder is removed too if that
  /// leaves it empty.
  void deleteFile(String path) {
    _deletedFiles.add(path);
    _pending.add(path);
  }

  /// Adds a summary line to show once the changes are applied. It describes
  /// the changes planned since the previous note.
  void note(String message) {
    _notes.add((message, _pending));
    _pending = [];
  }

  /// Summaries added with [note], in order.
  List<String> get notes => [for (final (message, _) in _notes) message];

  /// The [notes] whose changes would really change the disk. A note about a
  /// file that already has the planned content is left out, so commands
  /// only report what they actually changed. Call before [apply].
  List<String> get changedNotes => [
    for (final (message, paths) in _notes)
      if (paths.isEmpty || paths.any(_changes)) message,
  ];

  /// Whether the planned change at [path] differs from what's on disk.
  bool _changes(String path) {
    final file = File(path);
    if (_writes[path] case final content?) {
      return !file.existsSync() || file.readAsStringSync() != content;
    }
    if (_binaryWrites[path] case final bytes?) {
      return !file.existsSync() || !_sameBytes(file.readAsBytesSync(), bytes);
    }
    if (_deletedDirs.contains(path)) {
      // A folder that is emptied and filled again only changes if it holds
      // a file that won't be written back.
      final dir = Directory(path);
      return dir.existsSync() &&
          dir
              .listSync(recursive: true)
              .whereType<File>()
              .any(
                (f) =>
                    !_writes.containsKey(f.path) &&
                    !_binaryWrites.containsKey(f.path),
              );
    }
    return file.existsSync(); // A file to delete.
  }

  static bool _sameBytes(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

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
