import 'dart:io';

/// Asks the user questions in the terminal.
///
/// Every question has a default answer shown in brackets, so pressing Enter
/// accepts it. When [useDefaults] is true (the `--yes` flag), no question is
/// shown and the default is used right away; this is handy for scripts and
/// tests.
class Prompter {
  Prompter({this.useDefaults = false, String? Function()? readLine})
    : _readLine = readLine ?? stdin.readLineSync,
      _readsKeyboard = readLine == null;

  /// Skip all questions and use the default answers.
  final bool useDefaults;

  /// Reads one line typed by the user. Replaceable for tests.
  final String? Function() _readLine;

  /// Whether answers come from the real terminal, so typing can be hidden.
  final bool _readsKeyboard;

  /// Asks [question] and returns the typed answer, or [defaultValue] when the
  /// user just presses Enter.
  String ask(String question, {required String defaultValue}) {
    if (useDefaults) return defaultValue;

    stdout.write('$question [$defaultValue]: ');
    final answer = _readLine()?.trim() ?? '';
    return answer.isEmpty ? defaultValue : answer;
  }

  /// Asks for a secret, like a password, without showing what is typed.
  /// There is no default: an empty answer returns an empty string.
  String askSecret(String question) {
    stdout.write('$question: ');
    final hidden = _readsKeyboard && stdin.hasTerminal && _setEcho(false);
    try {
      return _readLine()?.trim() ?? '';
    } finally {
      if (hidden) {
        _setEcho(true);
        stdout.writeln();
      }
    }
  }

  /// Turns showing typed characters on or off. Returns false when the
  /// terminal doesn't support it; the answer is then shown as typed.
  bool _setEcho(bool on) {
    try {
      stdin.echoMode = on;
      return true;
    } on StdinException {
      return false;
    }
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
