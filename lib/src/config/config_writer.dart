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
      if (fields.isEmpty) {
        // A flavor with no settings is written as `name: {}`.
        buffer.writeln('  ${flavor.name}: {}');
        continue;
      }
      buffer.writeln('  ${flavor.name}:');
      fields.forEach((key, value) {
        buffer.writeln('    $key: ${_quote(value)}');
      });
    }
    return buffer.toString();
  }

  /// Wraps [value] in double quotes so characters like `:` or `#` in an app
  /// name don't break the YAML.
  String _quote(String value) {
    final escaped = value.replaceAll(r'\', r'\\').replaceAll('"', r'\"');
    return '"$escaped"';
  }
}
