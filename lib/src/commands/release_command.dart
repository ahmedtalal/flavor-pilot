import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

import '../models/flavor.dart';
import '../utils/app_version.dart';
import '../utils/exceptions.dart';
import '../utils/flutter_args.dart';
import 'flavorpilot_command.dart';

/// `flavorpilot release <flavor>`: bumps the version, builds a release, and
/// saves the result with a clear name.
///
/// Examples:
///
/// ```sh
/// flavorpilot release prod                          # build number +1, APK
/// flavorpilot release prod --bump patch --target appbundle
/// flavorpilot release qa --target ipa --bump none
/// ```
///
/// The file is copied to `dist/`, named like
/// `my_app-production-1.2.3+4.apk`, so builds of different flavors and
/// versions never overwrite each other.
class ReleaseCommand extends FlavorPilotCommand {
  ReleaseCommand({
    required super.logger,
    required super.processRunner,
    required super.projectDir,
    super.configLoader,
  }) {
    argParser
      ..addOption(
        'target',
        help: 'What to build.',
        allowed: _extensions.keys,
        defaultsTo: 'apk',
      )
      ..addOption(
        'bump',
        help: 'Which part of the version in pubspec.yaml to increase.',
        allowed: VersionBump.values.map((b) => b.name),
        defaultsTo: VersionBump.build.name,
      )
      ..addOption(
        'out',
        help: 'Folder to copy the finished file into.',
        defaultsTo: 'dist',
      );
  }

  /// Release targets and the file extension each one produces.
  static const _extensions = {'apk': 'apk', 'appbundle': 'aab', 'ipa': 'ipa'};

  /// The `version:` line in pubspec.yaml.
  static final _versionLine = RegExp(r'^version:[ \t]*(\S+)', multiLine: true);

  @override
  String get name => 'release';

  @override
  String get description =>
      'Bump the version, build a release, and save it to dist/.';

  @override
  String get invocation =>
      'flavorpilot release <flavor> [options] [-- flutter args]';

  @override
  Future<int> run() async {
    final config = loadConfig();
    final flavor = resolveFlavor(config);
    final target = argResults!.option('target')!;
    final bump = VersionBump.values.byName(argResults!.option('bump')!);

    // 1. Bump the version, remembering the original file so it can be put
    //    back if the build fails.
    final pubspec = File(p.join(projectDir, 'pubspec.yaml'));
    final original = pubspec.readAsStringSync();
    final version = _bumpVersion(pubspec, original, bump);

    // 2. Build.
    final exitCode = await processRunner.run(
      'flutter',
      flutterArgs(
        command: ['build', target],
        flavor: flavor,
        mode: BuildMode.release,
        entryPoint: config.entryPointFor(flavor),
        extra: passthroughArgs,
      ),
      workingDirectory: projectDir,
    );
    if (exitCode != 0) {
      if (bump != VersionBump.none) {
        pubspec.writeAsStringSync(original);
        logger.warn('Build failed, so the version change was undone.');
      }
      return exitCode;
    }

    // 3. Copy the result to the output folder with a clear name.
    final output = _findOutput(target, flavor);
    if (output == null) {
      logger.warn(
        'Build succeeded, but the output file was not found, so nothing '
        'was copied.',
      );
      return 0;
    }
    final appName = (loadYaml(original) as Map)['name'];
    final destination = p.join(
      projectDir,
      argResults!.option('out')!,
      '$appName-${flavor.name}-$version.${_extensions[target]}',
    );
    Directory(p.dirname(destination)).createSync(recursive: true);
    output.copySync(destination);

    logger.success(
      'Released "${flavor.name}" $version → '
      '${p.relative(destination, from: projectDir)}',
    );
    return 0;
  }

  /// Writes the bumped version into pubspec.yaml and returns it.
  AppVersion _bumpVersion(File pubspec, String content, VersionBump bump) {
    final match = _versionLine.firstMatch(content);
    if (match == null) {
      throw const FlavorPilotException(
        'pubspec.yaml has no "version:" line. Add one like `version: 1.0.0+1`.',
      );
    }
    final current = AppVersion.parse(match[1]!);
    final next = current.bump(bump);
    if (bump != VersionBump.none) {
      pubspec.writeAsStringSync(
        content.replaceFirst(_versionLine, 'version: $next'),
      );
      logger.success('Version $current → $next');
    }
    return next;
  }

  /// Finds the file Flutter just built for [target].
  File? _findOutput(String target, Flavor flavor) {
    final build = p.join(projectDir, 'build');
    switch (target) {
      case 'apk':
        return _existing(
          p.join(
            build,
            'app',
            'outputs',
            'flutter-apk',
            'app-${flavor.name}-release.apk',
          ),
        );
      case 'appbundle':
        return _existing(
          p.join(
            build,
            'app',
            'outputs',
            'bundle',
            '${flavor.name}Release',
            'app-${flavor.name}-release.aab',
          ),
        );
      case 'ipa':
        // The .ipa is named after the app, so take the newest one.
        final dir = Directory(p.join(build, 'ios', 'ipa'));
        if (!dir.existsSync()) return null;
        final ipas =
            dir
                .listSync()
                .whereType<File>()
                .where((f) => f.path.endsWith('.ipa'))
                .toList()
              ..sort(
                (a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()),
              );
        return ipas.firstOrNull;
    }
    return null;
  }

  File? _existing(String path) {
    final file = File(path);
    return file.existsSync() ? file : null;
  }
}
