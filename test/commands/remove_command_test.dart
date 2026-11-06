import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:flavorpilot/src/commands/remove_command.dart';
import 'package:flavorpilot/src/config/config_loader.dart';
import 'package:flavorpilot/src/utils/logger.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../helpers.dart';

void main() {
  const schemes = 'ios/Runner.xcodeproj/xcshareddata/xcschemes';

  /// A fixture project set up with development, staging and production.
  Future<String> setUpProject() async {
    final dir = createTempProject();
    await runFlavorPilot(dir, ['init', '--yes']);
    return dir;
  }

  bool exists(String dir, String path) =>
      File(p.join(dir, path)).existsSync() ||
      Directory(p.join(dir, path)).existsSync();

  test('removes the flavor everywhere and doctor passes', () async {
    final dir = await setUpProject();
    expect(exists(dir, '$schemes/staging.xcscheme'), isTrue);

    final code = await runFlavorPilot(dir, ['remove', 'stg', '--yes']);

    expect(code, 0);
    final config = const ConfigLoader().load(dir);
    expect(config.flavors.map((f) => f.name), ['development', 'production']);
    expect(
      readFile(dir, 'android/app/build.gradle.kts'),
      isNot(contains('staging')),
    );
    expect(
      readFile(dir, 'ios/Runner.xcodeproj/project.pbxproj'),
      isNot(contains('-staging')),
    );
    expect(readFile(dir, 'lib/flavors.dart'), isNot(contains('staging')));
    expect(readFile(dir, '.vscode/launch.json'), isNot(contains('staging')));
    expect(exists(dir, '$schemes/staging.xcscheme'), isFalse);
    expect(exists(dir, '.run/staging.run.xml'), isFalse);
    // Other flavors are untouched.
    expect(exists(dir, '$schemes/development.xcscheme'), isTrue);
    expect(exists(dir, '.run/development.run.xml'), isTrue);

    expect(await runFlavorPilot(dir, ['doctor']), 0);
  });

  test('deletes the icons flavorpilot created for the flavor', () async {
    final dir = await setUpProject();
    // The fixture has no asset catalog, which iOS icons need.
    writeFile(dir, 'ios/Runner/Assets.xcassets/Contents.json', '{}');
    writePng(dir, 'assets/stg.png');
    writeFile(
      dir,
      'flavorpilot.yaml',
      readFile(dir, 'flavorpilot.yaml').replaceFirst(
        'alias: "stg"',
        'alias: "stg"\n    icon: "assets/stg.png"',
      ),
    );
    await runFlavorPilot(dir, ['sync']);
    const iosIcons = 'ios/Runner/Assets.xcassets/AppIcon-staging.appiconset';
    const androidIcon =
        'android/app/src/staging/res/mipmap-mdpi/ic_launcher.png';
    expect(exists(dir, iosIcons), isTrue);
    expect(exists(dir, androidIcon), isTrue);

    await runFlavorPilot(dir, ['remove', 'staging', '--yes']);

    expect(exists(dir, iosIcons), isFalse);
    expect(exists(dir, androidIcon), isFalse);
  });

  test('keeps main files and .env files that hold values', () async {
    final dir = createTempProject();
    writeFile(dir, 'flavorpilot.yaml', '''
main_mode: multiple
flavors:
  development: {alias: dev}
  qa: {alias: q}
''');
    await runFlavorPilot(dir, ['dotenv']);
    writeFile(dir, '.env.qa', 'API_KEY=secret\n');

    await runFlavorPilot(dir, ['remove', 'qa', '--yes']);

    expect(exists(dir, 'lib/main_qa.dart'), isTrue);
    expect(readFile(dir, '.env.qa'), 'API_KEY=secret\n');
    expect(readFile(dir, '.gitignore'), isNot(contains('.env.qa')));
  });

  test('deletes an .env file that has no values', () async {
    final dir = createTempProject();
    writeFile(
      dir,
      'flavorpilot.yaml',
      'flavors:\n  development: {}\n  qa: {}\n',
    );
    await runFlavorPilot(dir, ['dotenv']);
    expect(exists(dir, '.env.qa'), isTrue);

    await runFlavorPilot(dir, ['remove', 'qa', '--yes']);

    expect(exists(dir, '.env.qa'), isFalse);
    expect(exists(dir, '.env.development'), isTrue);
  });

  group('confirmation', () {
    Future<void> removeWithAnswer(String dir, String answer) {
      return (CommandRunner<int>('flavorpilot', 'test')..addCommand(
            RemoveCommand(
              logger: Logger(useColors: false),
              processRunner: FakeProcessRunner(),
              projectDir: dir,
              readLine: () => answer,
            ),
          ))
          .run(['remove', 'staging']);
    }

    test('nothing changes when the answer is no or empty', () async {
      final dir = await setUpProject();
      final before = readFile(dir, 'flavorpilot.yaml');

      await removeWithAnswer(dir, '');
      await removeWithAnswer(dir, 'n');

      expect(readFile(dir, 'flavorpilot.yaml'), before);
      expect(exists(dir, '$schemes/staging.xcscheme'), isTrue);
    });

    test('removes the flavor when the answer is yes', () async {
      final dir = await setUpProject();

      await removeWithAnswer(dir, 'y');

      expect(const ConfigLoader().load(dir).findFlavor('staging'), isNull);
    });
  });

  group('errors', () {
    test('an unknown flavor changes nothing', () async {
      final dir = await setUpProject();
      final before = readFile(dir, 'flavorpilot.yaml');

      expect(await runFlavorPilot(dir, ['remove', 'nope', '--yes']), 1);
      expect(readFile(dir, 'flavorpilot.yaml'), before);
    });

    test('the last flavor can\'t be removed', () async {
      final dir = createTempProject();
      writeFile(dir, 'flavorpilot.yaml', 'flavors:\n  production: {}\n');

      expect(await runFlavorPilot(dir, ['remove', 'production', '--yes']), 1);
      expect(const ConfigLoader().load(dir).flavors, hasLength(1));
    });

    test('no flavor name is a usage error', () async {
      final dir = await setUpProject();
      expect(await runFlavorPilot(dir, ['remove']), 64);
    });
  });
}
