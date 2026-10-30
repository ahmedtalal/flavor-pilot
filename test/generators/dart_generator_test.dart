import 'package:flavorpilot/flavorpilot.dart';
import 'package:flavorpilot/src/generators/dart_generator.dart';
import 'package:flavorpilot/src/utils/file_changes.dart';
import 'package:flavorpilot/src/utils/logger.dart';
import 'package:test/test.dart';

import '../helpers.dart';

void main() {
  /// Generates `lib/flavors.dart` for [config] and returns its content.
  String generate(ProjectConfig config) {
    final dir = createEmptyDir();
    final changes = FileChanges();
    DartGenerator(
      projectDir: dir,
      logger: Logger(useColors: false),
    ).generate(config, changes);
    changes.apply();
    return readFile(dir, 'lib/flavors.dart');
  }

  test('without env it only has appName', () {
    final code = generate(
      const ProjectConfig(
        flavors: [Flavor(name: 'development', appName: 'App DEV')],
      ),
    );

    expect(code, contains("development(appName: 'App DEV');"));
    expect(code, contains('const AppFlavor({required this.appName});'));
  });

  test('each env key becomes a typed camelCase field', () {
    final code = generate(
      const ProjectConfig(
        flavors: [
          Flavor(
            name: 'development',
            appName: 'App DEV',
            env: {
              'base_url': 'https://dev.example.com',
              'enable_logs': true,
              'max_retries': 5,
              'ratio': 1,
            },
          ),
          Flavor(
            name: 'production',
            appName: 'App',
            env: {
              'base_url': 'https://example.com',
              'enable_logs': false,
              'max_retries': 3,
              'ratio': 0.5,
            },
          ),
        ],
      ),
    );

    expect(code, contains('final String baseUrl;'));
    expect(code, contains('final bool enableLogs;'));
    expect(code, contains('final int maxRetries;'));
    // A mix of whole and decimal numbers becomes double.
    expect(code, contains('final double ratio;'));
    expect(code, contains('required this.baseUrl'));
    expect(
      code,
      contains(
        "development(appName: 'App DEV', "
        "baseUrl: 'https://dev.example.com', enableLogs: true, "
        'maxRetries: 5, ratio: 1)',
      ),
    );
    expect(code, contains('ratio: 0.5)'));
  });

  test('escapes characters that are special in Dart strings', () {
    final code = generate(
      const ProjectConfig(
        flavors: [
          Flavor(name: 'development', env: {'note': "it's \$5\nback\\slash"}),
        ],
      ),
    );

    expect(code, contains(r"note: 'it\'s \$5\nback\\slash'"));
  });
}
