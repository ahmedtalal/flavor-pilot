import 'package:flavorpilot/src/utils/exceptions.dart';
import 'package:flavorpilot/src/utils/logger.dart';
import 'package:flavorpilot/src/utils/process_runner.dart';
import 'package:test/test.dart';

void main() {
  test('a missing program gives a clear error, not a crash', () {
    final runner = ProcessRunner(Logger(useColors: false));

    expect(
      runner.run('flavorpilot-no-such-program', ['--version']),
      throwsA(
        isA<FlavorPilotException>().having(
          (e) => e.message,
          'message',
          contains('"flavorpilot-no-such-program" was not found'),
        ),
      ),
    );
  });
}
