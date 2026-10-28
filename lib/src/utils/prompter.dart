import 'dart:io';

/// Asks the user questions in the terminal.
///
/// Every question has a default answer shown in brackets, so pressing Enter
/// accepts it. When [useDefaults] is true (the `--yes` flag), no question is
/// shown and the default is used right away; this is handy for scripts and
/// tests.
class Prompter {
  Prompter({this.useDefaults = false, String? Function()? readLine})
    : _readLine = readLine ?? stdin.readLineSync;

  /// Skip all questions and use the default answers.
  final bool useDefaults;

  /// Reads one line typed by the user. Replaceable for tests.
  final String? Function() _readLine;

  /// Asks [question] and returns the typed answer, or [defaultValue] when the
  /// user just presses Enter.
  String ask(String question, {required String defaultValue}) {
    if (useDefaults) return defaultValue;

    stdout.write('$question [$defaultValue]: ');
    final answer = _readLine()?.trim() ?? '';
    return answer.isEmpty ? defaultValue : answer;
  }

  /// Asks a yes/no [question]. Accepts y/yes/n/no in any letter case.
  bool confirm(String question, {required bool defaultValue}) {
    if (useDefaults) return defaultValue;

    final hint = defaultValue ? 'Y/n' : 'y/N';
    stdout.write('$question ($hint): ');
    final answer = _readLine()?.trim().toLowerCase() ?? '';
    if (answer.isEmpty) return defaultValue;
    return answer == 'y' || answer == 'yes';
  }
}
