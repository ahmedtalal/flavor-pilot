/// How the app's Dart entry point is organized.
///
/// The developer picks one of these during `flavorpilot init`.
enum MainMode {
  /// One `lib/main.dart` for all flavors. The app reads the current flavor
  /// at runtime from `appFlavor` (package:flutter/services.dart).
  single,

  /// One file per flavor, e.g. `lib/main_development.dart`. Useful when each
  /// flavor needs different setup code (like a separate Firebase project).
  multiple;

  /// Parses the `main_mode` value from the YAML file.
  ///
  /// Returns null when [value] is not a known mode, so the caller can show a
  /// clear error message.
  static MainMode? tryParse(String value) {
    for (final mode in MainMode.values) {
      if (mode.name == value) return mode;
    }
    return null;
  }
}
