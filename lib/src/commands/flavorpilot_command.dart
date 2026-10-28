import 'package:args/command_runner.dart';

import '../config/config_loader.dart';
import '../models/flavor.dart';
import '../models/project_config.dart';
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

  /// A short "Available flavors: ..." hint, e.g. `development (dev)`.
  String _available(ProjectConfig config) {
    final names = config.flavors
        .map((f) => f.alias == null ? f.name : '${f.name} (${f.alias})')
        .join(', ');
    return 'Available flavors: $names.';
  }
}
