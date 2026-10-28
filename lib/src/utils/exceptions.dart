/// An expected error caused by the user's input or project state, such as a
/// missing config file or an unknown flavor.
///
/// The runner catches it and prints [message] without a stack trace, because
/// it's not a bug in flavorpilot itself.
class FlavorPilotException implements Exception {
  const FlavorPilotException(this.message);

  /// A human-readable explanation of what went wrong and how to fix it.
  final String message;

  @override
  String toString() => message;
}
