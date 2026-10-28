import 'dart:io';

/// Prints colored messages to the terminal.
///
/// Colors are turned off automatically when the terminal doesn't support
/// them (for example when output is piped to a file).
class Logger {
  Logger({bool? useColors})
    : _useColors = useColors ?? stdout.supportsAnsiEscapes;

  final bool _useColors;

  // ANSI escape codes for terminal colors.
  static const _reset = '\x1B[0m';
  static const _red = '\x1B[31m';
  static const _green = '\x1B[32m';
  static const _yellow = '\x1B[33m';
  static const _cyan = '\x1B[36m';

  /// A normal message.
  void info(String message) => stdout.writeln(message);

  /// A message about a step that finished successfully.
  void success(String message) => stdout.writeln(_color('✓ $message', _green));

  /// A message about something that may need attention but isn't fatal.
  void warn(String message) => stdout.writeln(_color('! $message', _yellow));

  /// A message about a failure. Written to stderr.
  void error(String message) => stderr.writeln(_color('✗ $message', _red));

  /// Shows the exact command flavorpilot is about to run, so the user can
  /// see (and copy) what's happening behind the scenes.
  void command(String message) => stdout.writeln(_color('\$ $message', _cyan));

  /// Wraps [text] in [color] only when colors are enabled.
  String _color(String text, String color) =>
      _useColors ? '$color$text$_reset' : text;
}
