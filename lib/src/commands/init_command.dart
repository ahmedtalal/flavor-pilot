import 'dart:io';

import 'package:path/path.dart' as p;

import '../config/config_loader.dart';
import '../generators/project_setup.dart';
import '../models/main_mode.dart';
import '../models/project_config.dart';
import '../utils/exceptions.dart';
import '../utils/flavor_questions.dart';
import '../utils/prompter.dart';
import 'flavorpilot_command.dart';

/// `flavorpilot init`: sets up flavors in a Flutter project.
///
/// Steps:
/// 1. Asks a few questions (flavor names, aliases, app names, ids, and
///    whether each flavor gets its own main file).
/// 2. Saves the answers to `flavorpilot.yaml`.
/// 3. Runs every generator to update Android, iOS, Dart and IDE files.
///
/// Use `--yes` to skip the questions and accept all defaults.
class InitCommand extends FlavorPilotCommand {
  InitCommand({
    required super.logger,
    required super.processRunner,
    required super.projectDir,
    super.configLoader,
    String? Function()? readLine,
  }) : _readLine = readLine {
    argParser
      ..addFlag(
        'yes',
        abbr: 'y',
        negatable: false,
        help: 'Skip the questions and use the default answers.',
      )
      ..addFlag(
        'force',
        negatable: false,
        help: 'Overwrite an existing flavorpilot.yaml.',
      );
  }

  /// Reads the user's answers; replaceable in tests.
  final String? Function()? _readLine;

  @override
  String get name => 'init';

  @override
  String get description => 'Set up flavors in this Flutter project.';

  @override
  Future<int> run() async {
    _checkIsFlutterProject();
    _checkNotInitialized();

    final prompter = Prompter(
      useDefaults: argResults!.flag('yes'),
      readLine: _readLine,
    );
    final config = _askQuestions(prompter);

    // Plans every change first and writes them together, so a failure
    // leaves the project exactly as it was.
    ProjectSetup(
      projectDir: projectDir,
      logger: logger,
    ).apply(config, saveConfig: true);

    _printNextSteps(config);
    return 0;
  }

  /// Stops early when the current folder isn't a Flutter project.
  void _checkIsFlutterProject() {
    if (!File(p.join(projectDir, 'pubspec.yaml')).existsSync()) {
      throw const FlavorPilotException(
        'No pubspec.yaml found. Run this command from your Flutter project root.',
      );
    }
  }

  /// Stops early when flavors were already set up, unless `--force` is used.
  void _checkNotInitialized() {
    final exists = File(p.join(projectDir, ConfigLoader.fileName)).existsSync();
    if (exists && !argResults!.flag('force')) {
      throw const FlavorPilotException(
        '${ConfigLoader.fileName} already exists. Use `flavorpilot sync` to '
        'apply changes from it, or --force to start over.',
      );
    }
    if (exists) _warnAboutLostSettings();
  }

  /// Warns that `--force` replaces env values and icons, which `init` doesn't
  /// ask about.
  void _warnAboutLostSettings() {
    try {
      final hasExtras = configLoader
          .load(projectDir)
          .flavors
          .any((f) => f.env.isNotEmpty || f.icon != null);
      if (hasExtras) {
        logger.warn(
          '--force replaces ${ConfigLoader.fileName}, so its env values and '
          'icons will be lost.',
        );
      }
    } on FlavorPilotException {
      // The old file is broken, so there's nothing worth warning about.
    }
  }

  /// Asks the setup questions and builds the config from the answers.
  ProjectConfig _askQuestions(Prompter prompter) {
    final questions = FlavorQuestions(
      projectDir: projectDir,
      prompter: prompter,
    );
    final baseName = prompter.ask(
      'App name',
      defaultValue: questions.defaultAppName(),
    );
    final baseId = prompter.ask(
      'Base app id (Android applicationId / iOS bundle id)',
      defaultValue: questions.defaultAppId(),
    );
    final names = prompter
        .ask(
          'Flavors (comma separated)',
          defaultValue: 'development,staging,production',
        )
        .split(',')
        .map((name) => name.trim())
        .where((name) => name.isNotEmpty)
        .toList();

    final flavors = [
      for (final name in names)
        questions.ask(name, baseName: baseName, baseId: baseId),
    ];

    final separateMains = prompter.confirm(
      'Create a separate main file for each flavor?',
      defaultValue: false,
    );

    return ProjectConfig(
      flavors: flavors,
      mainMode: separateMains ? MainMode.multiple : MainMode.single,
    );
  }

  /// Tells the developer what's left to do by hand.
  void _printNextSteps(ProjectConfig config) {
    final first = config.flavors.first;
    logger
      ..info('')
      ..success('Flavors are ready on Android and iOS.')
      ..info('')
      ..info('Next steps:')
      ..info(
        '  • Use AppFlavor.current (lib/flavors.dart) to read the flavor in '
        'your code.',
      )
      ..info(
        '  • iOS with CocoaPods: run `pod install` in ios/. If ios/Podfile '
        'is created later, run `flavorpilot sync`.',
      )
      ..info('  • Try it: flavorpilot run ${first.alias ?? first.name}');
  }
}
