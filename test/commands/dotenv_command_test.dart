import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:flavorpilot/src/commands/init_command.dart';
import 'package:flavorpilot/src/config/config_loader.dart';
import 'package:flavorpilot/src/utils/logger.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../helpers.dart';

/// Tests for per-flavor `.env` files: the `dotenv` command, the `init`
/// question, and how `run`, `build`, `add` and the IDE files use them.
void main() {
  const twoFlavors = '''
flavors:
  development: {alias: dev}
  production: {alias: prod}
''';

  /// A project with the fixture files and [yaml] as flavorpilot.yaml.
  String projectWith(String yaml) {
    final dir = createTempProject();
    writeFile(dir, 'flavorpilot.yaml', yaml);
    return dir;
  }

  bool exists(String dir, String path) => File(p.join(dir, path)).existsSync();

  group('dotenv', () {
    test('creates a .env file per flavor and keeps them out of git', () async {
      final dir = projectWith(twoFlavors);
      writeFile(dir, '.gitignore', 'build/\n');

      final code = await runFlavorPilot(dir, ['dotenv']);

      expect(code, 0);
      final config = const ConfigLoader().load(dir);
      expect(config.findFlavor('dev')!.envFile, '.env.development');
      expect(config.findFlavor('prod')!.envFile, '.env.production');
      expect(exists(dir, '.env.development'), isTrue);
      expect(exists(dir, '.env.production'), isTrue);
      expect(
        readFile(dir, '.gitignore'),
        allOf(
          startsWith('build/\n\n# flavorpilot:start\n'),
          contains('.env.development\n.env.production\n'),
          endsWith('# flavorpilot:end\n'),
        ),
      );
    });

    test('never changes an existing .env file', () async {
      final dir = projectWith(twoFlavors);
      writeFile(dir, '.env.development', 'API_KEY=secret\n');

      await runFlavorPilot(dir, ['dotenv']);

      expect(readFile(dir, '.env.development'), 'API_KEY=secret\n');
    });

    test('running it again changes nothing and doctor passes', () async {
      final dir = projectWith(twoFlavors);
      writeFile(dir, '.gitignore', 'build/\n');
      await runFlavorPilot(dir, ['dotenv']);
      final gitignore = readFile(dir, '.gitignore');
      final yaml = readFile(dir, 'flavorpilot.yaml');

      expect(await runFlavorPilot(dir, ['dotenv']), 0);
      expect(await runFlavorPilot(dir, ['sync']), 0);

      expect(readFile(dir, '.gitignore'), gitignore);
      expect(readFile(dir, 'flavorpilot.yaml'), yaml);
      expect(await runFlavorPilot(dir, ['doctor']), 0);
    });

    test('doctor reports a deleted .env file and sync recreates it', () async {
      final dir = projectWith(twoFlavors);
      await runFlavorPilot(dir, ['dotenv']);
      File(p.join(dir, '.env.production')).deleteSync();

      expect(await runFlavorPilot(dir, ['doctor']), 1);
      await runFlavorPilot(dir, ['sync']);
      expect(exists(dir, '.env.production'), isTrue);
    });

    test('removing every env_file removes the .gitignore block', () async {
      final dir = projectWith(twoFlavors);
      writeFile(dir, '.gitignore', 'build/\n');
      await runFlavorPilot(dir, ['dotenv']);

      writeFile(dir, 'flavorpilot.yaml', twoFlavors);
      await runFlavorPilot(dir, ['sync']);

      expect(readFile(dir, '.gitignore'), 'build/\n');
    });
  });

  group('run and build', () {
    const withEnvFile = '''
flavors:
  development:
    alias: dev
    env_file: .env.development
''';

    test('pass the flavor\'s .env file to flutter', () async {
      final dir = projectWith(withEnvFile);
      writeFile(dir, '.env.development', 'API_KEY=x\n');
      final fake = FakeProcessRunner();

      await runFlavorPilot(dir, ['run', 'dev'], processRunner: fake);
      await runFlavorPilot(dir, ['build', 'dev'], processRunner: fake);

      for (final call in fake.calls) {
        expect(call, contains('--dart-define-from-file=.env.development'));
      }
    });

    test('stop with a clear message when the .env file is missing', () async {
      final dir = projectWith(withEnvFile);
      final fake = FakeProcessRunner();

      final code = await runFlavorPilot(dir, [
        'run',
        'dev',
      ], processRunner: fake);

      expect(code, 1);
      expect(fake.calls, isEmpty);
    });
  });

  test('IDE run configurations load the .env file', () async {
    final dir = projectWith(twoFlavors);

    await runFlavorPilot(dir, ['dotenv']);

    expect(
      readFile(dir, '.vscode/launch.json'),
      contains('"--dart-define-from-file=.env.development"'),
    );
    expect(
      readFile(dir, '.run/production.run.xml'),
      contains(
        '<option name="additionalArgs" '
        'value="--dart-define-from-file=.env.production" />',
      ),
    );
  });

  test('add gives the new flavor a .env file when others have one', () async {
    final dir = projectWith(twoFlavors);
    await runFlavorPilot(dir, ['dotenv']);

    await runFlavorPilot(dir, ['add', 'staging', '--yes']);

    expect(
      const ConfigLoader().load(dir).findFlavor('staging')!.envFile,
      '.env.staging',
    );
    expect(exists(dir, '.env.staging'), isTrue);
  });

  test('init creates .env files when the answer is yes', () async {
    final dir = createTempProject();
    // App name, base id, flavors, alias / name / id, separate mains, .env.
    final answers = ['', '', 'production', '', '', '', '', 'y'];
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

    expect(
      const ConfigLoader().load(dir).flavors.single.envFile,
      '.env.production',
    );
    expect(exists(dir, '.env.production'), isTrue);
  });

  test('init --yes creates no .env files', () async {
    final dir = createTempProject();

    await runFlavorPilot(dir, ['init', '--yes']);

    expect(
      const ConfigLoader().load(dir).flavors.every((f) => f.envFile == null),
      isTrue,
    );
    expect(exists(dir, '.env.development'), isFalse);
  });

  test('env_file outside the project is rejected', () {
    for (final path in ['../.env', '/etc/.env', '']) {
      expect(
        () => const ConfigLoader().parse(
          'flavors:\n  production: {env_file: "$path"}\n',
        ),
        throwsA(anything),
        reason: path,
      );
    }
  });
}
