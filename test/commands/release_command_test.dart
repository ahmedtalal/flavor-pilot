import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../helpers.dart';

void main() {
  const yaml = 'flavors:\n  production: {alias: prod}\n';

  /// A project with a pubspec and flavorpilot.yaml.
  String createProject() {
    final dir = createEmptyDir();
    writeFile(dir, 'pubspec.yaml', fixturePubspec);
    writeFile(dir, 'flavorpilot.yaml', yaml);
    return dir;
  }

  /// A fake Flutter that "builds" by creating the file Flutter would.
  FakeProcessRunner fakeBuild(String dir, String output) =>
      FakeProcessRunner(onRun: (_) => writeFile(dir, output, 'binary'));

  test('bumps the version, builds, and copies a clearly named APK', () async {
    final dir = createProject();
    final fake = fakeBuild(
      dir,
      'build/app/outputs/flutter-apk/app-production-release.apk',
    );

    final code = await runFlavorPilot(dir, [
      'release',
      'prod',
      '--bump',
      'patch',
    ], processRunner: fake);

    expect(code, 0);
    expect(readFile(dir, 'pubspec.yaml'), contains('version: 1.0.1+2'));
    expect(
      fake.calls.single,
      containsAllInOrder(['build', 'apk', '--release']),
    );
    expect(
      File(p.join(dir, 'dist/sample-production-1.0.1+2.apk')).existsSync(),
      isTrue,
    );
  });

  test('finds an app bundle in its flavor folder', () async {
    final dir = createProject();
    final fake = fakeBuild(
      dir,
      'build/app/outputs/bundle/productionRelease/app-production-release.aab',
    );

    await runFlavorPilot(dir, [
      'release',
      'prod',
      '--target',
      'appbundle',
      '--out',
      'out',
    ], processRunner: fake);

    // Default bump is the build number only.
    expect(
      File(p.join(dir, 'out/sample-production-1.0.0+2.aab')).existsSync(),
      isTrue,
    );
  });

  test('undoes the version change when the build fails', () async {
    final dir = createProject();

    final code = await runFlavorPilot(dir, [
      'release',
      'prod',
      '--bump',
      'major',
    ], processRunner: FakeProcessRunner(exitCode: 1));

    expect(code, 1);
    expect(readFile(dir, 'pubspec.yaml'), fixturePubspec);
    expect(Directory(p.join(dir, 'dist')).existsSync(), isFalse);
  });

  test('--bump none keeps pubspec.yaml untouched', () async {
    final dir = createProject();
    final fake = fakeBuild(
      dir,
      'build/app/outputs/flutter-apk/app-production-release.apk',
    );

    await runFlavorPilot(dir, [
      'release',
      'prod',
      '--bump',
      'none',
    ], processRunner: fake);

    expect(readFile(dir, 'pubspec.yaml'), fixturePubspec);
    expect(
      File(p.join(dir, 'dist/sample-production-1.0.0+1.apk')).existsSync(),
      isTrue,
    );
  });
}
