import 'package:flavorpilot/flavorpilot.dart';
import 'package:test/test.dart';

import '../helpers.dart';

void main() {
  const loader = ConfigLoader();

  group('ConfigLoader.parse', () {
    test('reads flavors with all their fields', () {
      final config = loader.parse('''
main_mode: multiple
flavors:
  development:
    alias: dev
    app_name: "App DEV"
    android_id: com.example.app.dev
    ios_bundle_id: com.example.app.dev
  production:
    alias: prod
''');

      expect(config.mainMode, MainMode.multiple);
      expect(config.flavors.map((f) => f.name), ['development', 'production']);
      final dev = config.flavors.first;
      expect(dev.alias, 'dev');
      expect(dev.appName, 'App DEV');
      expect(dev.androidId, 'com.example.app.dev');
      expect(dev.iosBundleId, 'com.example.app.dev');
    });

    test('defaults to single main mode', () {
      final config = loader.parse('flavors:\n  development: {}\n');
      expect(config.mainMode, MainMode.single);
    });

    test('allows a flavor with no settings', () {
      final config = loader.parse('flavors:\n  staging:\n');
      expect(config.flavors.single.name, 'staging');
      expect(config.flavors.single.alias, isNull);
    });

    test('rejects flavor names Gradle would not accept', () {
      expect(
        () => loader.parse('flavors:\n  my-flavor: {}\n'),
        throwsA(isA<FlavorPilotException>()),
      );
      expect(
        () => loader.parse('flavors:\n  Development: {}\n'),
        throwsA(isA<FlavorPilotException>()),
      );
    });

    test('rejects an alias used twice', () {
      expect(
        () => loader.parse('''
flavors:
  development: {alias: d}
  demo: {alias: d}
'''),
        throwsA(isA<FlavorPilotException>()),
      );
    });

    test('rejects an alias equal to another flavor name', () {
      expect(
        () => loader.parse('''
flavors:
  development: {alias: production}
  production: {}
'''),
        throwsA(isA<FlavorPilotException>()),
      );
    });

    test('rejects a file without flavors', () {
      expect(
        () => loader.parse('main_mode: single\n'),
        throwsA(isA<FlavorPilotException>()),
      );
      expect(
        () => loader.parse('flavors: {}\n'),
        throwsA(isA<FlavorPilotException>()),
      );
    });

    test('rejects an unknown main_mode', () {
      expect(
        () => loader.parse('main_mode: many\nflavors:\n  dev: {}\n'),
        throwsA(isA<FlavorPilotException>()),
      );
    });

    test('turns broken YAML into a friendly error', () {
      expect(
        () => loader.parse('flavors: [unclosed'),
        throwsA(isA<FlavorPilotException>()),
      );
    });
  });

  group('env', () {
    /// A config with two flavors, each with the given `env` lines.
    String withEnv(String dev, String prod) =>
        '''
flavors:
  development:
    env:
      $dev
  production:
    env:
      $prod
''';

    test('reads text, number and true/false values with their types', () {
      final env = loader
          .parse('''
flavors:
  development:
    env:
      base_url: "https://dev.example.com"
      enable_logs: true
      retries: 3
      ratio: 0.5
''')
          .flavors
          .single
          .env;

      expect(env, {
        'base_url': 'https://dev.example.com',
        'enable_logs': true,
        'retries': 3,
        'ratio': 0.5,
      });
    });

    test('allows mixing whole and decimal numbers', () {
      final config = loader.parse(withEnv('ratio: 1', 'ratio: 0.5'));
      expect(config.flavors.first.env['ratio'], 1);
    });

    /// Expects [yaml] to be rejected with a message containing [message].
    void expectRejected(String yaml, String message) {
      expect(
        () => loader.parse(yaml),
        throwsA(
          isA<FlavorPilotException>().having(
            (e) => e.message,
            'message',
            contains(message),
          ),
        ),
      );
    }

    test('rejects a key missing from another flavor', () {
      expectRejected(
        withEnv('base_url: "a"', 'other: "b"'),
        'missing from: production',
      );
    });

    test('rejects a flavor with no env when others have it', () {
      expectRejected('''
flavors:
  development:
    env:
      base_url: "a"
  production: {}
''', 'missing from: production');
    });

    test('rejects different types across flavors', () {
      expectRejected(
        withEnv('value: "1"', 'value: 1'),
        'different types across flavors',
      );
      expectRejected(
        withEnv('value: true', 'value: "true"'),
        'different types across flavors',
      );
    });

    test('rejects invalid keys', () {
      for (final key in ['baseUrl', 'base-url', '_url', 'a__b', 'url_']) {
        expectRejected(withEnv('$key: "a"', '$key: "b"'), 'invalid env key');
      }
    });

    test('rejects keys that would break the generated enum', () {
      for (final key in ['name', 'app_name', 'index', 'class', 'to_string']) {
        expectRejected(withEnv('$key: "a"', '$key: "b"'), 'is reserved');
      }
    });

    test('rejects a key that clashes with a flavor name', () {
      expectRejected(
        withEnv('production: "a"', 'production: "b"'),
        'clashes with the flavor',
      );
    });

    test('rejects two keys that become the same field', () {
      expectRejected('''
flavors:
  development:
    env:
      a_1: "x"
      a1: "y"
''', 'both become the field "a1"');
    });

    test('rejects nested, empty and infinite values', () {
      expectRejected('''
flavors:
  development:
    env:
      nested: {a: 1}
''', 'must be a text, number');
      expectRejected('''
flavors:
  development:
    env:
      empty:
''', 'must be a text, number');
      expectRejected('''
flavors:
  development:
    env:
      big: .inf
''', 'finite number');
    });

    test('rejects env that is not a map', () {
      expectRejected('''
flavors:
  development:
    env: "x"
''', 'env must be a YAML map');
    });
  });

  group('icon', () {
    test('reads the icon path', () {
      final config = loader.parse('''
flavors:
  development:
    icon: assets/dev.png
''');
      expect(config.flavors.single.icon, 'assets/dev.png');
    });

    test('rejects an icon that is not a path', () {
      expect(
        () => loader.parse('''
flavors:
  development:
    icon: 12
'''),
        throwsA(isA<FlavorPilotException>()),
      );
    });
  });

  group('ConfigLoader.load', () {
    test('explains how to fix a missing file', () {
      expect(
        () => loader.load(createEmptyDir()),
        throwsA(
          isA<FlavorPilotException>().having(
            (e) => e.message,
            'message',
            contains('flavorpilot init'),
          ),
        ),
      );
    });
  });

  group('ProjectConfig', () {
    final config = loader.parse('''
flavors:
  development: {alias: dev}
  production: {}
''');

    test('finds a flavor by name or alias', () {
      expect(config.findFlavor('development')?.name, 'development');
      expect(config.findFlavor('dev')?.name, 'development');
      expect(config.findFlavor('production')?.name, 'production');
      expect(config.findFlavor('prod'), isNull);
    });

    test('entry point depends on main mode', () {
      final flavor = config.flavors.first;
      expect(config.entryPointFor(flavor), isNull);

      final multiple = ProjectConfig(
        flavors: config.flavors,
        mainMode: MainMode.multiple,
      );
      expect(multiple.entryPointFor(flavor), 'lib/main_development.dart');
    });
  });
}
