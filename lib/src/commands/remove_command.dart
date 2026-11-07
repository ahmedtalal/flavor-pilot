import 'dart:io';

import 'package:path/path.dart' as p;

import '../config/config_loader.dart';
import '../generators/icon_generator.dart';
import '../generators/project_setup.dart';
import '../models/flavor.dart';
import '../models/project_config.dart';
import '../utils/exceptions.dart';
import '../utils/file_changes.dart';
import '../utils/prompter.dart';
import 'flavorpilot_command.dart';

/// `flavorpilot remove <flavor>`: removes one flavor from the project.
///
/// Examples:
///
/// ```sh
/// flavorpilot remove qa          # asks for confirmation first
/// flavorpilot remove qa --yes    # no question, e.g. in scripts
/// ```
///
/// Deletes the flavor from `flavorpilot.yaml` and everything flavorpilot
/// created for it (Android and iOS setup, icons, IDE run configurations).
/// Files that hold the developer's own work are kept: `lib/main_<flavor>.dart`
/// and a `.env` file with values in it.
class RemoveCommand extends FlavorPilotCommand {
  RemoveCommand({
    required super.logger,
    required super.processRunner,
    required super.projectDir,
    super.configLoader,
    String? Function()? readLine,
  }) : _readLine = readLine {
    argParser.addFlag(
      'yes',
      abbr: 'y',
      negatable: false,
      help: 'Remove without asking for confirmation.',
    );
  }

  /// Reads the user's answer; replaceable in tests.
  final String? Function()? _readLine;

  @override
  String get name => 'remove';

  @override
  String get description => 'Remove a flavor from this project.';

  @override
  String get invocation => 'flavorpilot remove <flavor> [--yes]';

  @override
  Future<int> run() async {
    final rest = argResults!.rest;
    if (rest.length != 1) {
      usageException(
        'Give exactly one flavor name or alias, e.g. `flavorpilot remove qa`.',
      );
    }

    final config = loadConfig();
    final flavor = config.findFlavor(rest.single);
    if (flavor == null) {
      final names = config.flavors.map((f) => f.name).join(', ');
      throw FlavorPilotException(
        'Unknown flavor "${rest.single}". Available flavors: $names.',
      );
    }
    if (config.flavors.length == 1) {
      throw FlavorPilotException(
        '"${flavor.name}" is the only flavor, so it can\'t be removed. Add '
        'another flavor first, or delete ${ConfigLoader.fileName} to stop '
        'using flavorpilot.',
      );
    }

    final updated = config.copyWith(
      flavors: config.flavors.where((f) => f != flavor).toList(),
    );

    // Plan everything before asking, so a problem shows up before the
    // question and nothing is written if any step fails.
    final changes = FileChanges();
    final removed = _planRemoval(flavor, changes);
    final setup = ProjectSetup(projectDir: projectDir, logger: logger);
    setup.plan(updated, saveConfig: true, changes: changes);
    final kept = _keptFiles(flavor, config, updated);

    if (!_confirm(flavor, removed, kept)) {
      logger.info('Nothing was removed.');
      return 0;
    }

    changes.apply();
    for (final path in removed) {
      logger.success('Removed $path');
    }
    changes.notes.forEach(logger.success);
    logger.success('Removed flavor "${flavor.name}".');

    for (final path in kept) {
      logger.warn('Kept $path, because it may hold your own work.');
    }
    for (final path in kept.where(
      (path) => path != config.entryPointFor(flavor),
    )) {
      logger.warn(
        '$path is no longer in .gitignore. Move it somewhere safe outside the '
        'project (or delete it) before your next commit.',
      );
    }
    logger.info(
      'If your code uses AppFlavor.${flavor.name}, update it: that value no '
      'longer exists.',
    );
    return 0;
  }

  /// Plans deleting the files flavorpilot created only for [flavor], which
  /// `sync` keeps on purpose. Returns their paths, relative to the project.
  List<String> _planRemoval(Flavor flavor, FileChanges changes) {
    final removed = <String>[];
    void delete(String path) {
      changes.deleteFile(p.join(projectDir, path));
      removed.add(path);
    }

    // The iOS scheme only points at this flavor's configurations, which are
    // removed, so it would be broken anyway.
    final scheme =
        'ios/Runner.xcodeproj/xcshareddata/xcschemes/${flavor.name}.xcscheme';
    if (_fileContains(scheme, 'buildConfiguration = "Debug-${flavor.name}"')) {
      delete(scheme);
    }

    final runConfig = '.run/${flavor.name}.run.xml';
    if (_fileContains(
      runConfig,
      '<option name="buildFlavor" value="${flavor.name}" />',
    )) {
      delete(runConfig);
    }

    // An .env file that still only has the comments flavorpilot wrote.
    final envFile = flavor.envFile;
    if (envFile != null && _hasNoValues(envFile)) delete(envFile);

    final iconChanges = FileChanges();
    IconGenerator(
      projectDir: projectDir,
      logger: logger,
    ).removeIcons(flavor, iconChanges);
    for (final path in iconChanges.deletedFiles) {
      changes.deleteFile(path);
    }
    if (iconChanges.deletedFiles.isNotEmpty) removed.add('icons');

    return removed;
  }

  /// Files of [flavor] that stay because they may hold the developer's work.
  ///
  /// A signing key only [flavor] used is listed too: keys are never deleted,
  /// since losing one can block app updates.
  List<String> _keptFiles(
    Flavor flavor,
    ProjectConfig config,
    ProjectConfig updated,
  ) {
    final mainFile = config.entryPointFor(flavor);
    final envFile = flavor.envFile;
    final key = flavor.androidSigning;
    final keyStillUsed = updated.flavors.any(
      (f) => updated.signingFor(f) == key,
    );
    return [
      if (mainFile != null && _exists(mainFile)) mainFile,
      if (envFile != null && _exists(envFile) && !_hasNoValues(envFile))
        envFile,
      if (key != null && !keyStillUsed && _exists(key)) key,
    ];
  }

  /// Shows what will happen and asks the user to confirm.
  bool _confirm(Flavor flavor, List<String> removed, List<String> kept) {
    final yes = argResults!.flag('yes');
    if (!yes) {
      logger
        ..info('This removes the flavor "${flavor.name}":')
        ..info('  • its entry in ${ConfigLoader.fileName}')
        ..info('  • its Android flavor, iOS configurations and IDE entries');
      for (final path in removed) {
        logger.info('  • $path');
      }
      for (final path in kept) {
        logger.info('  Kept: $path');
      }
    }
    return Prompter(
      useDefaults: yes,
      readLine: _readLine,
    ).confirm('Remove "${flavor.name}"?', defaultValue: yes);
  }

  bool _exists(String path) => File(p.join(projectDir, path)).existsSync();

  bool _fileContains(String path, String text) =>
      _exists(path) &&
      File(p.join(projectDir, path)).readAsStringSync().contains(text);

  /// True when the .env file at [path] has only comments and blank lines.
  bool _hasNoValues(String path) {
    if (!_exists(path)) return false;
    return File(p.join(projectDir, path))
        .readAsLinesSync()
        .map((line) => line.trim())
        .every((line) => line.isEmpty || line.startsWith('#'));
  }
}
