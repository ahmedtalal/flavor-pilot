import '../models/project_config.dart';
import '../utils/file_changes.dart';
import '../utils/logger.dart';

/// Base class for everything that edits or creates files in the user's
/// Flutter project (Android, iOS, Dart, IDE).
///
/// Generators never write to disk themselves. They read the current files
/// and record the new contents in a [FileChanges]; the command applies all
/// changes together only after every generator has finished without errors.
///
/// Generators are shared by `init` (first setup) and later by `add` (adding
/// a flavor), so each one must be safe to run more than once: running it
/// again replaces what it wrote before instead of adding a duplicate.
abstract class Generator {
  Generator({required this.projectDir, required this.logger});

  /// Root folder of the Flutter project.
  final String projectDir;

  /// Prints warnings about steps that were skipped.
  final Logger logger;

  /// Short name shown in logs, e.g. `Android`.
  String get label;

  /// Records the file changes needed to apply [config] into [changes].
  ///
  /// Throws a FlavorPilotException when a file can't be updated safely.
  void generate(ProjectConfig config, FileChanges changes);
}
