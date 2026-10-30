import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:flavorpilot/flavorpilot.dart';
import 'package:flavorpilot/src/commands/add_command.dart';
import 'package:flavorpilot/src/commands/init_command.dart';
import 'package:flavorpilot/src/utils/logger.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../helpers.dart';

/// Reads a binary file as bytes, for comparing generated icons.
List<int> readBytes(String dir, String path) =>
    File(p.join(dir, path)).readAsBytesSync();

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
      // for each flavor (empty = default), then "separate main file?" → yes.
      final answers = [
        'Shop',
        'com.acme.shop',
        'development,production',
        '', '', '', //
        '', '', '', //
        'y',
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

    test(
      'uses one main.dart when the main file question is left empty',
      () async {
        final dir = createTempProject();
        final answers = ['', '', 'production', '', '', '', ''];
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

        expect(const ConfigLoader().load(dir).mainMode, MainMode.single);
        expect(
          File(p.join(dir, 'lib/main_production.dart')).existsSync(),
          isFalse,
        );
      },
    );

    test('--force warns before replacing env values and icons', () async {
      final dir = createTempProject();
      writeFile(dir, 'flavorpilot.yaml', '''
flavors:
  production:
    env:
      base_url: "https://example.com"
''');
      final logger = RecordingLogger();

      final code = await FlavorPilotRunner(
        logger: logger,
        processRunner: FakeProcessRunner(),
        projectDir: dir,
      ).run(['init', '--yes', '--force']);

      expect(code, 0);
      expect(logger.warnings, anyElement(contains('will be lost')));
    });

    test('--force does not warn when there is nothing to lose', () async {
      final dir = createTempProject();
      writeFile(dir, 'flavorpilot.yaml', 'flavors:\n  production: {}\n');
      final logger = RecordingLogger();

      await FlavorPilotRunner(
        logger: logger,
        processRunner: FakeProcessRunner(),
        projectDir: dir,
      ).run(['init', '--yes', '--force']);

      expect(logger.warnings, isNot(anyElement(contains('will be lost'))));
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
        '--yes',
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

  group('add with env', () {
    /// A project whose flavors use env.
    Future<String> createEnvProject() async {
      final dir = createTempProject();
      await runFlavorPilot(dir, ['init', '--yes']);
      writeFile(dir, 'flavorpilot.yaml', '''
flavors:
  development:
    alias: dev
    env:
      base_url: "https://dev.example.com"
      enable_logs: true
      retries: 5
  production:
    alias: prod
    app_name: "Sample"
    android_id: "com.example.sample"
    env:
      base_url: "https://example.com"
      enable_logs: false
      retries: 3
''');
      return dir;
    }

    /// Runs `add qa` with typed [answers]: alias, app name, app id, then env.
    Future<void> runAdd(String dir, List<String> answers) {
      final runner = CommandRunner<int>('flavorpilot', 'test')
        ..addCommand(
          AddCommand(
            logger: Logger(useColors: false),
            processRunner: FakeProcessRunner(),
            projectDir: dir,
            readLine: () => answers.removeAt(0),
          ),
        );
      return runner.run(['add', 'qa']);
    }

    test('asks for each env value and keeps its type', () async {
      final dir = await createEnvProject();

      await runAdd(dir, ['', '', '', 'https://qa.example.com', 'true', '4']);

      final config = const ConfigLoader().load(dir);
      expect(config.findFlavor('qa')!.env, {
        'base_url': 'https://qa.example.com',
        'enable_logs': true,
        'retries': 4,
      });
      // The other flavors keep their values.
      expect(config.findFlavor('dev')!.env['retries'], 5);
      expect(readFile(dir, 'lib/flavors.dart'), contains('qa.example.com'));
    });

    test('empty answers use the production values', () async {
      final dir = await createEnvProject();

      await runAdd(dir, ['', '', '', '', '', '']);

      expect(const ConfigLoader().load(dir).findFlavor('qa')!.env, {
        'base_url': 'https://example.com',
        'enable_logs': false,
        'retries': 3,
      });
    });

    test('rejects an answer of the wrong type and changes nothing', () async {
      final dir = await createEnvProject();
      final before = snapshot(dir);

      await expectLater(
        runAdd(dir, ['', '', '', '', 'maybe', '']),
        throwsA(isA<FlavorPilotException>()),
      );
      await expectLater(
        runAdd(dir, ['', '', '', '', '', 'many']),
        throwsA(isA<FlavorPilotException>()),
      );
      expect(snapshot(dir), before);
    });

    test('--yes copies production values and warns about them', () async {
      final dir = await createEnvProject();
      final logger = RecordingLogger();

      final code = await FlavorPilotRunner(
        logger: logger,
        processRunner: FakeProcessRunner(),
        projectDir: dir,
      ).run(['add', 'qa', '--yes']);

      expect(code, 0);
      expect(
        const ConfigLoader().load(dir).findFlavor('qa')!.env['base_url'],
        'https://example.com',
      );
      expect(logger.warnings.single, contains('copied its env values'));
    });

    test('--yes does not warn when flavors have no env', () async {
      final dir = createTempProject();
      writeFile(dir, 'flavorpilot.yaml', 'flavors:\n  production: {}\n');
      final logger = RecordingLogger();

      await FlavorPilotRunner(
        logger: logger,
        processRunner: FakeProcessRunner(),
        projectDir: dir,
      ).run(['add', 'qa', '--yes']);

      expect(logger.warnings, isEmpty);
    });
  });

  group('env and icons through sync', () {
    /// A project after `init` with an asset catalog and a source icon.
    Future<String> createProject() async {
      final dir = createTempProject();
      writeFile(dir, 'ios/Runner/Assets.xcassets/Contents.json', '{}');
      writePng(dir, 'assets/dev.png');
      await runFlavorPilot(dir, ['init', '--yes']);
      return dir;
    }

    /// Adds [line] under the development flavor in flavorpilot.yaml.
    void addToDevelopment(String dir, String line) {
      writeFile(
        dir,
        'flavorpilot.yaml',
        readFile(
          dir,
          'flavorpilot.yaml',
        ).replaceFirst('  development:\n', '  development:\n    $line\n'),
      );
    }

    test('env reaches the generated enum', () async {
      final dir = await createProject();
      writeFile(dir, 'flavorpilot.yaml', '''
flavors:
  development:
    env:
      base_url: "https://dev.example.com"
  production:
    env:
      base_url: "https://example.com"
''');

      expect(await runFlavorPilot(dir, ['doctor']), 1);
      expect(await runFlavorPilot(dir, ['sync']), 0);
      expect(await runFlavorPilot(dir, ['doctor']), 0);

      final code = readFile(dir, 'lib/flavors.dart');
      expect(code, contains('final String baseUrl;'));
      expect(code, contains("baseUrl: 'https://dev.example.com'"));
    });

    test('an env mistake changes no file', () async {
      final dir = await createProject();
      // Remove a key from one flavor only, which the other flavors still have.
      writeFile(
        dir,
        'flavorpilot.yaml',
        readFile(
          dir,
          'flavorpilot.yaml',
        ).replaceFirst(RegExp(r'      base_url: .*\n'), ''),
      );
      final before = snapshot(dir);

      expect(await runFlavorPilot(dir, ['sync']), 1);
      expect(snapshot(dir), before);
    });

    test('an icon reaches both platforms and doctor checks it', () async {
      final dir = await createProject();
      addToDevelopment(dir, 'icon: "assets/dev.png"');

      expect(await runFlavorPilot(dir, ['doctor']), 1);
      expect(await runFlavorPilot(dir, ['sync']), 0);
      expect(await runFlavorPilot(dir, ['doctor']), 0);

      expect(
        readFile(dir, 'ios/Runner.xcodeproj/project.pbxproj'),
        contains('ASSETCATALOG_COMPILER_APPICON_NAME = "AppIcon-development";'),
      );

      // A changed icon on disk is noticed and restored by sync.
      const generated =
          'android/app/src/development/res/mipmap-mdpi/ic_launcher.png';
      final original = readBytes(dir, generated);
      writePng(dir, generated, width: 48, height: 48, alpha: 10);
      expect(await runFlavorPilot(dir, ['doctor']), 1);
      expect(await runFlavorPilot(dir, ['sync']), 0);
      expect(readBytes(dir, generated), original);
    });

    test('doctor notices icons that should be gone', () async {
      final dir = await createProject();
      final withoutIcon = readFile(dir, 'flavorpilot.yaml');
      addToDevelopment(dir, 'icon: "assets/dev.png"');
      await runFlavorPilot(dir, ['sync']);

      writeFile(dir, 'flavorpilot.yaml', withoutIcon);

      expect(await runFlavorPilot(dir, ['doctor']), 1);
      expect(await runFlavorPilot(dir, ['sync']), 0);
      expect(await runFlavorPilot(dir, ['doctor']), 0);
      expect(
        Directory(p.join(dir, 'android/app/src/development')).existsSync() &&
            File(
              p.join(dir, 'android/app/src/development/.flavorpilot-icon'),
            ).existsSync(),
        isFalse,
      );
    });

    test('a bad icon changes no file', () async {
      final dir = await createProject();
      addToDevelopment(dir, 'icon: "assets/missing.png"');
      final before = snapshot(dir);

      expect(await runFlavorPilot(dir, ['sync']), 1);
      expect(snapshot(dir), before);
    });

    test('add keeps env and icons of the other flavors', () async {
      final dir = await createProject();
      addToDevelopment(dir, 'icon: "assets/dev.png"');
      await runFlavorPilot(dir, ['sync']);

      await runFlavorPilot(dir, ['add', 'qa', '--yes']);

      final config = const ConfigLoader().load(dir);
      expect(config.findFlavor('dev')!.icon, 'assets/dev.png');
      expect(await runFlavorPilot(dir, ['doctor']), 0);
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
