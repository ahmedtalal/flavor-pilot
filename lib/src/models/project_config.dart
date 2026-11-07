import 'flavor.dart';
import 'main_mode.dart';

/// Everything flavorpilot knows about a project, loaded from
/// `flavorpilot.yaml`.
class ProjectConfig {
  const ProjectConfig({
    required this.flavors,
    this.mainMode = MainMode.single,
    this.androidSigning,
  });

  /// All flavors defined in the project, in the order they appear in the file.
  final List<Flavor> flavors;

  /// Whether the project uses one `main.dart` or one main file per flavor.
  final MainMode mainMode;

  /// Path of the `.properties` file with the Android signing key every
  /// flavor uses, unless it sets its own. See `flavorpilot signing`.
  final String? androidSigning;

  /// Returns a copy of this config with the given fields replaced.
  ProjectConfig copyWith({List<Flavor>? flavors, String? androidSigning}) {
    return ProjectConfig(
      flavors: flavors ?? this.flavors,
      mainMode: mainMode,
      androidSigning: androidSigning ?? this.androidSigning,
    );
  }

  /// The signing key file [flavor] uses: its own, or the project-wide one.
  /// Null when its release builds use the debug key.
  String? signingFor(Flavor flavor) => flavor.androidSigning ?? androidSigning;

  /// Whether any flavor uses an Android signing key from flavorpilot.
  bool get usesSigning => flavors.any((f) => signingFor(f) != null);

  /// Finds the flavor whose name or alias equals [input].
  ///
  /// Returns null when nothing matches.
  Flavor? findFlavor(String input) {
    for (final flavor in flavors) {
      if (flavor.matches(input)) return flavor;
    }
    return null;
  }

  /// The Dart file Flutter should start from for [flavor].
  ///
  /// Returns null in [MainMode.single], because Flutter already uses
  /// `lib/main.dart` by default and no `-t` flag is needed.
  String? entryPointFor(Flavor flavor) {
    return switch (mainMode) {
      MainMode.single => null,
      MainMode.multiple => 'lib/main_${flavor.name}.dart',
    };
  }
}
