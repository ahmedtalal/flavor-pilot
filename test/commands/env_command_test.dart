import 'package:flavorpilot/flavorpilot.dart';
import 'package:flavorpilot/src/utils/env_defaults.dart';
import 'package:test/test.dart';

import '../helpers.dart';

/// Tests for the example env settings added by `init` and `env`, and the
/// warnings about them.
void main() {
  const placeholderWarning = 'still examples';

  /// Runs flavorpilot in [dir] and returns the warnings it printed.
  Future<List<String>> warningsOf(String dir, List<String> args) async {
    final logger = RecordingLogger();
    await FlavorPilotRunner(
      logger: logger,
      processRunner: FakeProcessRunner(),
      projectDir: dir,
    ).run(args);
    return logger.warnings;
  }

  group('defaultEnv', () {
    test('production gets the plain URL and no logs', () {
      expect(defaultEnv(const Flavor(name: 'production', alias: 'prod')), {
        'base_url': 'https://api.example.com',
        'enable_logs': false,
      });
    });

    test('other flavors use their alias and turn logs on', () {
      expect(defaultEnv(const Flavor(name: 'development', alias: 'dev')), {
        'base_url': 'https://dev.api.example.com',
        'enable_logs': true,
      });
    });

    test('falls back to the lowercase flavor name', () {
      expect(
        defaultEnv(const Flavor(name: 'myFlavor'))['base_url'],
        'https://myflavor.api.example.com',
      );
    });
  });

  group('init', () {
    test('adds the example settings and warns about them', () async {
      final dir = createTempProject();

      final warnings = await warningsOf(dir, ['init', '--yes']);

      final config = const ConfigLoader().load(dir);
      expect(config.findFlavor('dev')!.env, {
        'base_url': 'https://dev.api.example.com',
        'enable_logs': true,
      });
      expect(config.findFlavor('prod')!.env['enable_logs'], false);
      final code = readFile(dir, 'lib/flavors.dart');
      expect(code, contains('final String baseUrl;'));
      expect(code, contains('final bool enableLogs;'));
      expect(warnings, anyElement(contains(placeholderWarning)));
    });
  });

  group('env command', () {
    /// A set-up project whose flavors have no env, like one from 0.2.0.
    Future<String> createOldProject() async {
      final dir = createTempProject();
      writeFile(dir, 'flavorpilot.yaml', '''
flavors:
  development:
    alias: dev
  production:
    alias: prod
''');
      await runFlavorPilot(dir, ['sync']);
      return dir;
    }

    test('adds the settings and updates the project', () async {
      final dir = await createOldProject();

      final warnings = await warningsOf(dir, ['env']);

      final config = const ConfigLoader().load(dir);
      expect(
        config.findFlavor('dev')!.env['base_url'],
        'https://dev.api.example.com',
      );
      expect(readFile(dir, 'lib/flavors.dart'), contains('this.baseUrl'));
      expect(await runFlavorPilot(dir, ['doctor']), 0);
      expect(warnings, anyElement(contains(placeholderWarning)));
    });

    test('never changes existing values', () async {
      final dir = createTempProject();
      writeFile(dir, 'flavorpilot.yaml', '''
flavors:
  development:
    env:
      base_url: "https://dev.mycompany.com"
      timeout: 30
  production:
    env:
      base_url: "https://mycompany.com"
      timeout: 10
''');

      expect(await runFlavorPilot(dir, ['env']), 0);

      expect(const ConfigLoader().load(dir).flavors.first.env, {
        'base_url': 'https://dev.mycompany.com',
        'timeout': 30,
        'enable_logs': true,
      });
    });

    test('running again changes nothing and keeps comments', () async {
      final dir = await createOldProject();
      await runFlavorPilot(dir, ['env']);
      writeFile(
        dir,
        'flavorpilot.yaml',
        '# my comment\n${readFile(dir, 'flavorpilot.yaml')}',
      );
      final before = snapshot(dir);

      expect(await runFlavorPilot(dir, ['env']), 0);
      expect(snapshot(dir), before);
    });

    test('changes no file when the project can not be updated', () async {
      final dir = await createOldProject();
      // Replace our Android block with hand-made flavors.
      const gradle = 'android/app/build.gradle.kts';
      writeFile(
        dir,
        gradle,
        readFile(dir, gradle).replaceAll('flavorpilot:', 'someone:'),
      );
      final before = snapshot(dir);

      expect(await runFlavorPilot(dir, ['env']), 1);
      expect(snapshot(dir), before);
    });

    test('needs flavorpilot.yaml', () async {
      expect(await runFlavorPilot(createEmptyDir(), ['env']), 1);
    });
  });

  group('placeholder warnings', () {
    const realValues = '''
flavors:
  development:
    alias: dev
    env:
      base_url: "https://dev.mycompany.com"
  production:
    alias: prod
    env:
      base_url: "https://mycompany.com"
''';

    test('doctor warns but does not fail', () async {
      final dir = createTempProject();
      await runFlavorPilot(dir, ['init', '--yes']);

      expect(await runFlavorPilot(dir, ['doctor']), 0);
      expect(
        await warningsOf(dir, ['doctor']),
        anyElement(contains(placeholderWarning)),
      );
    });

    test('doctor stays quiet with real values', () async {
      final dir = createTempProject();
      writeFile(dir, 'flavorpilot.yaml', realValues);
      await runFlavorPilot(dir, ['sync']);

      expect(
        await warningsOf(dir, ['doctor']),
        isNot(anyElement(contains(placeholderWarning))),
      );
    });

    test('release only checks the flavor being released', () async {
      final dir = createEmptyDir();
      writeFile(dir, 'pubspec.yaml', fixturePubspec);
      writeFile(
        dir,
        'flavorpilot.yaml',
        realValues.replaceFirst('dev.mycompany.com', 'dev.api.example.com'),
      );

      expect(
        await warningsOf(dir, ['release', 'dev', '--bump', 'none']),
        anyElement(contains('development: base_url')),
      );
      expect(
        await warningsOf(dir, ['release', 'prod', '--bump', 'none']),
        isNot(anyElement(contains(placeholderWarning))),
      );
    });
  });
}
