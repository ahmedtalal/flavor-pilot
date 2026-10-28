import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

import '../models/flavor.dart';
import '../models/main_mode.dart';
import '../models/project_config.dart';
import '../utils/exceptions.dart';

/// Reads and validates `flavorpilot.yaml`.
///
/// Example file:
///
/// ```yaml
/// main_mode: single        # single | multiple
/// flavors:
///   development:
///     alias: dev
///     app_name: My App Dev
///     android_id: com.example.app.dev
///     ios_bundle_id: com.example.app.dev
///   production:
///     alias: prod
///     app_name: My App
/// ```
class ConfigLoader {
  const ConfigLoader();

  /// Name of the config file, expected at the root of the Flutter project.
  static const fileName = 'flavorpilot.yaml';

  /// Flutter/Android flavor names must start with a lowercase letter and
  /// contain only letters and digits (Gradle rejects `-`, spaces, etc.).
  static final _validName = RegExp(r'^[a-z][a-zA-Z0-9]*$');

  /// Loads the config file from [projectDir].
  ///
  /// Throws [FlavorPilotException] if the file is missing or invalid.
  ProjectConfig load(String projectDir) {
    final file = File(p.join(projectDir, fileName));
    if (!file.existsSync()) {
      throw const FlavorPilotException(
        '$fileName not found. Run this command from your Flutter project '
        'root, or run `flavorpilot init` first.',
      );
    }
    return parse(file.readAsStringSync());
  }

  /// Parses the YAML [content] of the config file.
  ///
  /// Kept separate from [load] so tests can pass a string directly.
  ProjectConfig parse(String content) {
    final Object? root;
    try {
      root = loadYaml(content);
    } on YamlException catch (e) {
      throw FlavorPilotException('$fileName is not valid YAML: ${e.message}');
    }
    if (root is! Map) {
      throw const FlavorPilotException('$fileName must be a YAML map.');
    }

    final mainMode = _parseMainMode(root['main_mode']);
    final flavors = _parseFlavors(root['flavors']);
    _checkUniqueNames(flavors);

    return ProjectConfig(flavors: flavors, mainMode: mainMode);
  }

  /// Reads `main_mode`. Defaults to [MainMode.single] when it's missing.
  MainMode _parseMainMode(Object? value) {
    if (value == null) return MainMode.single;
    final mode = MainMode.tryParse(value.toString());
    if (mode == null) {
      final allowed = MainMode.values.map((m) => m.name).join(', ');
      throw FlavorPilotException(
        'Invalid main_mode "$value". Allowed values: $allowed.',
      );
    }
    return mode;
  }

  /// Reads the `flavors:` map and turns each entry into a [Flavor].
  List<Flavor> _parseFlavors(Object? value) {
    if (value is! Map || value.isEmpty) {
      throw const FlavorPilotException(
        '$fileName must define at least one flavor under "flavors:".',
      );
    }

    final flavors = <Flavor>[];
    for (final entry in value.entries) {
      final name = entry.key.toString();
      if (!_validName.hasMatch(name)) {
        throw FlavorPilotException(
          'Invalid flavor name "$name". Use a lowercase first letter and only '
          'letters and digits, e.g. "development" or "qualityAssurance".',
        );
      }
      // A flavor with no settings (`staging:` with nothing under it) is
      // allowed; YAML reads it as null, so treat it as an empty map.
      final data = entry.value ?? const {};
      if (data is! Map) {
        throw FlavorPilotException('Flavor "$name" must be a YAML map.');
      }
      flavors.add(Flavor.fromMap(name, data));
    }
    return flavors;
  }

  /// Makes sure no name or alias is used twice, otherwise
  /// `flavorpilot run dev` could match more than one flavor.
  void _checkUniqueNames(List<Flavor> flavors) {
    final seen = <String>{};
    for (final flavor in flavors) {
      for (final key in [flavor.name, ?flavor.alias]) {
        if (!seen.add(key)) {
          throw FlavorPilotException(
            '"$key" is used more than once as a flavor name or alias.',
          );
        }
      }
    }
  }
}
