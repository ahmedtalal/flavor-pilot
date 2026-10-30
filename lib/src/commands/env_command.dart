import '../generators/project_setup.dart';
import '../models/project_config.dart';
import '../utils/env_defaults.dart';
import 'flavorpilot_command.dart';

/// `flavorpilot env`: adds example env settings to an existing setup.
///
/// Adds `base_url` and `enable_logs` to every flavor in `flavorpilot.yaml`,
/// then updates the project, so `AppFlavor.current.baseUrl` works right away.
/// `init` already does this for new projects.
///
/// Values already in the file are never changed, so it's safe to run again.
class EnvCommand extends FlavorPilotCommand {
  EnvCommand({
    required super.logger,
    required super.processRunner,
    required super.projectDir,
    super.configLoader,
  });

  @override
  String get name => 'env';

  @override
  String get description => 'Add example env settings to every flavor.';

  @override
  Future<int> run() async {
    final config = loadConfig();
    final flavors = config.flavors.map(withDefaultEnv).toList();

    final nothingToAdd = flavors.every(
      (flavor) =>
          flavor.env.length == config.findFlavor(flavor.name)!.env.length,
    );
    if (nothingToAdd) {
      logger.info('Every flavor already has the example env settings.');
      warnAboutPlaceholders(flavors);
      return 0;
    }

    ProjectSetup(projectDir: projectDir, logger: logger).apply(
      ProjectConfig(flavors: flavors, mainMode: config.mainMode),
      saveConfig: true,
    );
    logger.info('Use them in your app: AppFlavor.current.baseUrl');
    warnAboutPlaceholders(flavors);
    return 0;
  }
}
