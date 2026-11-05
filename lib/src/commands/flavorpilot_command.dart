import 'package:args/command_runner.dart';

import '../config/config_loader.dart';
import '../models/flavor.dart';
import '../models/project_config.dart';
import '../utils/env_defaults.dart';
import '../utils/exceptions.dart';
import '../utils/logger.dart';
import '../utils/process_runner.dart';

/// Base class for every flavorpilot command.
///
/// Holds the shared tools each command needs (logger, process runner, config
/// loader) and common helpers, so the commands themselves stay short.
///
/// Each command returns an exit code: 0 means success.
abstract class FlavorPilotCommand extends Command<int> {
  FlavorPilotCommand({
    required this.logger,
    required this.processRunner,
    required this.projectDir,
    this.configLoader = const ConfigLoader(),
  });

  /// Prints messages to the terminal.
  final Logger logger;

  /// Runs external programs like `flutter`.
  final ProcessRunner processRunner;

  /// Root folder of the Flutter project (usually the current directory).
  final String projectDir;

  /// Reads `flavorpilot.yaml`.
  final ConfigLoader configLoader;

  /// Loads the project's `flavorpilot.yaml`.
  ProjectConfig loadConfig() => configLoader.load(projectDir);

  /// Reads the flavor name or alias given as the first positional argument,
  /// e.g. `dev` in `flavorpilot run dev`, and returns the matching flavor.
  ///
  /// Shows the usage help if no flavor was given, and lists the available
  /// flavors if the given one doesn't exist.
  Flavor resolveFlavor(ProjectConfig config) {
    final rest = argResults!.rest;
    if (rest.isEmpty) {
      usageException('Missing flavor. ${_available(config)}');
    }

    final input = rest.first;
    final flavor = config.findFlavor(input);
    if (flavor == null) {
      throw FlavorPilotException(
        'Unknown flavor "$input". ${_available(config)}',
      );
    }
    return flavor;
  }

  /// Arguments typed after the flavor, passed to Flutter as-is.
  ///
  /// In `flavorpilot run dev -- --dart-define=X=1`, this returns
  /// `['--dart-define=X=1']`.
  List<String> get passthroughArgs => argResults!.rest.skip(1).toList();

  /// Adds the `--split-per-abi` flag (shortcuts `--split` and `-s`), shared
  /// by `build` and `release`.
  void addSplitPerAbiFlag() => argParser.addFlag(
    'split-per-abi',
    abbr: 's',
    aliases: const ['split'],
    negatable: false,
    help:
        'Build one smaller APK per CPU architecture instead of one large '
        'APK. Only with --target apk. Also: --split.',
  );

  /// Whether `--split-per-abi` was given. Shows the usage help if it was
  /// combined with a [target] other than `apk`, where Flutter rejects it.
  bool splitPerAbi(String target) {
    final split = argResults!.flag('split-per-abi');
    if (split && target != 'apk') {
      usageException('--split-per-abi only works with --target apk.');
    }
    return split;
  }

  /// Warns about settings in [flavors] that still hold an example value, so
  /// a build doesn't ship with a fake URL by mistake.
  void warnAboutPlaceholders(Iterable<Flavor> flavors) {
    final placeholders = placeholderEnv(flavors);
    if (placeholders.isEmpty) return;
    logger.warn(
      'These env values are still examples: ${placeholders.join(', ')}. '
      'Replace them in flavorpilot.yaml, then run `flavorpilot sync`.',
    );
  }

  /// A short "Available flavors: ..." hint, e.g. `development (dev)`.
  String _available(ProjectConfig config) {
    final names = config.flavors
        .map((f) => f.alias == null ? f.name : '${f.name} (${f.alias})')
        .join(', ');
    return 'Available flavors: $names.';
  }
}
