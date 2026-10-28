import 'dart:io';

import 'package:flavorpilot/flavorpilot.dart';

/// Entry point of the `flavorpilot` terminal command.
///
/// All the work happens in [FlavorPilotRunner]; this file only passes the
/// terminal arguments in and reports the exit code back to the shell.
Future<void> main(List<String> arguments) async {
  exitCode = await FlavorPilotRunner().run(arguments);
}
