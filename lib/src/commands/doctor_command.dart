import 'dart:io';

import 'package:path/path.dart' as p;

import '../generators/project_setup.dart';
import '../utils/exceptions.dart';
import 'flavorpilot_command.dart';

/// `flavorpilot doctor`: checks that every flavor is set up correctly.
///
/// How it works: it asks every generator what the files *should* look like
/// for the current `flavorpilot.yaml` (without writing anything), then
/// compares that with the files on disk. Any difference means a file was
/// edited by hand or `flavorpilot.yaml` changed without running `sync`.
///
/// Exits with 0 when everything matches, 1 otherwise.
class DoctorCommand extends FlavorPilotCommand {
  DoctorCommand({
    required super.logger,
    required super.processRunner,
    required super.projectDir,
    super.configLoader,
  });

  /// Xcode object ids: 24 uppercase hex characters.
  static final _xcodeId = RegExp(r'\b[0-9A-F]{24}\b');

  @override
  String get name => 'doctor';

  @override
  String get description => 'Check that every flavor is set up correctly.';

  @override
  Future<int> run() async {
    final config = loadConfig();
    logger.success(
      'flavorpilot.yaml is valid (${config.flavors.length} flavors, '
      '${config.mainMode.name} main mode)',
    );

    final setup = ProjectSetup(projectDir: projectDir, logger: logger);
    final Map<String, String> expected;
    try {
      expected = setup.plan(config).writes;
    } on FlavorPilotException catch (e) {
      // A generator refused to plan, e.g. because of hand-made flavors.
      logger.error(e.message);
      return 1;
    }

    final outdated = [
      for (final MapEntry(key: path, value: content) in expected.entries)
        if (!_matches(path, content)) p.relative(path, from: projectDir),
    ];

    if (outdated.isEmpty) {
      logger.success('All flavor files are up to date.');
      return 0;
    }

    logger.error('These files are missing or out of date:');
    for (final path in outdated) {
      logger.info('    $path');
    }
    logger.info('Run `flavorpilot sync` to fix them.');
    return 1;
  }

  /// True when the file at [path] already has the [expected] content.
  bool _matches(String path, String expected) {
    final file = File(path);
    if (!file.existsSync()) return false;
    final actual = file.readAsStringSync();

    // New Xcode configurations get random ids each time they are planned,
    // so compare the project file with every id masked out.
    if (path.endsWith('.pbxproj')) {
      return _maskIds(actual) == _maskIds(expected);
    }
    return actual == expected;
  }

  String _maskIds(String text) => text.replaceAll(_xcodeId, 'ID');
}
