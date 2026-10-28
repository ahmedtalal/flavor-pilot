import 'package:flavorpilot/flavorpilot.dart';
import 'package:flavorpilot/src/generators/ios_generator.dart';
import 'package:flavorpilot/src/utils/file_changes.dart';
import 'package:flavorpilot/src/utils/logger.dart';
import 'package:test/test.dart';

import '../helpers.dart';

void main() {
  const schemesDir = 'ios/Runner.xcodeproj/xcshareddata/xcschemes';

  const config = ProjectConfig(
    flavors: [
      Flavor(
        name: 'development',
        appName: 'Sample DEV',
        iosBundleId: 'com.example.sample.dev',
      ),
    ],
  );

  /// Flutter's standard Podfile header.
  const podfile = '''
platform :ios, '13.0'

project 'Runner', {
  'Debug' => :debug,
  'Profile' => :release,
  'Release' => :release,
}
''';

  /// Runs the generator on [projectDir] and writes the result.
  void generate(String projectDir) {
    final changes = FileChanges();
    IosGenerator(
      projectDir: projectDir,
      logger: Logger(useColors: false),
    ).generate(config, changes);
    changes.apply();
  }

  test('creates a scheme per flavor using its configurations', () {
    final dir = createTempProject();
    generate(dir);
    final scheme = readFile(dir, '$schemesDir/development.xcscheme');

    expect(scheme, contains('buildConfiguration = "Debug-development"'));
    expect(scheme, contains('buildConfiguration = "Profile-development"'));
    expect(scheme, contains('buildConfiguration = "Release-development"'));
    expect(scheme, isNot(contains('buildConfiguration = "Debug"')));
  });

  test('keeps a scheme the developer already has', () {
    final dir = createTempProject();
    writeFile(dir, '$schemesDir/development.xcscheme', 'custom');
    generate(dir);

    expect(readFile(dir, '$schemesDir/development.xcscheme'), 'custom');
  });

  test('makes Info.plist read the per-flavor app name', () {
    final dir = createTempProject();
    generate(dir);

    expect(
      readFile(dir, 'ios/Runner/Info.plist'),
      contains('<string>${IosGenerator.appNameVariable}</string>'),
    );
  });

  test('writes xcconfigs that include the lowercase CocoaPods file', () {
    final dir = createTempProject();
    generate(dir);
    final xcconfig = readFile(
      dir,
      'ios/Flutter/flavorpilot/Release-development.xcconfig',
    );

    expect(
      xcconfig,
      contains('Pods-Runner/Pods-Runner.release-development.xcconfig"'),
    );
    expect(xcconfig, contains('#include "../Generated.xcconfig"'));
  });

  test('maps configurations in the Podfile exactly once', () {
    final dir = createTempProject();
    writeFile(dir, 'ios/Podfile', podfile);
    generate(dir);
    generate(dir);
    final result = readFile(dir, 'ios/Podfile');

    expect("'Debug-development' => :debug,".allMatches(result).length, 1);
    expect(result, contains("'Release-development' => :release,"));
    // The original entries are kept.
    expect(result, contains("'Debug' => :debug,"));
  });

  test('running again leaves every file unchanged except new ids', () {
    final dir = createTempProject();
    generate(dir);
    final first = snapshot(dir);
    generate(dir);
    final second = snapshot(dir);

    String mask(String s) => s.replaceAll(RegExp(r'\b[0-9A-F]{24}\b'), 'ID');
    expect(second.keys, first.keys);
    for (final path in first.keys) {
      expect(mask(second[path]!), mask(first[path]!), reason: path);
    }
  });
}
