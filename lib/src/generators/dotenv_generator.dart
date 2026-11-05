import 'dart:io';

import 'package:path/path.dart' as p;

import '../models/project_config.dart';
import '../utils/file_changes.dart';
import 'generator.dart';

/// Creates each flavor's `.env` file and keeps them out of Git.
///
/// For every flavor with an `env_file`:
/// - creates the file if it doesn't exist yet. An existing file is never
///   changed, because it holds the developer's own values.
/// - lists it in `.gitignore`, between `# flavorpilot:start` and
///   `# flavorpilot:end`, so the values are never committed by mistake.
///
/// When no flavor has an `env_file`, the `.gitignore` block is removed.
class DotenvGenerator extends Generator {
  DotenvGenerator({required super.projectDir, required super.logger});

  static const _startMarker = '# flavorpilot:start';
  static const _endMarker = '# flavorpilot:end';

  /// Our block in `.gitignore`, with the line breaks around it.
  static final _block = RegExp(
    '\\n*${RegExp.escape(_startMarker)}[\\s\\S]*?'
    '${RegExp.escape(_endMarker)}\\n?',
  );

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

    _writeGitignore(envFiles.map((e) => e.$2).toSet(), changes);
  }

  /// Puts our block in `.gitignore`, or removes it when [envFiles] is empty.
  void _writeGitignore(Set<String> envFiles, FileChanges changes) {
    final file = File(p.join(projectDir, '.gitignore'));
    final current = file.existsSync() ? file.readAsStringSync() : '';
    if (envFiles.isEmpty && !current.contains(_startMarker)) return;

    // The developer's own lines, without our block.
    var content = current.replaceAll(_block, '');
    if (content.isNotEmpty && !content.endsWith('\n')) content += '\n';
    if (envFiles.isNotEmpty) {
      final lines = envFiles.map((f) => p.posix.joinAll(p.split(f)));
      content +=
          '${content.isEmpty ? '' : '\n'}$_startMarker\n'
          '# .env files hold private values, so they stay out of Git.\n'
          '${lines.join('\n')}\n'
          '$_endMarker\n';
    }
    if (content == current) return;

    changes
      ..write(file.path, content)
      ..note('Updated .gitignore');
  }
}
