import 'package:path/path.dart' as p;

import '../config/config_loader.dart';
import '../config/config_writer.dart';
import '../models/project_config.dart';
import '../utils/file_changes.dart';
import '../utils/logger.dart';
import 'android_generator.dart';
import 'dart_generator.dart';
import 'generator.dart';
import 'icon_generator.dart';
import 'ide_generator.dart';
import 'ios_generator.dart';

/// Runs every generator for a config, so `init`, `add`, `sync` and `doctor`
/// all set up a project in exactly the same way.
class ProjectSetup {
  ProjectSetup({required this.projectDir, required this.logger});

  /// Root folder of the Flutter project.
  final String projectDir;

  /// Prints the summary of what changed.
  final Logger logger;

  /// Every generator, in the order they run.
  List<Generator> get generators => [
    AndroidGenerator(projectDir: projectDir, logger: logger),
    IosGenerator(projectDir: projectDir, logger: logger),
    IconGenerator(projectDir: projectDir, logger: logger),
    DartGenerator(projectDir: projectDir, logger: logger),
    IdeGenerator(projectDir: projectDir, logger: logger),
  ];

  /// Works out every file change for [config] without writing anything.
  ///
  /// When [saveConfig] is true, `flavorpilot.yaml` is included in the
  /// changes too (used by `init` and `add`, which create or edit it).
  ///
  /// Throws a FlavorPilotException if any generator can't update its files
  /// safely; in that case nothing should be written.
  FileChanges plan(ProjectConfig config, {bool saveConfig = false}) {
    final changes = FileChanges();
    if (saveConfig) {
      final yaml = const ConfigWriter().toYaml(config);
      // Load the YAML back first: this runs the same checks as every other
      // command (valid names, no duplicate aliases).
      const ConfigLoader().parse(yaml);
      changes
        ..write(p.join(projectDir, ConfigLoader.fileName), yaml)
        ..note('Saved ${ConfigLoader.fileName}');
    }
    for (final generator in generators) {
      generator.generate(config, changes);
    }
    return changes;
  }

  /// Plans all changes for [config], then writes them in one go and prints
  /// a summary. If planning fails, no file is touched.
  void apply(ProjectConfig config, {bool saveConfig = false}) {
    final changes = plan(config, saveConfig: saveConfig)..apply();
    changes.notes.forEach(logger.success);
  }
}
