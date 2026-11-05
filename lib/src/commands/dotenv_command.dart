import '../generators/project_setup.dart';
import '../models/project_config.dart';
import '../utils/env_defaults.dart';
import 'flavorpilot_command.dart';

/// `flavorpilot dotenv`: gives every flavor its own `.env` file.
///
/// Sets `env_file: .env.<flavor>` on every flavor that doesn't have one,
/// then updates the project: the files are created, added to `.gitignore`,
/// and passed to Flutter by `run`, `build`, `release` and the IDE run
/// configurations. `init` asks about this for new projects.
///
/// Existing `.env` files are never changed, so it's safe to run again.
class DotenvCommand extends FlavorPilotCommand {
  DotenvCommand({
    required super.logger,
    required super.processRunner,
    required super.projectDir,
    super.configLoader,
  });

  @override
  String get name => 'dotenv';

  @override
  String get description => 'Create a .env file for every flavor.';

  @override
  Future<int> run() async {
    final config = loadConfig();
    if (config.flavors.every((f) => f.envFile != null)) {
      // Still sync, in case a file was deleted or .gitignore changed.
      ProjectSetup(projectDir: projectDir, logger: logger).apply(config);
      logger.info('Every flavor already has an env_file.');
      return 0;
    }

    ProjectSetup(projectDir: projectDir, logger: logger).apply(
      ProjectConfig(
        flavors: config.flavors.map(withDefaultEnvFile).toList(),
        mainMode: config.mainMode,
      ),
      saveConfig: true,
    );
    logger
      ..info('')
      ..info('Add your values to each .env file, one per line: KEY=value')
      ..info("Read them in Dart with String.fromEnvironment('KEY').");
    return 0;
  }
}
