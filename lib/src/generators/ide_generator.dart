import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../models/project_config.dart';
import '../utils/file_changes.dart';
import 'generator.dart';

/// Adds a run configuration per flavor for VS Code and Android Studio, so
/// developers can also pick a flavor from the IDE's Run menu.
///
/// - VS Code: entries in `.vscode/launch.json`. Existing entries are kept;
///   only entries named `<flavor> (flavorpilot)` are replaced.
/// - Android Studio: one `.run/<flavor>.run.xml` file per flavor.
class IdeGenerator extends Generator {
  IdeGenerator({required super.projectDir, required super.logger});

  /// Suffix added to our VS Code entries so we can find and replace them
  /// later without touching the developer's own entries.
  static const _vscodeSuffix = ' (flavorpilot)';

  @override
  String get label => 'IDE';

  @override
  void generate(ProjectConfig config, FileChanges changes) {
    _writeVsCode(config, changes);
    _writeAndroidStudio(config, changes);
  }

  /// Adds or replaces our entries in `.vscode/launch.json`.
  void _writeVsCode(ProjectConfig config, FileChanges changes) {
    final file = File(p.join(projectDir, '.vscode', 'launch.json'));

    var launch = <String, dynamic>{'version': '0.2.0', 'configurations': []};
    if (file.existsSync()) {
      try {
        launch = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
      } on FormatException {
        // VS Code allows comments in launch.json, but Dart's JSON parser
        // doesn't. Skip instead of risking the developer's file.
        logger.warn(
          '.vscode/launch.json has comments or invalid JSON, so VS Code '
          'configurations were skipped.',
        );
        return;
      }
    }

    // Keep every entry that isn't ours, then add fresh ones.
    final kept = (launch['configurations'] as List? ?? [])
        .where((c) => !'${(c as Map)['name']}'.endsWith(_vscodeSuffix))
        .toList();
    final ours = config.flavors.map((flavor) {
      final entryPoint = config.entryPointFor(flavor);
      return {
        'name': '${flavor.name}$_vscodeSuffix',
        'request': 'launch',
        'type': 'dart',
        'program': ?entryPoint,
        'args': ['--flavor', flavor.name],
      };
    });
    launch['configurations'] = [...kept, ...ours];

    changes
      ..write(
        file.path,
        '${const JsonEncoder.withIndent('  ').convert(launch)}\n',
      )
      ..note('Updated .vscode/launch.json');
  }

  /// Writes one Android Studio run configuration file per flavor.
  void _writeAndroidStudio(ProjectConfig config, FileChanges changes) {
    final dir = p.join(projectDir, '.run');

    for (final flavor in config.flavors) {
      final entryPoint = config.entryPointFor(flavor) ?? 'lib/main.dart';
      changes.write(p.join(dir, '${flavor.name}.run.xml'), '''
<component name="ProjectRunConfigurationManager">
  <configuration default="false" name="${flavor.name}" type="FlutterRunConfigurationType" factoryName="Flutter">
    <option name="buildFlavor" value="${flavor.name}" />
    <option name="filePath" value="\$PROJECT_DIR\$/$entryPoint" />
    <method v="2" />
  </configuration>
</component>
''');
    }
    changes.note('Wrote Android Studio run configurations in .run/');
  }
}
