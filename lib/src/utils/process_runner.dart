import 'dart:io';

import 'exceptions.dart';
import 'logger.dart';

/// Runs external programs such as `flutter`.
///
/// Kept in its own class so tests can replace it with a fake and check which
/// command would have run, without actually running Flutter.
class ProcessRunner {
  ProcessRunner(this._logger);

  final Logger _logger;

  /// Runs [executable] with [arguments] inside [workingDirectory] and returns
  /// its exit code.
  ///
  /// The child process shares this terminal's input and output, so Flutter's
  /// live output and its interactive keys (like `r` for hot reload) work
  /// exactly as if the user had typed the command themselves.
  Future<int> run(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
  }) async {
    _logger.command([executable, ...arguments].join(' '));

    final Process process;
    try {
      process = await Process.start(
        executable,
        arguments,
        workingDirectory: workingDirectory,
        mode: ProcessStartMode.inheritStdio,
        // On Windows `flutter` is a .bat file, which needs a shell to start.
        runInShell: Platform.isWindows,
      );
    } on ProcessException {
      // Usually the program isn't installed or isn't on the PATH. Show a
      // clear message instead of a stack trace.
      throw FlavorPilotException(
        '"$executable" was not found. Make sure it is installed and on your '
        'PATH (run `$executable --version` to check).',
      );
    }
    return process.exitCode;
  }
}
