import 'exceptions.dart';

/// Which part of the version `flavorpilot release` increases.
enum VersionBump {
  /// Only the build number: 1.2.3+4 → 1.2.3+5.
  build,

  /// Bug-fix release: 1.2.3+4 → 1.2.4+5.
  patch,

  /// New features: 1.2.3+4 → 1.3.0+5.
  minor,

  /// Breaking changes: 1.2.3+4 → 2.0.0+5.
  major,

  /// Keep the version as it is.
  none,
}

/// A Flutter app version like `1.2.3+4`, from pubspec.yaml's `version:`.
///
/// The part before `+` is the version users see (major.minor.patch); the
/// number after `+` is the build number the app stores require to grow with
/// every upload.
class AppVersion {
  const AppVersion(this.major, this.minor, this.patch, this.build);

  final int major;
  final int minor;
  final int patch;

  /// Build number; 0 when the version has no `+` part.
  final int build;

  static final _pattern = RegExp(r'^(\d+)\.(\d+)\.(\d+)(?:\+(\d+))?$');

  /// Parses a version like `1.2.3` or `1.2.3+4`.
  factory AppVersion.parse(String text) {
    final match = _pattern.firstMatch(text.trim());
    if (match == null) {
      throw FlavorPilotException(
        'Unsupported version "$text" in pubspec.yaml. Expected a version '
        'like 1.2.3+4.',
      );
    }
    return AppVersion(
      int.parse(match[1]!),
      int.parse(match[2]!),
      int.parse(match[3]!),
      int.parse(match[4] ?? '0'),
    );
  }

  /// Returns the next version for [bump].
  ///
  /// Every bump except [VersionBump.none] also increases the build number,
  /// because stores reject an upload that reuses one.
  AppVersion bump(VersionBump bump) => switch (bump) {
    VersionBump.none => this,
    VersionBump.build => AppVersion(major, minor, patch, build + 1),
    VersionBump.patch => AppVersion(major, minor, patch + 1, build + 1),
    VersionBump.minor => AppVersion(major, minor + 1, 0, build + 1),
    VersionBump.major => AppVersion(major + 1, 0, 0, build + 1),
  };

  @override
  String toString() => '$major.$minor.$patch+$build';
}
