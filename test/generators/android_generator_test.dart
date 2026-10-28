import 'dart:io';

import 'package:flavorpilot/flavorpilot.dart';
import 'package:flavorpilot/src/generators/android_generator.dart';
import 'package:flavorpilot/src/utils/file_changes.dart';
import 'package:flavorpilot/src/utils/logger.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../helpers.dart';

void main() {
  const gradlePath = 'android/app/build.gradle.kts';
  const manifestPath = 'android/app/src/main/AndroidManifest.xml';

  const config = ProjectConfig(
    flavors: [
      Flavor(
        name: 'development',
        appName: r'Sample "DEV" $1',
        androidId: 'com.example.sample.dev',
      ),
      Flavor(name: 'production'),
    ],
  );

  /// Runs the generator on [projectDir] and writes the result.
  void generate(String projectDir) {
    final changes = FileChanges();
    AndroidGenerator(
      projectDir: projectDir,
      logger: Logger(useColors: false),
    ).generate(config, changes);
    changes.apply();
  }

  test('adds flavors to build.gradle.kts with escaped values', () {
    final dir = createTempProject();
    generate(dir);
    final gradle = readFile(dir, gradlePath);

    expect(gradle, contains('flavorDimensions += "flavor"'));
    expect(gradle, contains('create("development") {'));
    expect(gradle, contains('applicationId = "com.example.sample.dev"'));
    // `"` and `$` must be escaped, or Gradle would fail or interpolate.
    expect(
      gradle,
      contains(r'resValue("string", "app_name", "Sample \"DEV\" \$1")'),
    );
    // A flavor without an app name falls back to its flavor name.
    expect(gradle, contains('resValue("string", "app_name", "production")'));
  });

  test('points the manifest label to the per-flavor app name', () {
    final dir = createTempProject();
    generate(dir);

    expect(
      readFile(dir, manifestPath),
      contains('android:label="@string/app_name"'),
    );
  });

  test('running again leaves the files unchanged', () {
    final dir = createTempProject();
    generate(dir);
    final first = snapshot(dir);

    generate(dir);
    expect(snapshot(dir), first);
  });

  test('removeGeneratedBlock restores the original Gradle file', () {
    final dir = createTempProject();
    final original = readFile(dir, gradlePath);
    generate(dir);

    expect(
      AndroidGenerator.removeGeneratedBlock(readFile(dir, gradlePath)),
      original,
    );
  });

  test('uses Groovy syntax for build.gradle', () {
    final dir = createTempProject();
    // Older projects have build.gradle instead of build.gradle.kts.
    File(p.join(dir, gradlePath)).deleteSync();
    writeFile(dir, 'android/app/build.gradle', '''
android {
    namespace "com.example.sample"
}
''');

    generate(dir);
    final gradle = readFile(dir, 'android/app/build.gradle');

    expect(gradle, contains('flavorDimensions "flavor"'));
    expect(gradle, contains('        development {'));
    expect(gradle, contains('applicationId "com.example.sample.dev"'));
  });

  test('refuses to overwrite hand-made productFlavors', () {
    final dir = createTempProject();
    final gradle = readFile(dir, gradlePath).replaceFirst(
      'android {\n',
      'android {\n    productFlavors { create("dev") {} }\n',
    );
    writeFile(dir, gradlePath, gradle);

    expect(() => generate(dir), throwsA(isA<FlavorPilotException>()));
    expect(readFile(dir, gradlePath), gradle);
  });
}
