/// One flavor (environment) of the app, for example `development` or
/// `production`.
///
/// Flavors are read from the `flavors:` section of `flavorpilot.yaml`.
class Flavor {
  const Flavor({
    required this.name,
    this.alias,
    this.appName,
    this.androidId,
    this.iosBundleId,
    this.icon,
    this.env = const {},
  });

  /// The exact name passed to Flutter's `--flavor` flag, e.g. `development`.
  final String name;

  /// Optional short name typed in the terminal, e.g. `dev`.
  ///
  /// Lets the user write `flavorpilot run dev` instead of
  /// `flavorpilot run development`.
  final String? alias;

  /// App name shown on the device home screen for this flavor.
  final String? appName;

  /// Android `applicationId` for this flavor, e.g. `com.example.app.dev`.
  final String? androidId;

  /// iOS bundle identifier for this flavor, e.g. `com.example.app.dev`.
  final String? iosBundleId;

  /// Path of this flavor's app icon (a PNG), relative to the project root.
  /// When null, the flavor keeps the project's current icon.
  final String? icon;

  /// Custom settings for this flavor, like `base_url`, available in the app
  /// as fields on `AppFlavor`. Values are a String, bool, int or double.
  final Map<String, Object> env;

  /// Returns true when [input] is this flavor's [name] or [alias].
  bool matches(String input) => input == name || input == alias;

  /// Returns a copy of this flavor with [env] as its settings.
  Flavor copyWithEnv(Map<String, Object> env) {
    return Flavor(
      name: name,
      alias: alias,
      appName: appName,
      androidId: androidId,
      iosBundleId: iosBundleId,
      icon: icon,
      env: env,
    );
  }

  /// Builds a [Flavor] from one entry of the `flavors:` map in the YAML file.
  ///
  /// [name] is the map key and [data] is the map value under it.
  factory Flavor.fromMap(String name, Map<dynamic, dynamic> data) {
    final env = data['env'] as Map<dynamic, dynamic>?;
    return Flavor(
      name: name,
      alias: data['alias'] as String?,
      appName: data['app_name'] as String?,
      androidId: data['android_id'] as String?,
      iosBundleId: data['ios_bundle_id'] as String?,
      icon: data['icon'] as String?,
      env: {
        for (final entry in (env ?? const {}).entries)
          entry.key.toString(): entry.value as Object,
      },
    );
  }

  /// Converts this flavor's text settings back into the YAML map shape.
  ///
  /// Empty fields are skipped so the generated file stays clean. [env] is not
  /// included, because its values aren't all text.
  Map<String, String> toMap() {
    // `'key': ?value` adds the entry only when value is not null.
    return {
      'alias': ?alias,
      'app_name': ?appName,
      'android_id': ?androidId,
      'ios_bundle_id': ?iosBundleId,
      'icon': ?icon,
    };
  }
}
