import 'dart:io';

import 'package:path/path.dart' as p;

import '../generators/project_setup.dart';
import '../models/flavor.dart';
import '../models/project_config.dart';
import '../utils/exceptions.dart';
import '../utils/flavor_questions.dart';
import '../utils/prompter.dart';
import '../utils/signing_key.dart';
import 'flavorpilot_command.dart';

/// `flavorpilot signing [flavor]`: sets up the Android signing key that
/// release builds are signed with, e.g. for Google Play.
///
/// Examples:
///
/// ```sh
/// flavorpilot signing                         # one new key for every flavor
/// flavorpilot signing prod                    # a separate key for production
/// flavorpilot signing --keystore my-key.jks   # use a key you already have
/// ```
///
/// Creates the key with Java's `keytool` (or uses an existing keystore),
/// writes a `.properties` file with its passwords, keeps both out of Git, and
/// sets `android_signing` in `flavorpilot.yaml`. Existing keys are never
/// overwritten.
class SigningCommand extends FlavorPilotCommand {
  SigningCommand({
    required super.logger,
    required super.processRunner,
    required super.projectDir,
    super.configLoader,
    String? Function()? readLine,
  }) : _readLine = readLine {
    argParser
      ..addOption(
        'keystore',
        help:
            'Use a keystore (.jks) you already have, instead of creating a '
            'new key.',
        valueHelp: 'path',
      )
      ..addOption(
        'alias',
        help: 'Name of the key inside the keystore.',
        defaultsTo: 'upload',
      );
  }

  /// Reads the user's answers; replaceable in tests.
  final String? Function()? _readLine;

  /// Folder for the keys flavorpilot creates.
  static const keysDir = 'android/keys';

  /// Environment variable that passes the password to keytool, so it never
  /// shows up in the command line.
  static const _passwordVariable = 'FLAVORPILOT_KEY_PASSWORD';

  /// keytool rejects shorter passwords.
  static const _minPasswordLength = 6;

  @override
  String get name => 'signing';

  @override
  String get description =>
      'Set up the Android signing key for release builds.';

  @override
  String get invocation => 'flavorpilot signing [flavor] [options]';

  @override
  Future<int> run() async {
    final config = loadConfig();
    final flavor = _targetFlavor(config);
    final fileName = flavor?.name ?? 'upload';
    final propertiesPath = '$keysDir/$fileName.properties';
    _checkNotSetUp(config, flavor, propertiesPath);

    final prompter = Prompter(readLine: _readLine);
    final alias = _checked('The alias', argResults!.option('alias')!);
    final existing = argResults!.option('keystore');

    final created = <File>[];
    try {
      final properties = existing == null
          ? await _createKey(prompter, fileName, alias, created)
          : await _useKeystore(prompter, existing, alias, propertiesPath);
      final propertiesFile = File(p.join(projectDir, propertiesPath));
      propertiesFile
        ..parent.createSync(recursive: true)
        ..writeAsStringSync(SigningKey.format(properties));
      created.add(propertiesFile);

      ProjectSetup(
        projectDir: projectDir,
        logger: logger,
      ).apply(_withSigning(config, flavor, propertiesPath), saveConfig: true);
    } catch (_) {
      // Nothing uses a key that was just made, so removing it is safe.
      for (final file in created) {
        if (file.existsSync()) file.deleteSync();
      }
      rethrow;
    }

    _printNextSteps(flavor, propertiesPath, isNewKey: existing == null);
    return 0;
  }

  /// The flavor named on the command line, or null for every flavor.
  Flavor? _targetFlavor(ProjectConfig config) {
    final rest = argResults!.rest;
    if (rest.length > 1) {
      usageException(
        'Give at most one flavor, e.g. `flavorpilot signing prod`.',
      );
    }
    if (rest.isEmpty) return null;
    return config.findFlavor(rest.single) ??
        (throw FlavorPilotException(
          'Unknown flavor "${rest.single}". Available flavors: '
          '${config.flavors.map((f) => f.name).join(', ')}.',
        ));
  }

  /// Stops if a key is already set up, so a key is never replaced by
  /// mistake (losing it can lock you out of updating your app).
  void _checkNotSetUp(
    ProjectConfig config,
    Flavor? flavor,
    String propertiesPath,
  ) {
    final current = flavor == null
        ? config.androidSigning
        : flavor.androidSigning;
    final who = flavor == null ? 'Every flavor' : '"${flavor.name}"';
    if (current != null) {
      throw FlavorPilotException(
        '$who already has a signing key ($current). To use another one, '
        'remove android_signing from flavorpilot.yaml first.',
      );
    }
    if (File(p.join(projectDir, propertiesPath)).existsSync()) {
      throw FlavorPilotException(
        '$propertiesPath already exists. Set it as android_signing in '
        'flavorpilot.yaml, or move it away first.',
      );
    }
  }

  /// Creates a new key with keytool and returns its properties.
  Future<Map<String, String>> _createKey(
    Prompter prompter,
    String fileName,
    String alias,
    List<File> created,
  ) async {
    final keystorePath = '$keysDir/$fileName.jks';
    final keystore = File(p.join(projectDir, keystorePath));
    if (keystore.existsSync()) {
      throw FlavorPilotException(
        '$keystorePath already exists. Use it with '
        '`flavorpilot signing --keystore $keystorePath`, or move it away.',
      );
    }

    final password = _askNewPassword(prompter);
    final owner = prompter.ask(
      'Your name or company (stored in the key)',
      defaultValue: FlavorQuestions(
        projectDir: projectDir,
        prompter: prompter,
      ).defaultAppName(),
    );

    keystore.parent.createSync(recursive: true);
    final exitCode = await processRunner.run(
      _keytool(),
      [
        '-genkeypair',
        '-keystore',
        keystore.path,
        '-storetype',
        'PKCS12',
        '-alias',
        alias,
        '-keyalg',
        'RSA',
        '-keysize',
        '2048',
        // About 27 years. Google Play needs keys valid until at least 2033.
        '-validity',
        '10000',
        '-dname',
        'CN=${_escapeDname(owner)}',
        '-storepass:env',
        _passwordVariable,
        '-keypass:env',
        _passwordVariable,
      ],
      workingDirectory: projectDir,
      environment: {_passwordVariable: password},
    );
    if (keystore.existsSync()) created.add(keystore);
    if (exitCode != 0) {
      throw const FlavorPilotException(
        'keytool could not create the key, so nothing was changed.',
      );
    }

    return {
      'storeFile': '$fileName.jks',
      'storePassword': password,
      'keyAlias': alias,
      // PKCS12 keystores use the same password for the key.
      'keyPassword': password,
    };
  }

  /// Checks an existing keystore with keytool and returns its properties.
  Future<Map<String, String>> _useKeystore(
    Prompter prompter,
    String keystorePath,
    String alias,
    String propertiesPath,
  ) async {
    final keystore = File(p.join(projectDir, keystorePath));
    if (!keystore.existsSync()) {
      throw FlavorPilotException('The keystore $keystorePath was not found.');
    }
    final storePassword = _checked(
      'The password',
      prompter.askSecret('Keystore password'),
    );
    final keyPassword = _checked(
      'The key password',
      prompter.askSecret('Key password (press Enter if it is the same)'),
    );

    // Opening the key now catches a wrong password or alias before a build.
    final exitCode = await processRunner.run(
      _keytool(),
      [
        '-list',
        '-keystore',
        keystore.absolute.path,
        '-alias',
        alias,
        '-storepass:env',
        _passwordVariable,
      ],
      workingDirectory: projectDir,
      environment: {_passwordVariable: storePassword},
    );
    if (exitCode != 0) {
      throw FlavorPilotException(
        'Could not open the key "$alias" in $keystorePath. Check the password '
        'and the --alias option. Nothing was changed.',
      );
    }

    final propertiesDir = p.dirname(p.join(projectDir, propertiesPath));
    final storeFile = p.relative(
      keystore.absolute.path,
      from: p.normalize(p.absolute(propertiesDir)),
    );
    return {
      // Inside the project a relative path keeps it working on every
      // computer; outside it, the absolute path is clearer.
      'storeFile': p.posix.joinAll(
        p.split(
          p.isWithin(projectDir, keystore.absolute.path)
              ? storeFile
              : keystore.absolute.path,
        ),
      ),
      'storePassword': storePassword,
      'keyAlias': alias,
      'keyPassword': keyPassword.isEmpty ? storePassword : keyPassword,
    };
  }

  /// Asks for a new password twice, so a typo doesn't lock the key.
  String _askNewPassword(Prompter prompter) {
    final password = _checked(
      'The password',
      prompter.askSecret(
        'Key password (at least $_minPasswordLength characters)',
      ),
    );
    if (password.length < _minPasswordLength) {
      throw const FlavorPilotException(
        'The password must have at least $_minPasswordLength characters.',
      );
    }
    if (prompter.askSecret('Repeat the password') != password) {
      throw const FlavorPilotException(
        'The passwords did not match. Nothing was changed.',
      );
    }
    return password;
  }

  /// Returns [value], or stops when it can't be stored in the key's
  /// `.properties` file (see [SigningKey.unsupportedValue]).
  String _checked(String what, String value) {
    final problem = SigningKey.unsupportedValue(value);
    if (problem != null) {
      throw FlavorPilotException(
        "$what can't be used, because $problem. Nothing was changed.",
      );
    }
    return value;
  }

  /// [config] with [propertiesPath] as the key of [flavor], or of every
  /// flavor when [flavor] is null.
  ProjectConfig _withSigning(
    ProjectConfig config,
    Flavor? flavor,
    String propertiesPath,
  ) {
    if (flavor == null) return config.copyWith(androidSigning: propertiesPath);
    return config.copyWith(
      flavors: [
        for (final f in config.flavors)
          f == flavor ? f.copyWith(androidSigning: propertiesPath) : f,
      ],
    );
  }

  /// Finds keytool: from JAVA_HOME, Android Studio's Java, or the PATH.
  String _keytool() {
    final exe = Platform.isWindows ? 'keytool.exe' : 'keytool';
    final javaHome = Platform.environment['JAVA_HOME'];
    final candidates = [
      if (javaHome != null) p.join(javaHome, 'bin', exe),
      '/Applications/Android Studio.app/Contents/jbr/Contents/Home/bin/$exe',
      r'C:\Program Files\Android\Android Studio\jbr\bin\keytool.exe',
      '/opt/android-studio/jbr/bin/$exe',
    ];
    for (final path in candidates) {
      if (File(path).existsSync()) return path;
    }
    return 'keytool';
  }

  /// Escapes characters that are special in a certificate name.
  String _escapeDname(String value) =>
      value.replaceAllMapped(RegExp(r'[,+="<>;\\#]'), (m) => '\\${m[0]}');

  void _printNextSteps(
    Flavor? flavor,
    String propertiesPath, {
    required bool isNewKey,
  }) {
    final who = flavor == null ? 'every flavor' : '"${flavor.name}"';
    logger
      ..info('')
      ..success('Release builds of $who are now signed with this key.')
      ..info(
        'Try it: flavorpilot release ${flavor?.alias ?? flavor?.name ?? '<flavor>'}',
      );
    if (isNewKey) {
      logger.warn(
        'Back up ${p.dirname(propertiesPath)}/ (the key and its password) '
        'somewhere safe, outside this project. If you lose the key, you may '
        'not be able to update your app on Google Play.',
      );
    }
    logger.info(
      'Teammates and CI need the same files in ${p.dirname(propertiesPath)}/ '
      'to sign release builds.',
    );
  }
}
