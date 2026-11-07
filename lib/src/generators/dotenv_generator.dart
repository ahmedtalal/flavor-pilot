import 'dart:io';

import 'package:path/path.dart' as p;

import '../models/project_config.dart';
import '../utils/file_changes.dart';
import 'generator.dart';

/// Creates each flavor's `.env` file, if it doesn't exist yet.
///
/// An existing file is never changed, because it holds the developer's own
/// values. GitignoreGenerator keeps the files out of Git.
class DotenvGenerator extends Generator {
  DotenvGenerator({required super.projectDir, required super.logger});

  @override
  String get label => 'dotenv';

  @override
  void generate(ProjectConfig config, FileChanges changes) {
    final envFiles = [
      for (final flavor in config.flavors)
        if (flavor.envFile case final envFile?) (flavor.name, envFile),
    ];

    for (final (flavor, envFile) in envFiles) {
      final file = File(p.join(projectDir, envFile));
      if (file.existsSync()) continue;
      changes
        ..write(
          file.path,
          '# Values for the "$flavor" flavor, one per line: KEY=value\n'
          '# Read them in Dart with String.fromEnvironment(\'KEY\').\n'
          '# This file is in .gitignore: never commit it.\n',
        )
        ..note('Created $envFile');
    }
  }
}
