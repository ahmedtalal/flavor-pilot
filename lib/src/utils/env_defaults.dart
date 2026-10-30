import '../models/flavor.dart';

/// Example values that `init` and `env` add to every flavor, so the app has
/// working settings right away. The developer replaces them later.
const _placeholderHost = 'example.com';

/// Returns the example env settings for [flavor].
///
/// `production` gets the plain URL and logs turned off. Other flavors get
/// their alias in the URL and logs turned on.
Map<String, Object> defaultEnv(Flavor flavor) {
  final isProduction = flavor.name == 'production';
  final prefix = (flavor.alias ?? flavor.name).toLowerCase();
  return {
    'base_url': isProduction
        ? 'https://api.$_placeholderHost'
        : 'https://$prefix.api.$_placeholderHost',
    'enable_logs': !isProduction,
  };
}

/// Returns a copy of [flavor] with any missing example settings added.
/// Values the flavor already has are never changed.
Flavor withDefaultEnv(Flavor flavor) {
  return flavor.copyWithEnv({...defaultEnv(flavor), ...flavor.env});
}

/// Lists the settings in [flavors] that still hold an example value, like
/// `development: base_url`.
List<String> placeholderEnv(Iterable<Flavor> flavors) {
  return [
    for (final flavor in flavors)
      for (final MapEntry(:key, :value) in flavor.env.entries)
        if (value is String && value.contains(_placeholderHost))
          '${flavor.name}: $key',
  ];
}
