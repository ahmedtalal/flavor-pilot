import 'dart:io';
import 'dart:math';

import 'package:flavorpilot/flavorpilot.dart';
import 'package:flavorpilot/src/generators/ios/pbxproj_editor.dart';
import 'package:test/test.dart';

import '../helpers.dart';

void main() {
  final original = File(
    '$fixtureDir/ios/Runner.xcodeproj/project.pbxproj',
  ).readAsStringSync();

  const flavors = [
    Flavor(
      name: 'development',
      appName: 'Sample DEV',
      iosBundleId: 'com.example.sample.dev',
    ),
    Flavor(
      name: 'production',
      appName: 'Sample',
      iosBundleId: 'com.example.sample',
    ),
  ];

  /// Runs a full generation on [text], like `init` and `sync` do.
  String generate(String text, {int seed = 1}) {
    return (PbxprojEditor(text, random: Random(seed))
          ..removeGenerated()
          ..checkNoConflicts(flavors)
          ..addFlavors(flavors, defaultAppName: 'Sample'))
        .text;
  }

  /// Number of times [pattern] appears in [text].
  int count(String text, String pattern) => pattern.allMatches(text).length;

  /// Replaces Xcode ids, which are random for every new object.
  String maskIds(String text) =>
      text.replaceAll(RegExp(r'\b[0-9A-F]{24}\b'), 'ID');

  /// Every XCBuildConfiguration block in [text].
  Iterable<String> configEntries(String text) => RegExp(
    r'^\t\t\w+ /\* [^\n]*? \*/ = \{\n\t\t\tisa = XCBuildConfiguration;\n.*?\n\t\t\};',
    multiLine: true,
    dotAll: true,
  ).allMatches(text).map((m) => m[0]!);

  test('adds Debug, Release and Profile for each flavor to every list', () {
    final text = generate(original);

    // 3 lists (project, Runner, RunnerTests) × 2 flavors × 3 kinds = 18.
    expect(count(text, PbxprojEditor.marker), 18);
    for (final kind in PbxprojEditor.kinds) {
      for (final flavor in flavors) {
        final name = PbxprojEditor.configName(kind, flavor);
        // One configuration object and one list entry per list.
        expect(count(text, 'name = "$name";'), 3, reason: name);
        expect(count(text, '/* $name */,'), 3, reason: name);
      }
    }
  });

  test('includes Profile configurations at project level', () {
    // Regression: a regex used to swallow the project's Profile config, so
    // `xcodebuild -list` showed no Profile-* configurations.
    final text = generate(original);
    final projectList = RegExp(
      r'Build configuration list for PBXProject "Runner" \*/ = \{.*?\);',
      dotAll: true,
    ).firstMatch(text)![0]!;

    expect(projectList, contains('/* Profile-development */'));
    expect(projectList, contains('/* Profile-production */'));
  });

  test('sets bundle ids only on the Runner app target', () {
    final text = generate(original);

    // 3 Runner configs (Debug/Release/Profile) per flavor.
    expect(
      count(text, 'PRODUCT_BUNDLE_IDENTIFIER = "com.example.sample.dev";'),
      3,
    );
    // RunnerTests keeps its own id: 3 originals + 3 copies per flavor.
    expect(
      count(
        text,
        'PRODUCT_BUNDLE_IDENTIFIER = com.example.sample.RunnerTests;',
      ),
      9,
    );
  });

  test('gives each Runner configuration its own xcconfig file', () {
    final text = generate(original);

    for (final kind in PbxprojEditor.kinds) {
      final name = PbxprojEditor.configName(kind, flavors.first);
      expect(
        count(text, 'path = "Flutter/flavorpilot/$name.xcconfig";'),
        1,
        reason: name,
      );
      expect(
        RegExp(
          'baseConfigurationReference = \\w+ /\\* $name\\.xcconfig \\*/;',
        ).allMatches(text).length,
        1,
        reason: name,
      );
    }
  });

  test('points only the flavor with an icon to its own icon set', () {
    const withIcon = [
      Flavor(name: 'development', icon: 'assets/dev.png'),
      Flavor(name: 'production'),
    ];
    final text = (PbxprojEditor(
      original,
      random: Random(1),
    )..addFlavors(withIcon, defaultAppName: 'Sample')).text;

    // Debug, Release and Profile of the Runner target only.
    expect(
      count(
        text,
        'ASSETCATALOG_COMPILER_APPICON_NAME = "AppIcon-development";',
      ),
      3,
    );
    expect(text, isNot(contains('AppIcon-production')));
    for (final entry in configEntries(text)) {
      expect(
        count(entry, 'ASSETCATALOG_COMPILER_APPICON_NAME'),
        lessThanOrEqualTo(1),
        reason: entry,
      );
    }
  });

  test('every configuration has at most one FLAVOR_APP_NAME', () {
    // Regression: re-running copied the base's app name into flavor configs.
    final text = generate(generate(original, seed: 1), seed: 2);

    for (final entry in configEntries(text)) {
      expect(
        count(entry, 'FLAVOR_APP_NAME'),
        lessThanOrEqualTo(1),
        reason: entry,
      );
    }
    expect(count(text, 'FLAVOR_APP_NAME = "Sample DEV";'), 3);
  });

  test('running again gives the same project (apart from new ids)', () {
    final once = generate(original, seed: 1);
    final twice = generate(once, seed: 2);

    expect(maskIds(twice), maskIds(once));
  });

  test('removeGenerated removes every object it added', () {
    final cleaned = (PbxprojEditor(generate(original))..removeGenerated()).text;

    expect(cleaned, isNot(contains(PbxprojEditor.marker)));
    expect(cleaned, isNot(contains(PbxprojEditor.xcconfigDir)));
    expect(cleaned, isNot(contains('-development')));
  });

  test('refuses to touch hand-made flavor configurations', () {
    // Removing our marker makes the configurations look hand-made.
    final handMade = generate(
      original,
    ).replaceAll('\t\t\t\t${PbxprojEditor.marker}\n', '');

    final editor = PbxprojEditor(handMade)..removeGenerated();
    expect(
      () => editor.checkNoConflicts(flavors),
      throwsA(isA<FlavorPilotException>()),
    );
  });
}
