import 'dart:math';

import '../../models/flavor.dart';
import '../../utils/exceptions.dart';

/// Edits the text of Xcode's `project.pbxproj` to add flavors.
///
/// For every flavor it adds three build configurations, named the way
/// Flutter expects: `Debug-<flavor>`, `Release-<flavor>` and
/// `Profile-<flavor>`. Each is a copy of the matching base configuration
/// (Debug, Release, Profile) with:
/// - `PRODUCT_BUNDLE_IDENTIFIER` set to the flavor's iOS bundle id,
/// - `FLAVOR_APP_NAME` set to the flavor's app name (Info.plist reads it),
/// - its own `.xcconfig` file, so CocoaPods can link per configuration,
/// - a `FLAVORPILOT = YES` marker, so the next run can find and replace it.
///
/// This class only changes a string; it never reads or writes files, which
/// keeps it easy to test.
///
/// About the pbxproj format: it's a text file where every object has a
/// 24-character id, written like `97C147061CF9000F007C117D /* Debug */`.
/// Lines are indented with tabs, and the regexes below rely on that exact
/// indentation, which Xcode always writes the same way.
class PbxprojEditor {
  PbxprojEditor(this._text, {Random? random}) : _random = random ?? Random();

  String _text;
  final Random _random;

  /// The edited project file text.
  String get text => _text;

  /// The three build types every Flutter iOS project has.
  static const kinds = ['Debug', 'Release', 'Profile'];

  /// Build setting added to every configuration we create.
  static const marker = 'FLAVORPILOT = YES;';

  /// Folder (relative to `ios/`) holding our per-configuration xcconfig files.
  static const xcconfigDir = 'Flutter/flavorpilot';

  /// The build configuration name Flutter looks for, e.g. `Debug-development`.
  static String configName(String kind, Flavor flavor) =>
      '$kind-${flavor.name}';

  /// One `XCBuildConfiguration` object, from its id line to its closing `};`.
  ///
  /// The header uses `[^\n]*?` (not `.*?`) on purpose: with `dotAll` a `.`
  /// also matches newlines, and the match could start at an earlier object.
  static final _configEntry = RegExp(
    r'^\t\t(\w+) /\* [^\n]*? \*/ = \{\n\t\t\tisa = XCBuildConfiguration;\n.*?\n\t\t\};\n',
    multiLine: true,
    dotAll: true,
  );

  /// One `XCConfigurationList`: the list of configurations a target (or the
  /// project) has. Groups: 1 = owner type, 2 = owner name, 3 = child lines.
  static final _configList = RegExp(
    r'^\t\t\w+ /\* Build configuration list for (\w+) "([^"]+)" \*/ = \{\n'
    r'\t\t\tisa = XCConfigurationList;\n'
    r'\t\t\tbuildConfigurations = \(\n'
    r'(.*?)\t\t\t\);',
    multiLine: true,
    dotAll: true,
  );

  /// One child line inside a list: `<id> /* <name> */,`.
  static final _childLine = RegExp(
    r'^\t\t\t\t(\w+) /\* (.+?) \*/,$',
    multiLine: true,
  );

  /// The `name = ...;` line of a configuration (the value may be quoted).
  static final _nameLine = RegExp(
    r'^\t\t\tname = "?([^";]+)"?;$',
    multiLine: true,
  );

  /// A file reference we created earlier (its path is inside [xcconfigDir]).
  static final _ourFileRef = RegExp(
    '^\\t\\t(\\w+) /\\* [^\\n]*? \\*/ = \\{isa = PBXFileReference;'
    '[^\\n]*path = "?$xcconfigDir/[^\\n]*\\n',
    multiLine: true,
  );

  /// The start of the `Flutter` group's children list, where our xcconfig
  /// files are listed so they show up in Xcode next to Debug.xcconfig.
  static final _flutterGroupChildren = RegExp(
    r'/\* Flutter \*/ = \{\n\t\t\tisa = PBXGroup;\n\t\t\tchildren = \(\n',
  );

  /// Removes everything a previous run added, so the next run starts clean.
  void removeGenerated() {
    final removedIds = <String>[];

    // 1. Configurations carrying our marker.
    _text = _text.replaceAllMapped(_configEntry, (match) {
      if (!match[0]!.contains(marker)) return match[0]!;
      removedIds.add(match[1]!);
      return '';
    });

    // 2. File references to our xcconfig files.
    _text = _text.replaceAllMapped(_ourFileRef, (match) {
      removedIds.add(match[1]!);
      return '';
    });

    // 3. The lines pointing to those objects in lists and groups.
    for (final id in removedIds) {
      _text = _text.replaceAll(
        RegExp('^\\t\\t\\t\\t$id /\\* .*? \\*/,\\n', multiLine: true),
        '',
      );
    }
  }

  /// Throws if the project already has flavor configurations that weren't
  /// made by flavorpilot, so we never overwrite someone's manual setup.
  ///
  /// Call after [removeGenerated], so our own old configurations don't count.
  void checkNoConflicts(List<Flavor> flavors) {
    final wanted = {
      for (final flavor in flavors)
        for (final kind in kinds) configName(kind, flavor),
    };
    for (final match in _configEntry.allMatches(_text)) {
      final name = _nameLine.firstMatch(match[0]!)?[1];
      if (wanted.contains(name)) {
        throw FlavorPilotException(
          'ios/Runner.xcodeproj already has a "$name" build configuration '
          'that was not created by flavorpilot. Remove it in Xcode first, '
          'then run this command again.',
        );
      }
    }
  }

  /// Adds the build configurations for [flavors] to every configuration
  /// list (the project, the Runner app, and other targets like RunnerTests).
  ///
  /// [defaultAppName] is written as `FLAVOR_APP_NAME` into the original
  /// Runner configurations (plain Debug/Release/Profile), so building
  /// without a flavor still shows a name.
  void addFlavors(List<Flavor> flavors, {required String defaultAppName}) {
    // Look up every existing configuration by id.
    final entries = {
      for (final match in _configEntry.allMatches(_text)) match[1]!: match[0]!,
    };

    final newEntries = StringBuffer();
    final newFileRefs = StringBuffer();
    final newGroupChildren = StringBuffer();
    final runnerBaseIds = <String>{};

    _text = _text.replaceAllMapped(_configList, (list) {
      // Only the Runner app target gets bundle ids, app names and xcconfigs.
      final isApp = list[1] == 'PBXNativeTarget' && list[2] == 'Runner';
      final children = StringBuffer();

      for (final child in _childLine.allMatches(list[3]!)) {
        final baseId = child[1]!;
        final kind = child[2]!;
        final base = entries[baseId];
        if (base == null || !kinds.contains(kind)) continue;
        if (isApp) runnerBaseIds.add(baseId);

        for (final flavor in flavors) {
          final name = configName(kind, flavor);
          final id = _newId();
          String? fileRefId;
          if (isApp) {
            fileRefId = _newId();
            newFileRefs.writeln(_fileRefLine(fileRefId, name));
            newGroupChildren.writeln(
              '\t\t\t\t$fileRefId /* $name.xcconfig */,',
            );
          }
          newEntries.write(
            _flavorEntry(base, id, name, flavor, fileRefId: fileRefId),
          );
          children.writeln('\t\t\t\t$id /* $name */,');
        }
      }
      // Append the new children at the end of this list.
      return list[0]!.replaceFirst(RegExp(r'\t\t\t\);$'), '$children\t\t\t);');
    });

    _insertBefore('/* End XCBuildConfiguration section */', '$newEntries');
    _insertBefore('/* End PBXFileReference section */', '$newFileRefs');
    _addToFlutterGroup('$newGroupChildren');
    _addDefaultAppName(runnerBaseIds, defaultAppName);
  }

  /// Builds a new configuration from [base] for [flavor].
  String _flavorEntry(
    String base,
    String id,
    String name,
    Flavor flavor, {
    String? fileRefId,
  }) {
    final isApp = fileRefId != null;
    var entry = base
        // The base may already have the default app name (added on an
        // earlier run). Drop it so the flavor's name below is the only one.
        .replaceAll(
          RegExp(r'^\t\t\t\tFLAVOR_APP_NAME = .*;\n', multiLine: true),
          '',
        )
        // New id and name in the header line.
        .replaceFirst(RegExp(r'^\t\t\w+ /\* .*? \*/'), '\t\t$id /* $name */')
        .replaceFirst(_nameLine, '\t\t\tname = "$name";')
        // Our marker (and the app name for the app target) go first.
        .replaceFirst(
          '\t\t\tbuildSettings = {\n',
          '\t\t\tbuildSettings = {\n'
              '\t\t\t\t$marker\n'
              '${isApp ? '\t\t\t\tFLAVOR_APP_NAME = ${_quote(flavor.appName ?? flavor.name)};\n' : ''}',
        );

    if (!isApp) return entry;

    if (flavor.iosBundleId != null) {
      entry = entry.replaceFirst(
        RegExp(r'^\t\t\t\tPRODUCT_BUNDLE_IDENTIFIER = .*;$', multiLine: true),
        '\t\t\t\tPRODUCT_BUNDLE_IDENTIFIER = ${_quote(flavor.iosBundleId!)};',
      );
    }
    // Swap Flutter's Debug/Release.xcconfig for this configuration's own file.
    return entry.replaceFirst(
      RegExp(
        r'baseConfigurationReference = \w+ /\* (Debug|Release)\.xcconfig \*/;',
      ),
      'baseConfigurationReference = $fileRefId /* $name.xcconfig */;',
    );
  }

  /// A file reference line for `ios/Flutter/flavorpilot/<name>.xcconfig`.
  String _fileRefLine(String id, String name) =>
      '\t\t$id /* $name.xcconfig */ = {isa = PBXFileReference; '
      'lastKnownFileType = text.xcconfig; name = "$name.xcconfig"; '
      'path = "$xcconfigDir/$name.xcconfig"; sourceTree = "<group>"; };';

  /// Adds `FLAVOR_APP_NAME` to the original Runner configurations that don't
  /// have it yet.
  void _addDefaultAppName(Set<String> ids, String appName) {
    _text = _text.replaceAllMapped(_configEntry, (match) {
      final entry = match[0]!;
      if (!ids.contains(match[1]) || entry.contains('FLAVOR_APP_NAME')) {
        return entry;
      }
      return entry.replaceFirst(
        '\t\t\tbuildSettings = {\n',
        '\t\t\tbuildSettings = {\n'
            '\t\t\t\tFLAVOR_APP_NAME = ${_quote(appName)};\n',
      );
    });
  }

  /// Lists our xcconfig files inside Xcode's `Flutter` group.
  void _addToFlutterGroup(String children) {
    final match = _flutterGroupChildren.firstMatch(_text);
    if (match == null) {
      throw const FlavorPilotException(
        'Could not find the "Flutter" group in ios/Runner.xcodeproj. '
        'Is this a standard Flutter iOS project?',
      );
    }
    _text = _text.replaceRange(match.end, match.end, children);
  }

  /// Inserts [content] right before the section end comment [anchor].
  void _insertBefore(String anchor, String content) {
    final index = _text.indexOf(anchor);
    if (index == -1) {
      throw FlavorPilotException(
        'ios/Runner.xcodeproj is missing "$anchor". The file may be damaged.',
      );
    }
    _text = _text.replaceRange(index, index, content);
  }

  /// A new random 24-character id that doesn't exist in the file yet.
  String _newId() {
    const hex = '0123456789ABCDEF';
    while (true) {
      final id = List.generate(24, (_) => hex[_random.nextInt(16)]).join();
      if (!_text.contains(id)) return id;
    }
  }

  /// Quotes a pbxproj string value, escaping `\` and `"`.
  String _quote(String value) =>
      '"${value.replaceAll(r'\', r'\\').replaceAll('"', r'\"')}"';
}
