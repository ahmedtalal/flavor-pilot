import 'dart:io';

import 'package:flavorpilot/flavorpilot.dart';
import 'package:flavorpilot/src/utils/logger.dart';
import 'package:flavorpilot/src/utils/process_runner.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// Untouched files from a fresh `flutter create` project (Android + iOS).
const fixtureDir = 'test/fixtures/flutter_app';

/// A minimal pubspec, written by [createTempProject]. (The fixture folder
/// has no pubspec.yaml, so Dart doesn't treat it as a separate package.)
const fixturePubspec = 'name: sample\nversion: 1.0.0+1\n';

/// Copies the fixture Flutter project into a new temporary folder and
/// returns its path. The folder is deleted when the test ends.
String createTempProject() {
  final dir = Directory.systemTemp.createTempSync('flavorpilot_test_');
  addTearDown(() => dir.deleteSync(recursive: true));

  for (final entity in Directory(fixtureDir).listSync(recursive: true)) {
    if (entity is! File) continue;
    final target = p.join(dir.path, p.relative(entity.path, from: fixtureDir));
    File(target).parent.createSync(recursive: true);
    entity.copySync(target);
  }
  File(p.join(dir.path, 'pubspec.yaml')).writeAsStringSync(fixturePubspec);
  return dir.path;
}

/// Creates an empty temporary folder, deleted when the test ends.
String createEmptyDir() {
  final dir = Directory.systemTemp.createTempSync('flavorpilot_test_');
  addTearDown(() => dir.deleteSync(recursive: true));
  return dir.path;
}

/// Reads a file inside [projectDir].
String readFile(String projectDir, String path) =>
    File(p.join(projectDir, path)).readAsStringSync();

/// Writes a file inside [projectDir], creating folders as needed.
void writeFile(String projectDir, String path, String content) {
  File(p.join(projectDir, path))
    ..parent.createSync(recursive: true)
    ..writeAsStringSync(content);
}

/// Every file in [dir] with its content, used to prove nothing changed.
Map<String, String> snapshot(String dir) => {
  for (final file in Directory(dir).listSync(recursive: true).whereType<File>())
    p.relative(file.path, from: dir): file.readAsStringSync(),
};

/// A [ProcessRunner] that records commands instead of running them.
class FakeProcessRunner extends ProcessRunner {
  FakeProcessRunner({this.exitCode = 0, this.onRun})
    : super(Logger(useColors: false));

  /// Exit code every "run" returns.
  final int exitCode;

  /// Called with Flutter's arguments, e.g. to create a fake build output.
  final void Function(List<String> arguments)? onRun;

  /// Every command, as `[executable, ...arguments]`.
  final calls = <List<String>>[];

  @override
  Future<int> run(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
  }) async {
    calls.add([executable, ...arguments]);
    onRun?.call(arguments);
    return exitCode;
  }
}

/// Runs flavorpilot with [args] inside [projectDir] and returns the exit code.
Future<int> runFlavorPilot(
  String projectDir,
  List<String> args, {
  FakeProcessRunner? processRunner,
}) {
  return FlavorPilotRunner(
    logger: Logger(useColors: false),
    processRunner: processRunner ?? FakeProcessRunner(),
    projectDir: projectDir,
  ).run(args);
}
