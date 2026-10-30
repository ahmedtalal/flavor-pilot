import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

import '../generators/android_generator.dart';
import '../models/flavor.dart';
import 'exceptions.dart';
import 'prompter.dart';

/// The questions asked about a flavor, and their default answers.
///
/// Shared by `init` (several flavors) and `add` (one flavor), so both
/// suggest the same names and ids.
class FlavorQuestions {
  FlavorQuestions({required this.projectDir, required this.prompter});

  /// Root folder of the Flutter project, used to read default values.
  final String projectDir;

  /// Asks the questions (or returns defaults with `--yes`).
  final Prompter prompter;

  /// Common flavor names and their usual short aliases.
  static const knownAliases = {
    'development': 'dev',
    'staging': 'stg',
    'production': 'prod',
    'qualityAssurance': 'qa',
    'testing': 'test',
  };

  /// Asks the questions for the flavor called [name].
  ///
  /// Defaults: `production` keeps the plain [baseName] and [baseId]; every
  /// other flavor gets its alias added, e.g. "My App DEV" and
  /// `com.example.app.dev`, so all flavors can be installed on the same
  /// device side by side.
  ///
  /// A value passed in [alias], [appName] or [appId] (from command-line
  /// options) is used as-is and its question is skipped.
  ///
  /// [envDefaults] holds the env keys the flavor needs and their suggested
  /// values, taken from an existing flavor.
  Flavor ask(
    String name, {
    required String baseName,
    required String baseId,
    String? alias,
    String? appName,
    String? appId,
    Map<String, Object> envDefaults = const {},
  }) {
    final isProduction = name == 'production';
    alias ??= prompter.ask(
      '  [$name] short alias',
      defaultValue: knownAliases[name] ?? name,
    );
    appName ??= prompter.ask(
      '  [$name] app name',
      defaultValue: isProduction
          ? baseName
          : '$baseName ${alias.toUpperCase()}',
    );
    appId ??= prompter.ask(
      '  [$name] app id',
      defaultValue: isProduction ? baseId : '$baseId.${alias.toLowerCase()}',
    );

    return Flavor(
      name: name,
      // An alias equal to the name adds nothing, so leave it out.
      alias: alias == name ? null : alias,
      appName: appName,
      androidId: appId,
      iosBundleId: appId,
      env: {
        for (final MapEntry(:key, :value) in envDefaults.entries)
          key: _askEnvValue(name, key, value),
      },
    );
  }

  /// Asks for one env value and converts the answer to the type of [suggested].
  Object _askEnvValue(String flavor, String key, Object suggested) {
    final answer = prompter.ask(
      '  [$flavor] env $key',
      defaultValue: '$suggested',
    );
    return switch (suggested) {
      String() => answer,
      bool() => switch (answer) {
        'true' => true,
        'false' => false,
        _ => throw FlavorPilotException(
          'env key "$key" must be true or false, not "$answer".',
        ),
      },
      _ =>
        num.tryParse(answer) ??
            (throw FlavorPilotException(
              'env key "$key" must be a number, not "$answer".',
            )),
    };
  }

  /// Default app name: the `name:` from pubspec.yaml with a capital first
  /// letter, e.g. `my_app` becomes `My app`.
  String defaultAppName() {
    final file = File(p.join(projectDir, 'pubspec.yaml'));
    final pubspec = file.existsSync()
        ? loadYaml(file.readAsStringSync())
        : null;
    final name = (pubspec is Map ? pubspec['name'] as String? : null) ?? 'app';
    final words = name.replaceAll('_', ' ');
    return words[0].toUpperCase() + words.substring(1);
  }

  /// Default app id: the original `applicationId` from the Android Gradle
  /// file, or `com.example.app` if it can't be found.
  String defaultAppId() {
    final appDir = p.join(projectDir, 'android', 'app');
    for (final fileName in ['build.gradle.kts', 'build.gradle']) {
      final file = File(p.join(appDir, fileName));
      if (!file.existsSync()) continue;
      // Skip our own flavors block, otherwise we'd read a flavor's id and
      // end up with ids like `com.example.app.dev.dev`.
      final gradle = AndroidGenerator.removeGeneratedBlock(
        file.readAsStringSync(),
      );
      final match = RegExp(
        r'applicationId\s*=?\s*"([^"]+)"',
      ).firstMatch(gradle);
      if (match != null) return match.group(1)!;
    }
    return 'com.example.app';
  }
}
