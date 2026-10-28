import '../generators/project_setup.dart';
import 'flavorpilot_command.dart';

/// `flavorpilot sync`: re-applies `flavorpilot.yaml` to the project.
///
/// Use it after editing `flavorpilot.yaml` by hand (for example to change an
/// app name or id), or after `ios/Podfile` was created by Flutter. It's safe
/// to run any number of times.
class SyncCommand extends FlavorPilotCommand {
  SyncCommand({
    required super.logger,
    required super.processRunner,
    required super.projectDir,
    super.configLoader,
  });

  @override
  String get name => 'sync';

  @override
  String get description =>
      'Update Android, iOS, Dart and IDE files from flavorpilot.yaml.';

  @override
  Future<int> run() async {
    final config = loadConfig();
    ProjectSetup(projectDir: projectDir, logger: logger).apply(config);
    return 0;
  }
}
