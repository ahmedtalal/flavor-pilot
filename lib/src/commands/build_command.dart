import '../utils/flutter_args.dart';
import 'flavorpilot_command.dart';

/// `flavorpilot build <flavor>`: builds the app for one flavor.
///
/// Examples:
///
/// ```sh
/// flavorpilot build prod                     # flutter build apk --flavor production --release
/// flavorpilot build prod --target appbundle  # Play Store bundle
/// flavorpilot build qa --target ipa          # iOS archive
/// flavorpilot build prod -s                  # one APK per CPU architecture
/// flavorpilot build dev --mode debug
/// ```
class BuildCommand extends FlavorPilotCommand {
  BuildCommand({
    required super.logger,
    required super.processRunner,
    required super.projectDir,
    super.configLoader,
  }) {
    argParser
      ..addOption(
        'target',
        // No `-t` short form on purpose: in Flutter `-t` means the entry
        // file, so reusing it here would confuse people.
        help: 'What to build.',
        allowed: targets,
        defaultsTo: 'apk',
      )
      ..addOption(
        'mode',
        abbr: 'm',
        help: 'Build mode.',
        allowed: BuildMode.values.map((m) => m.name),
        defaultsTo: BuildMode.release.name,
      );
    addSplitPerAbiFlag();
  }

  /// Flutter build targets that support `--flavor`.
  static const targets = ['apk', 'appbundle', 'ios', 'ipa'];

  @override
  String get name => 'build';

  @override
  String get description => 'Build the app for a flavor.';

  @override
  String get invocation =>
      'flavorpilot build <flavor> [options] [-- flutter args]';

  @override
  Future<int> run() async {
    final config = loadConfig();
    final flavor = resolveFlavor(config);
    final target = argResults!.option('target')!;
    final mode = BuildMode.values.byName(argResults!.option('mode')!);
    if (mode == BuildMode.release &&
        (target == 'apk' || target == 'appbundle')) {
      checkSigning(config, flavor, strict: false);
    }

    final args = flutterArgs(
      command: ['build', target],
      flavor: flavor,
      mode: mode,
      entryPoint: config.entryPointFor(flavor),
      extra: [if (splitPerAbi(target)) '--split-per-abi', ...passthroughArgs],
    );

    final exitCode = await processRunner.run(
      'flutter',
      args,
      workingDirectory: projectDir,
    );
    if (exitCode == 0) {
      logger.success('Built "${flavor.name}" successfully.');
    }
    return exitCode;
  }
}
