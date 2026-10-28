import 'package:test/test.dart';

import '../helpers.dart';

void main() {
  const yaml = '''
flavors:
  development: {alias: dev}
  qualityAssurance: {alias: qa}
''';

  /// A folder with only flavorpilot.yaml, enough for run/build.
  String projectWith(String config) {
    final dir = createEmptyDir();
    writeFile(dir, 'flavorpilot.yaml', config);
    return dir;
  }

  group('run', () {
    test('turns an alias into the full flutter run command', () async {
      final fake = FakeProcessRunner();
      final code = await runFlavorPilot(projectWith(yaml), [
        'run',
        'dev',
        '-d',
        'emulator-5554',
        '--',
        '--dart-define=X=1',
      ], processRunner: fake);

      expect(code, 0);
      expect(fake.calls.single, [
        'flutter',
        'run',
        '--flavor',
        'development',
        '--debug',
        '-d',
        'emulator-5554',
        '--dart-define=X=1',
      ]);
    });

    test('adds the entry point in multiple main mode', () async {
      final fake = FakeProcessRunner();
      await runFlavorPilot(projectWith('main_mode: multiple\n$yaml'), [
        'run',
        'qa',
      ], processRunner: fake);

      expect(
        fake.calls.single,
        containsAllInOrder(['-t', 'lib/main_qualityAssurance.dart']),
      );
    });

    test('returns flutter\'s exit code', () async {
      final code = await runFlavorPilot(projectWith(yaml), [
        'run',
        'dev',
      ], processRunner: FakeProcessRunner(exitCode: 3));
      expect(code, 3);
    });
  });

  group('build', () {
    test('builds a release appbundle by default mode', () async {
      final fake = FakeProcessRunner();
      await runFlavorPilot(projectWith(yaml), [
        'build',
        'qa',
        '--target',
        'appbundle',
      ], processRunner: fake);

      expect(fake.calls.single, [
        'flutter',
        'build',
        'appbundle',
        '--flavor',
        'qualityAssurance',
        '--release',
      ]);
    });
  });

  group('errors', () {
    test('unknown flavor exits with 1 and runs nothing', () async {
      final fake = FakeProcessRunner();
      final code = await runFlavorPilot(projectWith(yaml), [
        'run',
        'staging',
      ], processRunner: fake);

      expect(code, 1);
      expect(fake.calls, isEmpty);
    });

    test('missing flavor is a usage error (64)', () async {
      final code = await runFlavorPilot(projectWith(yaml), ['build']);
      expect(code, 64);
    });

    test('missing flavorpilot.yaml exits with 1', () async {
      final code = await runFlavorPilot(createEmptyDir(), ['run', 'dev']);
      expect(code, 1);
    });
  });
}
