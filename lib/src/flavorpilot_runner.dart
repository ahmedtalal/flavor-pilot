import 'dart:io';

import 'package:args/command_runner.dart';

import 'commands/add_command.dart';
import 'commands/build_command.dart';
import 'commands/doctor_command.dart';
import 'commands/init_command.dart';
import 'commands/release_command.dart';
import 'commands/run_command.dart';
import 'commands/sync_command.dart';
import 'utils/exceptions.dart';
import 'utils/logger.dart';
import 'utils/process_runner.dart';
import 'version.dart';

/// The top-level `flavorpilot` command.
///
/// Registers every sub-command (run, build, ...), parses the arguments, and
/// turns errors into friendly messages and exit codes.
class FlavorPilotRunner extends CommandRunner<int> {
  FlavorPilotRunner({
    Logger? logger,
    ProcessRunner? processRunner,
    String? projectDir,
  }) : _logger = logger ?? Logger(),
       super('flavorpilot', 'Set up and manage Flutter flavors in one place.') {
    // Dependencies are injectable so tests can pass fakes.
    final runner = processRunner ?? ProcessRunner(_logger);
    final dir = projectDir ?? Directory.current.path;

    argParser.addFlag(
      'version',
      negatable: false,
      help: 'Print the flavorpilot version.',
    );

    // Setup commands.
    addCommand(
      InitCommand(logger: _logger, processRunner: runner, projectDir: dir),
    );
    addCommand(
      AddCommand(logger: _logger, processRunner: runner, projectDir: dir),
    );
    addCommand(
      SyncCommand(logger: _logger, processRunner: runner, projectDir: dir),
    );
    addCommand(
      DoctorCommand(logger: _logger, processRunner: runner, projectDir: dir),
    );
    // Everyday commands.
    addCommand(
      RunCommand(logger: _logger, processRunner: runner, projectDir: dir),
    );
    addCommand(
      BuildCommand(logger: _logger, processRunner: runner, projectDir: dir),
    );
    addCommand(
      ReleaseCommand(logger: _logger, processRunner: runner, projectDir: dir),
    );
  }

  final Logger _logger;

  /// Runs flavorpilot with [args] and returns the exit code.
  ///
  /// Exit codes follow the common Unix convention:
  /// - 0: success
  /// - 1: a known error (bad config, unknown flavor, ...)
  /// - 64: wrong usage (missing or invalid arguments)
  @override
  Future<int> run(Iterable<String> args) async {
    try {
      final results = parse(args);
      if (results.flag('version')) {
        _logger.info('flavorpilot $packageVersion');
        return 0;
      }
      // `runCommand` returns null when only help was printed.
      return await runCommand(results) ?? 0;
    } on UsageException catch (e) {
      _logger.error(e.message);
      _logger.info('');
      _logger.info(e.usage);
      return 64;
    } on FlavorPilotException catch (e) {
      _logger.error(e.message);
      return 1;
    }
  }
}
