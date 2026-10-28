import '../utils/flutter_args.dart';
import 'flavorpilot_command.dart';

/// `flavorpilot run <flavor>`: runs the app for one flavor.
///
/// Examples:
///
/// ```sh
/// flavorpilot run dev                       # flutter run --flavor development --debug
/// flavorpilot run prod --mode release       # ... --release
/// flavorpilot run dev -d emulator-5554      # pick a device
/// flavorpilot run dev -- --dart-define=X=1  # extra Flutter flags after --
/// ```
class RunCommand extends FlavorPilotCommand {
  RunCommand({
    required super.logger,
    required super.processRunner,
    required super.projectDir,
    super.configLoader,
  }) {
    argParser
      ..addOption(
        'mode',
        abbr: 'm',
        help: 'Build mode to run in.',
        allowed: BuildMode.values.map((m) => m.name),
        defaultsTo: BuildMode.debug.name,
      )
      ..addOption(
        'device',
        abbr: 'd',
        help: 'Device id to run on (same as `flutter run -d`).',
      );
  }

  @override
  String get name => 'run';

  @override
  String get description => 'Run the app for a flavor.';

  @override
  String get invocation =>
      'flavorpilot run <flavor> [options] [-- flutter args]';

  @override
  Future<int> run() async {
    final config = loadConfig();
    final flavor = resolveFlavor(config);
    final device = argResults!.option('device');

    final args = flutterArgs(
      command: ['run'],
      flavor: flavor,
      mode: BuildMode.values.byName(argResults!.option('mode')!),
      entryPoint: config.entryPointFor(flavor),
      extra: [
        if (device != null) ...['-d', device],
        ...passthroughArgs,
      ],
    );

    return processRunner.run('flutter', args, workingDirectory: projectDir);
  }
}
