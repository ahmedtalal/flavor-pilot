import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:flavorpilot/flavorpilot.dart';
import 'package:flavorpilot/src/commands/signing_command.dart';
import 'package:flavorpilot/src/generators/android_generator.dart';
import 'package:flavorpilot/src/utils/file_changes.dart';
import 'package:flavorpilot/src/utils/logger.dart';
import 'package:flavorpilot/src/utils/signing_key.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../helpers.dart';

void main() {
  const gradlePath = 'android/app/build.gradle.kts';
  const twoFlavors = '''
flavors:
  development: {alias: dev}
  production: {alias: prod}
''';

  bool exists(String dir, String path) => File(p.join(dir, path)).existsSync();

  /// A fake keytool: `-genkeypair` creates the keystore file it names.
  FakeProcessRunner fakeKeytool({int exitCode = 0}) => FakeProcessRunner(
    exitCode: exitCode,
    onRun: (args) {
      if (exitCode == 0 && args.first == '-genkeypair') {
        File(args[args.indexOf('-keystore') + 1])
          ..parent.createSync(recursive: true)
          ..writeAsStringSync('fake keystore');
      }
    },
  );

  /// Runs `signing` with [args], typing [answers] to its questions.
  Future<int?> runSigning(
    String dir,
    List<String> args,
    List<String> answers, {
    FakeProcessRunner? keytool,
  }) {
    return (CommandRunner<int>('flavorpilot', 'test')..addCommand(
          SigningCommand(
            logger: Logger(useColors: false),
            processRunner: keytool ?? fakeKeytool(),
            projectDir: dir,
            readLine: () => answers.removeAt(0),
          ),
        ))
        .run(['signing', ...args]);
  }

  /// A project with the fixture files and two flavors, set up by `sync`.
  Future<String> setUpProject() async {
    final dir = createTempProject();
    writeFile(dir, 'flavorpilot.yaml', twoFlavors);
    await runFlavorPilot(dir, ['sync']);
    return dir;
  }

  group('signing (new key)', () {
    test('creates one key for every flavor', () async {
      final dir = await setUpProject();
      final keytool = fakeKeytool();

      final code = await runSigning(dir, [], [
        'secret123',
        'secret123',
        'Acme',
      ], keytool: keytool);

      expect(code, 0);
      expect(exists(dir, 'android/keys/upload.jks'), isTrue);
      final key = SigningKey.read(dir, 'android/keys/upload.properties')!;
      expect(key.values, {
        'storeFile': 'upload.jks',
        'storePassword': 'secret123',
        'keyAlias': 'upload',
        'keyPassword': 'secret123',
      });
      expect(key.problems(dir), isEmpty);
      expect(
        const ConfigLoader().load(dir).androidSigning,
        'android/keys/upload.properties',
      );
    });

    test('never puts the password in the command line', () async {
      final dir = await setUpProject();
      final keytool = fakeKeytool();

      await runSigning(dir, [], [
        'secret123',
        'secret123',
        'Acme, Inc.',
      ], keytool: keytool);

      final args = keytool.calls.single;
      expect(args.join(' '), isNot(contains('secret123')));
      expect(keytool.environments.single, {
        'FLAVORPILOT_KEY_PASSWORD': 'secret123',
      });
      // Commas are special in certificate names.
      expect(args, contains(r'CN=Acme\, Inc.'));
    });

    test('keeps the key files out of git', () async {
      final dir = await setUpProject();

      await runSigning(dir, [], ['secret123', 'secret123', '']);

      expect(
        readFile(dir, '.gitignore'),
        allOf(
          contains('android/keys/upload.properties\n'),
          contains('android/keys/upload.jks\n'),
        ),
      );
    });

    test('a flavor gets its own key, and others keep theirs', () async {
      final dir = await setUpProject();
      await runSigning(dir, [], ['secret123', 'secret123', '']);

      await runSigning(dir, ['prod'], ['other123', 'other123', '']);

      final config = const ConfigLoader().load(dir);
      expect(
        config.signingFor(config.findFlavor('prod')!),
        'android/keys/production.properties',
      );
      expect(
        config.signingFor(config.findFlavor('dev')!),
        'android/keys/upload.properties',
      );
      expect(exists(dir, 'android/keys/production.jks'), isTrue);
    });

    test('passwords that don\'t match change nothing', () async {
      final dir = await setUpProject();
      final keytool = fakeKeytool();

      await expectLater(
        runSigning(dir, [], ['secret123', 'secret124'], keytool: keytool),
        throwsA(isA<FlavorPilotException>()),
      );
      expect(keytool.calls, isEmpty);
      expect(Directory(p.join(dir, 'android/keys')).existsSync(), isFalse);
    });

    test('a too short password changes nothing', () async {
      final dir = await setUpProject();
      final keytool = fakeKeytool();

      await expectLater(
        runSigning(dir, [], ['12345'], keytool: keytool),
        throwsA(isA<FlavorPilotException>()),
      );
      expect(keytool.calls, isEmpty);
    });

    test('a keytool failure leaves no files behind', () async {
      final dir = await setUpProject();
      final before = readFile(dir, 'flavorpilot.yaml');

      await expectLater(
        runSigning(dir, [], [
          'secret123',
          'secret123',
          '',
        ], keytool: fakeKeytool(exitCode: 1)),
        throwsA(isA<FlavorPilotException>()),
      );
      expect(exists(dir, 'android/keys/upload.properties'), isFalse);
      expect(readFile(dir, 'flavorpilot.yaml'), before);
    });

    test('never replaces a key that is set up', () async {
      final dir = await setUpProject();
      await runSigning(dir, [], ['secret123', 'secret123', '']);
      final properties = readFile(dir, 'android/keys/upload.properties');

      await expectLater(
        runSigning(dir, [], ['other123', 'other123', '']),
        throwsA(isA<FlavorPilotException>()),
      );
      expect(readFile(dir, 'android/keys/upload.properties'), properties);
    });
  });

  group('signing --keystore', () {
    test('uses an existing key after checking it', () async {
      final dir = await setUpProject();
      writeFile(dir, 'keys/old.jks', 'existing keystore');
      final keytool = fakeKeytool();

      await runSigning(
        dir,
        ['--keystore', 'keys/old.jks', '--alias', 'release'],
        ['store:pw#1', ''],
        keytool: keytool,
      );

      expect(keytool.calls.single, contains('-list'));
      final key = SigningKey.read(dir, 'android/keys/upload.properties')!;
      expect(key.values['storeFile'], '../../keys/old.jks');
      expect(key.storeFile, 'keys/old.jks');
      expect(key.values['keyAlias'], 'release');
      // Special characters survive the .properties file.
      expect(key.values['storePassword'], 'store:pw#1');
      expect(key.values['keyPassword'], 'store:pw#1');
      expect(readFile(dir, 'keys/old.jks'), 'existing keystore');
    });

    test('a wrong password changes nothing', () async {
      final dir = await setUpProject();
      writeFile(dir, 'keys/old.jks', 'existing keystore');

      await expectLater(
        runSigning(
          dir,
          ['--keystore', 'keys/old.jks'],
          ['wrong', ''],
          keytool: fakeKeytool(exitCode: 1),
        ),
        throwsA(isA<FlavorPilotException>()),
      );
      expect(exists(dir, 'android/keys/upload.properties'), isFalse);
      expect(const ConfigLoader().load(dir).androidSigning, isNull);
    });
  });

  group('Gradle', () {
    ProjectConfig signed(String gradleFile) {
      return const ProjectConfig(
        androidSigning: 'android/keys/upload.properties',
        flavors: [
          Flavor(name: 'development'),
          Flavor(
            name: 'production',
            androidSigning: 'android/keys/production.properties',
          ),
        ],
      );
    }

    String generate(String dir, ProjectConfig config, String gradleFile) {
      final changes = FileChanges();
      AndroidGenerator(
        projectDir: dir,
        logger: Logger(useColors: false),
      ).generate(config, changes);
      changes.apply();
      return readFile(dir, gradleFile);
    }

    test('Kotlin: loads each key and signs each flavor with it', () {
      final dir = createTempProject();
      final gradle = generate(dir, signed(gradlePath), gradlePath);

      expect(
        gradle,
        contains('val flavorpilotKey0 = file("../keys/upload.properties")'),
      );
      expect(
        gradle,
        contains('val flavorpilotKey1 = file("../keys/production.properties")'),
      );
      expect(
        gradle,
        contains(
          'signingConfig = signingConfigs.findByName("flavorpilotKey1") ?: '
          'signingConfigs.getByName("debug")',
        ),
      );
      expect(
        gradle,
        endsWith(
          'android.buildTypes.getByName("release").signingConfig = null\n'
          '// flavorpilot:end\n',
        ),
      );
    });

    test('Groovy: same setup in Groovy syntax', () {
      final dir = createTempProject();
      File(p.join(dir, gradlePath)).deleteSync();
      writeFile(dir, 'android/app/build.gradle', '''
android {
    buildTypes {
        release {
            signingConfig signingConfigs.debug
        }
    }
}
''');
      final gradle = generate(dir, signed(''), 'android/app/build.gradle');

      expect(
        gradle,
        contains('def flavorpilotKey0 = file("../keys/upload.properties")'),
      );
      expect(
        gradle,
        contains(
          'signingConfig signingConfigs.findByName("flavorpilotKey0") ?: '
          'signingConfigs.debug',
        ),
      );
      expect(
        gradle,
        contains('android.buildTypes.release.signingConfig = null'),
      );
    });

    test('running again, or dropping signing, leaves no duplicates', () {
      final dir = createTempProject();
      final original = readFile(dir, gradlePath);
      generate(dir, signed(gradlePath), gradlePath);
      final once = readFile(dir, gradlePath);

      expect(generate(dir, signed(gradlePath), gradlePath), once);

      const unsigned = ProjectConfig(flavors: [Flavor(name: 'production')]);
      final gradle = generate(dir, unsigned, gradlePath);
      expect(gradle, isNot(contains('signingConfig = null')));
      expect(gradle, isNot(contains('flavorpilotKey')));
      // Back to just the flavors block, with the original file around it.
      expect(AndroidGenerator.removeGeneratedBlock(gradle), original);
    });
  });

  group('safety checks', () {
    Future<String> signedProject() async {
      final dir = await setUpProject();
      await runSigning(dir, [], ['secret123', 'secret123', '']);
      return dir;
    }

    test('release stops when the key is missing', () async {
      final dir = await signedProject();
      File(p.join(dir, 'android/keys/upload.jks')).deleteSync();
      final flutter = FakeProcessRunner();

      final code = await runFlavorPilot(dir, [
        'release',
        'prod',
      ], processRunner: flutter);

      expect(code, 1);
      expect(flutter.calls, isEmpty);
      expect(readFile(dir, 'pubspec.yaml'), fixturePubspec);
    });

    test('release of an iOS ipa doesn\'t need the Android key', () async {
      final dir = await signedProject();
      File(p.join(dir, 'android/keys/upload.properties')).deleteSync();
      final flutter = FakeProcessRunner();

      await runFlavorPilot(dir, [
        'release',
        'prod',
        '--target',
        'ipa',
        '--bump',
        'none',
      ], processRunner: flutter);

      expect(flutter.calls, hasLength(1));
    });

    test(
      'build only warns, since Gradle falls back to the debug key',
      () async {
        final dir = await signedProject();
        File(p.join(dir, 'android/keys/upload.properties')).deleteSync();
        final logger = RecordingLogger();
        final flutter = FakeProcessRunner();

        final code = await FlavorPilotRunner(
          logger: logger,
          processRunner: flutter,
          projectDir: dir,
        ).run(['build', 'prod']);

        expect(code, 0);
        expect(flutter.calls, hasLength(1));
        expect(logger.warnings.join(), contains('debug key'));
      },
    );

    test('add and remove keep the project-wide key', () async {
      final dir = await signedProject();

      await runFlavorPilot(dir, ['add', 'staging', '--yes']);
      await runFlavorPilot(dir, ['remove', 'staging', '--yes']);

      expect(
        const ConfigLoader().load(dir).androidSigning,
        'android/keys/upload.properties',
      );
      expect(await runFlavorPilot(dir, ['doctor']), 0);
    });

    test('remove keeps a flavor\'s own key and warns about it', () async {
      final dir = await setUpProject();
      await runSigning(dir, ['dev'], ['secret123', 'secret123', '']);
      final logger = RecordingLogger();

      await FlavorPilotRunner(
        logger: logger,
        processRunner: FakeProcessRunner(),
        projectDir: dir,
      ).run(['remove', 'dev', '--yes']);

      expect(exists(dir, 'android/keys/development.properties'), isTrue);
      expect(exists(dir, 'android/keys/development.jks'), isTrue);
      expect(
        logger.warnings.join(),
        contains('Kept the signing key android/keys/development.properties'),
      );
    });
  });

  group('SigningKey', () {
    test('passwords with special characters survive a round trip', () {
      const values = {'storePassword': 'a=b:c#d!e f', 'keyAlias': 'upload'};
      final parsed = SigningKey.parseProperties(SigningKey.format(values));
      expect(parsed, values);
    });

    test('values Gradle and Java would read differently are rejected', () {
      for (final value in [r'a\b', ' lead', 'trail ', 'two\nlines']) {
        expect(SigningKey.unsupportedValue(value), isNotNull, reason: value);
      }
      expect(SigningKey.unsupportedValue('fine-Pa55:word#!'), isNull);
    });

    test('signing refuses such a password and changes nothing', () async {
      final dir = await setUpProject();
      final keytool = fakeKeytool();

      await expectLater(
        runSigning(dir, [], [r'back\slash1'], keytool: keytool),
        throwsA(isA<FlavorPilotException>()),
      );
      expect(keytool.calls, isEmpty);
    });

    test('lists what is missing', () {
      final dir = createEmptyDir();
      writeFile(dir, 'k.properties', 'storeFile=k.jks\nkeyAlias=upload\n');

      final problems = SigningKey.read(dir, 'k.properties')!.problems(dir);

      expect(problems, [
        'k.properties is missing: storePassword, keyPassword.',
        'The keystore k.jks was not found.',
      ]);
    });
  });
}
