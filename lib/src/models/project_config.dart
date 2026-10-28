import 'flavor.dart';
import 'main_mode.dart';

/// Everything flavorpilot knows about a project, loaded from
/// `flavorpilot.yaml`.
class ProjectConfig {
  const ProjectConfig({required this.flavors, this.mainMode = MainMode.single});

  /// All flavors defined in the project, in the order they appear in the file.
  final List<Flavor> flavors;

  /// Whether the project uses one `main.dart` or one main file per flavor.
  final MainMode mainMode;

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
