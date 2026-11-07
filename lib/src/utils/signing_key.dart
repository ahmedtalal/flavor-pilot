import 'dart:io';

import 'package:path/path.dart' as p;

/// An Android signing key, described by a `.properties` file like the one
/// Flutter's docs use:
///
/// ```properties
/// storeFile=upload.jks
/// storePassword=...
/// keyAlias=upload
/// keyPassword=...
/// ```
///
/// `storeFile` is relative to the `.properties` file's folder (or absolute).
class SigningKey {
  SigningKey._(this.propertiesPath, this.values);

  /// The keys every signing `.properties` file needs.
  static const requiredKeys = [
    'storeFile',
    'storePassword',
    'keyAlias',
    'keyPassword',
  ];

  /// Reads the `.properties` file at [path] (relative to [projectDir]).
  /// Returns null when the file doesn't exist.
  static SigningKey? read(String projectDir, String path) {
    final file = File(p.join(projectDir, path));
    if (!file.existsSync()) return null;
    return SigningKey._(path, parseProperties(file.readAsStringSync()));
  }

  /// The `.properties` file's path, as written in `flavorpilot.yaml`.
  final String propertiesPath;

  /// Every key and value in the file.
  final Map<String, String> values;

  /// The keystore file path, relative to the project root (or absolute), or
  /// null when `storeFile` is missing.
  String? get storeFile {
    final store = values['storeFile'];
    if (store == null || store.isEmpty) return null;
    return p.normalize(p.join(p.dirname(propertiesPath), store));
  }

  /// Problems that would make a signed build fail, as readable sentences.
  /// Empty when the key looks ready to use.
  List<String> problems(String projectDir) {
    final missing = [
      for (final key in requiredKeys)
        if ((values[key] ?? '').isEmpty) key,
    ];
    final store = storeFile;
    return [
      if (missing.isNotEmpty)
        '$propertiesPath is missing: ${missing.join(', ')}.',
      if (store != null && !File(p.join(projectDir, store)).existsSync())
        'The keystore $store was not found.',
    ];
  }

  /// Why [value] can't be stored in a signing `.properties` file, or null
  /// when it can.
  ///
  /// Values are kept to plain text that Gradle, Java and flavorpilot all read
  /// the same way: no `\`, no line breaks, no spaces at the start or end.
  static String? unsupportedValue(String value) {
    if (value.contains(r'\')) return r'it contains "\"';
    if (value.contains('\n') || value.contains('\r')) {
      return 'it contains a line break';
    }
    if (value.trim() != value) return 'it starts or ends with a space';
    return null;
  }

  /// Text for a `.properties` file with these [values]. Each value must pass
  /// [unsupportedValue].
  static String format(Map<String, String> values) {
    final buffer = StringBuffer()
      ..writeln('# Android signing key, used by flavorpilot.')
      ..writeln('# Keep this file private: it is in .gitignore. Never share or')
      ..writeln('# commit it, and keep a backup of it and its keystore.');
    values.forEach((key, value) {
      assert(unsupportedValue(value) == null, key);
      buffer.writeln('$key=$value');
    });
    return buffer.toString();
  }

  /// Reads `key=value` lines, skipping blank and comment lines, the same way
  /// the Gradle code flavorpilot writes does.
  static Map<String, String> parseProperties(String text) {
    return {
      for (final line in text.split('\n'))
        if (line.contains('=') && !line.trimLeft().startsWith('#'))
          line.substring(0, line.indexOf('=')).trim(): line
              .substring(line.indexOf('=') + 1)
              .trim(),
    };
  }
}
