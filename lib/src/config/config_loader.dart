import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

import '../models/flavor.dart';
import '../models/main_mode.dart';
import '../models/project_config.dart';
import '../utils/env_fields.dart';
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

  /// Env keys are snake_case, so they convert cleanly to Dart field names.
  static final _validEnvKey = RegExp(r'^[a-z][a-z0-9]*(_[a-z0-9]+)*$');

  /// Names an env key can't turn into: existing `AppFlavor` members and Dart
  /// reserved words.
  static const _reservedEnvFields = {
    'appName', 'current', 'hashCode', 'index', 'name', 'noSuchMethod',
    'runtimeType', 'toString', 'values', //
    'assert', 'break', 'case', 'catch', 'class', 'const', 'continue',
    'default', 'do', 'else', 'enum', 'extends', 'false', 'final', 'finally',
    'for', 'if', 'in', 'is', 'new', 'null', 'rethrow', 'return', 'super',
    'switch', 'this', 'throw', 'true', 'try', 'var', 'void', 'while', 'with',
  };

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
    _checkEnvMatches(flavors);

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
      _checkEnvShape(name, data['env']);
      if (data['icon'] != null && data['icon'] is! String) {
        throw FlavorPilotException(
          'Flavor "$name": icon must be a file path, e.g. assets/icons/dev.png.',
        );
      }
      flavors.add(Flavor.fromMap(name, data));
    }
    return flavors;
  }

  /// Checks one flavor's `env:` section: a map of valid keys with simple
  /// values that can become fields on the generated `AppFlavor` enum.
  void _checkEnvShape(String flavor, Object? env) {
    if (env == null) return;
    if (env is! Map) {
      throw FlavorPilotException('Flavor "$flavor": env must be a YAML map.');
    }
    for (final MapEntry(:key, :value) in env.entries) {
      if (!_validEnvKey.hasMatch('$key')) {
        throw FlavorPilotException(
          'Flavor "$flavor": invalid env key "$key". Use lowercase letters, '
          'digits and single underscores, e.g. "base_url".',
        );
      }
      if (_reservedEnvFields.contains(envFieldName('$key'))) {
        throw FlavorPilotException(
          'Flavor "$flavor": env key "$key" is reserved. Pick another name.',
        );
      }
      final isSimple = value is String || value is bool || value is num;
      if (!isSimple) {
        throw FlavorPilotException(
          'Flavor "$flavor": env key "$key" must be a text, number or '
          'true/false.',
        );
      }
      if (value is double && !value.isFinite) {
        throw FlavorPilotException(
          'Flavor "$flavor": env key "$key" must be a finite number.',
        );
      }
    }
  }

  /// Makes sure all flavors define the same env keys with compatible types,
  /// because each key becomes one field on the `AppFlavor` enum.
  void _checkEnvMatches(List<Flavor> flavors) {
    final keys = {for (final flavor in flavors) ...flavor.env.keys};
    final flavorNames = flavors.map((f) => f.name).toSet();
    final fields = <String, String>{};

    for (final key in keys) {
      final missing = flavors.where((f) => !f.env.containsKey(key));
      if (missing.isNotEmpty) {
        final names = missing.map((f) => f.name).join(', ');
        throw FlavorPilotException(
          'env key "$key" is missing from: $names. Every flavor needs the '
          'same env keys.',
        );
      }
      if (envDartType(flavors.map((f) => f.env[key]!)) == null) {
        throw FlavorPilotException(
          'env key "$key" has different types across flavors. Use the same '
          'type (text, number or true/false) in every flavor.',
        );
      }

      // Fields can't share a name with each other or an enum value.
      final field = envFieldName(key);
      if (flavorNames.contains(field)) {
        throw FlavorPilotException(
          'env key "$key" clashes with the flavor named "$field". Pick '
          'another name.',
        );
      }
      final other = fields[field];
      if (other != null) {
        throw FlavorPilotException(
          'env keys "$other" and "$key" both become the field "$field". '
          'Rename one of them.',
        );
      }
      fields[field] = key;
    }
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
