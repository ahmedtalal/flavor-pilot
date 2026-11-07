import 'dart:io';

import 'package:path/path.dart' as p;

import '../models/flavor.dart';
import '../models/project_config.dart';
import '../utils/exceptions.dart';
import '../utils/file_changes.dart';
import 'generator.dart';

/// Sets up flavors for Android.
///
/// It does two things:
/// 1. Adds a `productFlavors` block to `android/app/build.gradle(.kts)`, with
///    an applicationId and an app name for every flavor.
/// 2. Changes the app label in `AndroidManifest.xml` to `@string/app_name`,
///    so each flavor shows its own name on the device.
///
/// The Gradle block is wrapped in `// flavorpilot:start` and
/// `// flavorpilot:end` comments. On the next run the old block is removed
/// and a fresh one is written, so the file never gets duplicates.
///
/// When flavors use signing keys (`android_signing`), the block also loads
/// them, and a second small block at the end of the file stops the release
/// build type from forcing the debug key. Flutter's template sets that, and
/// a build type's key wins over a flavor's. A key file that's missing (for
/// example on a teammate's computer) falls back to the debug key, so builds
/// still work; `flavorpilot release` refuses to build without it.
class AndroidGenerator extends Generator {
  AndroidGenerator({required super.projectDir, required super.logger});

  static const _startMarker = '// flavorpilot:start';
  static const _endMarker = '// flavorpilot:end';

  /// Matches a block we wrote earlier, including its trailing newline.
  static final _oldBlock = RegExp(
    '[ \\t]*$_startMarker.*?$_endMarker[^\\n]*\\n?',
    dotAll: true,
  );

  /// Matches the `android {` line where the flavors block gets inserted.
  static final _androidBlockStart = RegExp(
    r'^android\s*\{[ \t]*$',
    multiLine: true,
  );

  /// Matches the app label inside the `<application ...>` tag.
  static final _manifestLabel = RegExp(
    r'(<application[^>]*?android:label=")([^"]*)(")',
  );

  /// Returns [gradle] without the block flavorpilot wrote earlier.
  ///
  /// Also used by `init` to read the original `applicationId`, so it doesn't
  /// pick up a flavor's id (like `com.example.app.dev`) by mistake.
  static String removeGeneratedBlock(String gradle) =>
      gradle.replaceAll(_oldBlock, '');

  @override
  String get label => 'Android';

  @override
  void generate(ProjectConfig config, FileChanges changes) {
    _updateGradle(config, changes);
    _updateManifest(changes);
  }

  /// Writes the `productFlavors` block into the app's Gradle file.
  void _updateGradle(ProjectConfig config, FileChanges changes) {
    final appDir = p.join(projectDir, 'android', 'app');
    final kotlinFile = File(p.join(appDir, 'build.gradle.kts'));
    final groovyFile = File(p.join(appDir, 'build.gradle'));

    // New Flutter projects use Kotlin (.kts); older ones use Groovy.
    final isKotlin = kotlinFile.existsSync();
    final file = isKotlin ? kotlinFile : groovyFile;
    if (!file.existsSync()) {
      logger.warn('No android/app/build.gradle(.kts) found, skipping Android.');
      return;
    }

    // Remove our old block first, so re-running replaces it.
    final content = removeGeneratedBlock(file.readAsStringSync());

    // Flavors written by hand would clash with ours, so stop and let the
    // developer decide instead of guessing.
    if (content.contains('productFlavors')) {
      throw FlavorPilotException(
        '${p.relative(file.path, from: projectDir)} already has '
        'productFlavors that were not created by flavorpilot. '
        'Remove them first, then run this command again.',
      );
    }

    final match = _androidBlockStart.firstMatch(content);
    if (match == null) {
      throw FlavorPilotException(
        'Could not find the "android {" block in ${file.path}.',
      );
    }

    // Insert on the line right after `android {`. Inserting after the
    // newline (not before it) means removing the block later restores the
    // file exactly, so repeated runs don't pile up blank lines.
    final keys = _signingKeys(config);
    final block = isKotlin
        ? _kotlinBlock(config, keys)
        : _groovyBlock(config, keys);
    final lineEnd = content.indexOf('\n', match.end);
    final at = lineEnd == -1 ? content.length : lineEnd + 1;
    var updated =
        '${content.substring(0, at)}${lineEnd == -1 ? '\n' : ''}$block'
        '${content.substring(at)}';
    if (keys.isNotEmpty) {
      if (!updated.endsWith('\n')) updated += '\n';
      updated += isKotlin ? _kotlinReleaseBlock : _groovyReleaseBlock;
    }
    changes
      ..write(file.path, updated)
      ..note(
        'Added ${config.flavors.length} flavors to '
        '${p.relative(file.path, from: projectDir)}',
      );
  }

  /// Gradle names for each signing key file, in the order first used,
  /// e.g. `{'android/keys/upload.properties': 'flavorpilotKey0'}`.
  Map<String, String> _signingKeys(ProjectConfig config) {
    final keys = <String, String>{};
    for (final flavor in config.flavors) {
      final path = config.signingFor(flavor);
      if (path != null) {
        keys.putIfAbsent(path, () => 'flavorpilotKey${keys.length}');
      }
    }
    return keys;
  }

  /// [path] (from the project root, or absolute) as Gradle's `file()` in
  /// `android/app` reads it.
  String _gradlePath(String path) {
    if (p.isAbsolute(path)) return _escape(path);
    final relative = p.relative(
      p.join(projectDir, path),
      from: p.join(projectDir, 'android', 'app'),
    );
    return _escape(p.posix.joinAll(p.split(relative)));
  }

  /// The flavor's `signingConfig` value, in Kotlin or Groovy.
  String _signingValue(
    ProjectConfig config,
    Flavor flavor,
    Map<String, String> keys, {
    required bool kotlin,
  }) {
    final debug = kotlin
        ? 'signingConfigs.getByName("debug")'
        : 'signingConfigs.debug';
    final key = keys[config.signingFor(flavor)];
    return key == null ? debug : 'signingConfigs.findByName("$key") ?: $debug';
  }

  /// Kotlin code that loads each signing key, if its file exists.
  String _kotlinSigning(Map<String, String> keys) {
    final buffer = StringBuffer()
      ..writeln(
        '    // Signing keys from android_signing in flavorpilot.yaml. A',
      )
      ..writeln('    // missing key file falls back to the debug key.');
    keys.forEach((path, name) {
      final props = '${name}Properties';
      // Read as plain `key=value` lines: inside `android {}`, `java` means
      // Gradle's Java extension, so `java.util.Properties` doesn't compile.
      buffer
        ..writeln('    val $name = file("${_gradlePath(path)}")')
        ..writeln('    if ($name.exists()) {')
        ..writeln('        val $props = $name.readLines()')
        ..writeln(
          '            .filter { "=" in it && !it.trimStart().startsWith("#") }',
        )
        ..writeln(
          '            .associate { it.substringBefore("=").trim() to '
          'it.substringAfter("=").trim() }',
        )
        ..writeln('        signingConfigs.create("$name") {')
        ..writeln(
          '            storeFile = $name.parentFile.resolve('
          '$props.getValue("storeFile"))',
        )
        ..writeln(
          '            storePassword = $props.getValue("storePassword")',
        )
        ..writeln('            keyAlias = $props.getValue("keyAlias")')
        ..writeln('            keyPassword = $props.getValue("keyPassword")')
        ..writeln('        }')
        ..writeln('    }');
    });
    return buffer.toString();
  }

  /// Groovy code that loads each signing key, if its file exists.
  String _groovySigning(Map<String, String> keys) {
    final buffer = StringBuffer()
      ..writeln(
        '    // Signing keys from android_signing in flavorpilot.yaml. A',
      )
      ..writeln('    // missing key file falls back to the debug key.');
    keys.forEach((path, name) {
      final props = '${name}Properties';
      buffer
        ..writeln('    def $name = file("${_gradlePath(path)}")')
        ..writeln('    if ($name.exists()) {')
        // Same plain `key=value` reading as the Kotlin version.
        ..writeln(
          '        def $props = $name.readLines()'
          '.findAll { it.contains("=") && !it.trim().startsWith("#") }',
        )
        ..writeln(
          '            .collectEntries { [(it.split("=", 2)[0].trim()): '
          'it.split("=", 2)[1].trim()] }',
        )
        ..writeln('        signingConfigs.create("$name") {')
        ..writeln(
          '            storeFile $name.parentFile.toPath().resolve('
          '$props["storeFile"]).toFile()',
        )
        ..writeln('            storePassword $props["storePassword"]')
        ..writeln('            keyAlias $props["keyAlias"]')
        ..writeln('            keyPassword $props["keyPassword"]')
        ..writeln('        }')
        ..writeln('    }');
    });
    return buffer.toString();
  }

  /// Added at the end of `build.gradle.kts` when signing keys are used. It
  /// runs after the developer's `buildTypes`, so release builds use each
  /// flavor's key instead of the debug key Flutter's template sets.
  static const _kotlinReleaseBlock =
      '$_startMarker (generated, edit flavorpilot.yaml instead)\n'
      '// Release builds use each flavor\'s signing key (see productFlavors).\n'
      'android.buildTypes.getByName("release").signingConfig = null\n'
      '$_endMarker\n';

  /// The Groovy version of [_kotlinReleaseBlock].
  static const _groovyReleaseBlock =
      '$_startMarker (generated, edit flavorpilot.yaml instead)\n'
      '// Release builds use each flavor\'s signing key (see productFlavors).\n'
      'android.buildTypes.release.signingConfig = null\n'
      '$_endMarker\n';

  /// The flavors block for `build.gradle.kts` (Kotlin DSL).
  String _kotlinBlock(ProjectConfig config, Map<String, String> keys) {
    final buffer = StringBuffer()
      ..writeln('    $_startMarker (generated, edit flavorpilot.yaml instead)')
      // Needed for `resValue` on newer Android Gradle Plugin versions.
      ..writeln('    buildFeatures {')
      ..writeln('        resValues = true')
      ..writeln('    }');
    if (keys.isNotEmpty) buffer.write(_kotlinSigning(keys));
    buffer
      ..writeln('    flavorDimensions += "flavor"')
      ..writeln('    productFlavors {');
    for (final flavor in config.flavors) {
      buffer
        ..writeln('        create("${flavor.name}") {')
        ..writeln('            dimension = "flavor"');
      if (flavor.androidId != null) {
        buffer.writeln(
          '            applicationId = "${_escape(flavor.androidId!)}"',
        );
      }
      buffer.writeln(
        '            resValue("string", "app_name", '
        '"${_escape(_appName(flavor))}")',
      );
      if (keys.isNotEmpty) {
        buffer.writeln(
          '            signingConfig = '
          '${_signingValue(config, flavor, keys, kotlin: true)}',
        );
      }
      buffer.writeln('        }');
    }
    buffer
      ..writeln('    }')
      ..writeln('    $_endMarker');
    return buffer.toString();
  }

  /// The flavors block for `build.gradle` (Groovy DSL).
  String _groovyBlock(ProjectConfig config, Map<String, String> keys) {
    final buffer = StringBuffer()
      ..writeln('    $_startMarker (generated, edit flavorpilot.yaml instead)')
      ..writeln('    buildFeatures {')
      ..writeln('        resValues true')
      ..writeln('    }');
    if (keys.isNotEmpty) buffer.write(_groovySigning(keys));
    buffer
      ..writeln('    flavorDimensions "flavor"')
      ..writeln('    productFlavors {');
    for (final flavor in config.flavors) {
      buffer
        ..writeln('        ${flavor.name} {')
        ..writeln('            dimension "flavor"');
      if (flavor.androidId != null) {
        buffer.writeln(
          '            applicationId "${_escape(flavor.androidId!)}"',
        );
      }
      buffer.writeln(
        '            resValue "string", "app_name", '
        '"${_escape(_appName(flavor))}"',
      );
      if (keys.isNotEmpty) {
        buffer.writeln(
          '            signingConfig '
          '${_signingValue(config, flavor, keys, kotlin: false)}',
        );
      }
      buffer.writeln('        }');
    }
    buffer
      ..writeln('    }')
      ..writeln('    $_endMarker');
    return buffer.toString();
  }

  /// Points the manifest's app label to the per-flavor `app_name` string.
  void _updateManifest(FileChanges changes) {
    final file = File(
      p.join(
        projectDir,
        'android',
        'app',
        'src',
        'main',
        'AndroidManifest.xml',
      ),
    );
    if (!file.existsSync()) {
      logger.warn('AndroidManifest.xml not found, app names were not set.');
      return;
    }

    final content = file.readAsStringSync();
    final match = _manifestLabel.firstMatch(content);
    if (match == null) {
      logger.warn(
        'No android:label found in AndroidManifest.xml. Add '
        'android:label="@string/app_name" to <application> by hand.',
      );
      return;
    }
    if (match.group(2) == '@string/app_name') return; // Already done.

    changes
      ..write(
        file.path,
        content.replaceFirst(
          _manifestLabel,
          '${match.group(1)}@string/app_name${match.group(3)}',
        ),
      )
      ..note('Set the app label in AndroidManifest.xml');
  }

  /// The app name for [flavor], falling back to the flavor name so the
  /// `@string/app_name` resource always exists.
  String _appName(Flavor flavor) => flavor.appName ?? flavor.name;

  /// Escapes characters that are special inside Gradle strings
  /// (both Kotlin and Groovy treat `$` as string interpolation).
  String _escape(String value) => value
      .replaceAll(r'\', r'\\')
      .replaceAll('"', r'\"')
      .replaceAll(r'$', r'\$');
}
