import '../models/flavor.dart';

/// The Flutter build modes: `--debug`, `--profile` or `--release`.
enum BuildMode { debug, profile, release }

/// Builds the argument list passed to the `flutter` executable.
///
/// This is a pure function (no files, no processes), which makes it easy to
/// test. For example:
///
/// ```dart
/// flutterArgs(
///   command: ['build', 'apk'],
///   flavor: production,
///   mode: BuildMode.release,
/// );
/// // => ['build', 'apk', '--flavor', 'production', '--release']
/// ```
///
/// - [command] is the Flutter sub-command, e.g. `['run']` or
///   `['build', 'apk']`.
/// - [entryPoint] adds `-t <file>` when the project has one main file per
///   flavor.
/// - The flavor's `env_file`, if any, is added with `--dart-define-from-file`.
/// - [extra] is passed through untouched, so users can still use any Flutter
///   flag that flavorpilot doesn't know about.
List<String> flutterArgs({
  required List<String> command,
  required Flavor flavor,
  required BuildMode mode,
  String? entryPoint,
  List<String> extra = const [],
}) {
  return [
    ...command,
    '--flavor',
    flavor.name,
    '--${mode.name}',
    if (entryPoint != null) ...['-t', entryPoint],
    ?dartDefineFromFile(flavor),
    ...extra,
  ];
}

/// The Flutter flag that loads [flavor]'s `.env` file, e.g.
/// `--dart-define-from-file=.env.development`, or null when it has none.
///
/// Shared with the IDE run configurations, so the IDE and the terminal load
/// the same values.
String? dartDefineFromFile(Flavor flavor) => switch (flavor.envFile) {
  final envFile? => '--dart-define-from-file=$envFile',
  null => null,
};
