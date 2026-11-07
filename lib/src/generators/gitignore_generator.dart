import 'dart:io';

import 'package:path/path.dart' as p;

import '../models/project_config.dart';
import '../utils/file_changes.dart';
import '../utils/signing_key.dart';
import 'generator.dart';

/// Keeps private files out of Git: each flavor's `.env` file, and the
/// Android signing keys (`.properties` files and their keystores).
///
/// They are listed in `.gitignore` between `# flavorpilot:start` and
/// `# flavorpilot:end`. When there's nothing to list, the block is removed.
/// Files outside the project don't need listing and are skipped.
class GitignoreGenerator extends Generator {
  GitignoreGenerator({required super.projectDir, required super.logger});

  static const _startMarker = '# flavorpilot:start';
  static const _endMarker = '# flavorpilot:end';

  /// Our block in `.gitignore`, with the line breaks around it.
  static final _block = RegExp(
    '\\n*${RegExp.escape(_startMarker)}[\\s\\S]*?'
    '${RegExp.escape(_endMarker)}\\n?',
  );

  @override
  String get label => 'gitignore';

  @override
  void generate(ProjectConfig config, FileChanges changes) {
    final signing = {
      for (final flavor in config.flavors) ?config.signingFor(flavor),
    };
    final private = <String>{
      for (final flavor in config.flavors) ?flavor.envFile,
      for (final path in signing) ...[
        path,
        ?SigningKey.read(projectDir, path)?.storeFile,
      ],
    }.where(_isInProject);

    _write(private.map(_gitPath).toSet(), changes);
  }

  bool _isInProject(String path) {
    if (p.isAbsolute(path)) return p.isWithin(projectDir, path);
    return !p.split(p.normalize(path)).contains('..');
  }

  /// [path] as `.gitignore` expects it: relative, with `/` separators.
  String _gitPath(String path) {
    final relative = p.isAbsolute(path)
        ? p.relative(path, from: projectDir)
        : p.normalize(path);
    return p.posix.joinAll(p.split(relative));
  }

  /// Puts our block in `.gitignore`, or removes it when [paths] is empty.
  void _write(Set<String> paths, FileChanges changes) {
    final file = File(p.join(projectDir, '.gitignore'));
    final current = file.existsSync() ? file.readAsStringSync() : '';
    if (paths.isEmpty && !current.contains(_startMarker)) return;

    // The developer's own lines, without our block.
    var content = current.replaceAll(_block, '');
    if (content.isNotEmpty && !content.endsWith('\n')) content += '\n';
    if (paths.isNotEmpty) {
      content +=
          '${content.isEmpty ? '' : '\n'}$_startMarker\n'
          '# Private files (.env values, signing keys): never commit them.\n'
          '${paths.join('\n')}\n'
          '$_endMarker\n';
    }
    if (content == current) return;

    changes
      ..write(file.path, content)
      ..note('Updated .gitignore');
  }
}
