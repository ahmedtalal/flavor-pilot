import '../models/project_config.dart';
import 'config_loader.dart';

/// Turns a [ProjectConfig] into the text of `flavorpilot.yaml`.
///
/// The output has the same shape that [ConfigLoader] reads, so a written file
/// can always be loaded back. Saving the text is left to the caller (through
/// FileChanges), so it happens together with the other project changes.
class ConfigWriter {
  const ConfigWriter();

  /// Builds the YAML text for [config].
  String toYaml(ProjectConfig config) {
    final buffer = StringBuffer()
      ..writeln('# flavorpilot config. Docs: run `flavorpilot help`.')
      ..writeln('main_mode: ${config.mainMode.name}')
      ..writeln('flavors:');

    for (final flavor in config.flavors) {
      final fields = flavor.toMap();
      if (fields.isEmpty && flavor.env.isEmpty) {
        // A flavor with no settings is written as `name: {}`.
        buffer.writeln('  ${flavor.name}: {}');
        continue;
      }
      buffer.writeln('  ${flavor.name}:');
      fields.forEach((key, value) {
        buffer.writeln('    $key: ${_quote(value)}');
      });
      if (flavor.env.isNotEmpty) {
        buffer.writeln('    env:');
        flavor.env.forEach((key, value) {
          // Numbers and true/false stay unquoted so they keep their type.
          final text = value is String ? _quote(value) : '$value';
          buffer.writeln('      $key: $text');
        });
      }
    }
    return buffer.toString();
  }

  /// Wraps [value] in double quotes so characters like `:` or `#` in an app
  /// name don't break the YAML. Line breaks are escaped to stay on one line.
  String _quote(String value) {
    final escaped = value
        .replaceAll(r'\', r'\\')
        .replaceAll('"', r'\"')
        .replaceAll('\n', r'\n')
        .replaceAll('\r', r'\r')
        .replaceAll('\t', r'\t');
    return '"$escaped"';
  }
}
