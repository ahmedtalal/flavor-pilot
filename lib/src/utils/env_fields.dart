/// Helpers that turn `env` values from `flavorpilot.yaml` into Dart fields on
/// the generated `AppFlavor` enum.
library;

/// The Dart field name for an env key: `base_url` becomes `baseUrl`.
String envFieldName(String key) {
  final parts = key.split('_');
  return parts.first +
      parts.skip(1).map((w) => w[0].toUpperCase() + w.substring(1)).join();
}

/// The Dart type of a field holding [values], one value per flavor.
///
/// Returns null when the values can't share one type, for example a text in
/// one flavor and a number in another. A mix of whole and decimal numbers is
/// allowed and becomes `double`.
String? envDartType(Iterable<Object> values) {
  if (values.every((v) => v is String)) return 'String';
  if (values.every((v) => v is bool)) return 'bool';
  if (values.every((v) => v is int)) return 'int';
  if (values.every((v) => v is num)) return 'double';
  return null;
}
