import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:flavorpilot/flavorpilot.dart';
import 'package:flavorpilot/src/commands/init_command.dart';
import 'package:flavorpilot/src/utils/logger.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../helpers.dart';

/// Tests for the commands that change project files:
/// init, add, sync and doctor.
void main() {
  group('init', () {
    test('sets up every platform with default answers', () async {
      final dir = createTempProject();

      expect(await runFlavorPilot(dir, ['init', '--yes']), 0);

      final config = const ConfigLoader().load(dir);
      expect(config.flavors.map((f) => f.name), [
        'development',
        'staging',
        'production',
      ]);
      expect(config.findFlavor('dev')?.androidId, 'com.example.sample.dev');
      expect(config.findFlavor('prod')?.appName, 'Sample');
      expect(
        readFile(dir, 'android/app/build.gradle.kts'),
        contains('create("staging")'),
      );
      expect(
        readFile(dir, 'ios/Runner.xcodeproj/project.pbxproj'),
        contains('Release-staging'),
      );
      expect(readFile(dir, 'lib/flavors.dart'), contains('enum AppFlavor'));
      expect(readFile(dir, '.vscode/launch.json'), contains('staging'));
    });

    test('creates one main file per flavor when asked', () async {
      final dir = createTempProject();
      // Answers in order: app name, base id, flavors, then alias / name / id
      // for each flavor (empty = default), then "one main.dart?" → no.
      final answers = [
        'Shop',
        'com.acme.shop',
        'development,production',
        '', '', '', //
        '', '', '', //
        'n',
      ];
      final runner = CommandRunner<int>('flavorpilot', 'test')
        ..addCommand(
          InitCommand(
            logger: Logger(useColors: false),
            processRunner: FakeProcessRunner(),
            projectDir: dir,
            readLine: () => answers.removeAt(0),
          ),
        );

      await runner.run(['init']);

      final config = const ConfigLoader().load(dir);
      expect(config.mainMode, MainMode.multiple);
      expect(config.findFlavor('dev')?.androidId, 'com.acme.shop.dev');
      expect(config.findFlavor('prod')?.appName, 'Shop');
      expect(
        readFile(dir, 'lib/main_development.dart'),
        contains('app.main()'),
      );
      expect(readFile(dir, 'lib/main_production.dart'), contains('app.main()'));
    });

    test('refuses to run twice without --force', () async {
      final dir = createTempProject();
      await runFlavorPilot(dir, ['init', '--yes']);

      expect(await runFlavorPilot(dir, ['init', '--yes']), 1);
      expect(await runFlavorPilot(dir, ['init', '--yes', '--force']), 0);
    });

    test('needs a Flutter project', () async {
      expect(await runFlavorPilot(createEmptyDir(), ['init', '--yes']), 1);
    });

    test('changes no file when one platform cannot be set up', () async {
      final dir = createTempProject();
      // Hand-made Android flavors make the Android step fail.
      final gradle = readFile(dir, 'android/app/build.gradle.kts').replaceFirst(
        'android {\n',
        'android {\n    productFlavors { create("dev") {} }\n',
      );
      writeFile(dir, 'android/app/build.gradle.kts', gradle);
      final before = snapshot(dir);

      expect(await runFlavorPilot(dir, ['init', '--yes']), 1);
      expect(snapshot(dir), before);
    });
  });

  group('add', () {
    test('adds a flavor with the given options', () async {
      final dir = createTempProject();
      await runFlavorPilot(dir, ['init', '--yes']);

      final code = await runFlavorPilot(dir, [
        'add',
        'uat',
        '--alias',
        'u',
        '--app-name',
        'Sample UAT',
        '--app-id',
        'com.example.sample.uat',
      ]);

      expect(code, 0);
      final uat = const ConfigLoader().load(dir).findFlavor('u')!;
      expect(uat.name, 'uat');
      expect(uat.appName, 'Sample UAT');
      expect(
        readFile(dir, 'android/app/build.gradle.kts'),
        contains('applicationId = "com.example.sample.uat"'),
      );
      expect(
        File(
          p.join(
            dir,
            'ios/Runner.xcodeproj/xcshareddata/xcschemes/uat.xcscheme',
          ),
        ).existsSync(),
        isTrue,
      );
    });

    test('bases default ids on the production flavor', () async {
      final dir = createTempProject();
      await runFlavorPilot(dir, ['init', '--yes']);
      await runFlavorPilot(dir, ['add', 'qualityAssurance', '--yes']);

      final qa = const ConfigLoader().load(dir).findFlavor('qa')!;
      expect(qa.androidId, 'com.example.sample.qa');
      expect(qa.appName, 'Sample QA');
    });

    test('rejects a name or alias already in use', () async {
      final dir = createTempProject();
      await runFlavorPilot(dir, ['init', '--yes']);
      final before = snapshot(dir);

      expect(await runFlavorPilot(dir, ['add', 'staging', '--yes']), 1);
      expect(await runFlavorPilot(dir, ['add', 'dev', '--yes']), 1);
      expect(snapshot(dir), before);
    });
  });

  group('doctor and sync', () {
    test('doctor passes right after init', () async {
      final dir = createTempProject();
      await runFlavorPilot(dir, ['init', '--yes']);

      expect(await runFlavorPilot(dir, ['doctor']), 0);
    });

    test('doctor catches a hand-edited config until sync runs', () async {
      final dir = createTempProject();
      await runFlavorPilot(dir, ['init', '--yes']);
      writeFile(
        dir,
        'flavorpilot.yaml',
        readFile(dir, 'flavorpilot.yaml').replaceFirst('Sample STG', 'Stage'),
      );

      expect(await runFlavorPilot(dir, ['doctor']), 1);
      expect(await runFlavorPilot(dir, ['sync']), 0);
      expect(await runFlavorPilot(dir, ['doctor']), 0);
      expect(
        readFile(dir, 'android/app/build.gradle.kts'),
        contains('"app_name", "Stage"'),
      );
    });

    test('doctor catches a deleted generated file', () async {
      final dir = createTempProject();
      await runFlavorPilot(dir, ['init', '--yes']);
      File(p.join(dir, 'lib/flavors.dart')).deleteSync();

      expect(await runFlavorPilot(dir, ['doctor']), 1);
    });
  });
}
