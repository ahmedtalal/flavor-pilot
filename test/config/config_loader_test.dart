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
