import '../generators/project_setup.dart';
import '../models/project_config.dart';
import '../utils/exceptions.dart';
import '../utils/flavor_questions.dart';
import '../utils/prompter.dart';
import 'flavorpilot_command.dart';

/// `flavorpilot add <name>`: adds one flavor to an existing setup.
///
/// Examples:
///
/// ```sh
/// flavorpilot add staging                     # asks alias, app name, id
/// flavorpilot add uat --alias uat --yes       # defaults for the rest
/// flavorpilot add qa --app-name "My App QA" --app-id com.example.app.qa
/// ```
///
/// The new flavor is appended to `flavorpilot.yaml`, then every generator
/// runs again so Android, iOS, Dart and IDE files include it.
class AddCommand extends FlavorPilotCommand {
  AddCommand({
    required super.logger,
    required super.processRunner,
    required super.projectDir,
    super.configLoader,
    String? Function()? readLine,
  }) : _readLine = readLine {
    argParser
      ..addOption('alias', help: 'Short name, e.g. "qa".')
      ..addOption('app-name', help: 'App name shown on the device.')
      ..addOption('app-id', help: 'Android applicationId and iOS bundle id.')
      ..addFlag(
        'yes',
        abbr: 'y',
        negatable: false,
        help: 'Use default answers for anything not given as an option.',
      );
  }

  /// Reads the user's answers; replaceable in tests.
  final String? Function()? _readLine;

  @override
  String get name => 'add';

  @override
  String get description => 'Add a new flavor to this project.';

  @override
  String get invocation => 'flavorpilot add <name> [options]';

  @override
  Future<int> run() async {
    final rest = argResults!.rest;
    if (rest.length != 1) {
      usageException(
        'Give exactly one flavor name, e.g. `flavorpilot add qa`.',
      );
    }

    final config = loadConfig();
    final existing = config.findFlavor(rest.single);
    if (existing != null) {
      throw FlavorPilotException(
        '"${rest.single}" is already used by the "${existing.name}" flavor.',
      );
    }

    final questions = FlavorQuestions(
      projectDir: projectDir,
      prompter: Prompter(
        useDefaults: argResults!.flag('yes'),
        readLine: _readLine,
      ),
    );

    // Base the defaults on production when it exists, so a new flavor's id
    // looks like its siblings (e.g. com.example.app.qa).
    final production = config.findFlavor('production');
    final flavor = questions.ask(
      rest.single,
      baseName: production?.appName ?? questions.defaultAppName(),
      baseId: production?.androidId ?? questions.defaultAppId(),
      alias: argResults!.option('alias'),
      appName: argResults!.option('app-name'),
      appId: argResults!.option('app-id'),
    );

    final updated = ProjectConfig(
      flavors: [...config.flavors, flavor],
      mainMode: config.mainMode,
    );
    // Saving the config also validates it, so a duplicate name or alias is
    // rejected before any file changes.
    ProjectSetup(
      projectDir: projectDir,
      logger: logger,
    ).apply(updated, saveConfig: true);

    logger.success('Added flavor "${flavor.name}".');
    return 0;
  }
}
