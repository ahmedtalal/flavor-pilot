import 'package:flavorpilot/flavorpilot.dart';
import 'package:test/test.dart';

void main() {
  const flavor = Flavor(name: 'development');

  test('builds a simple run command', () {
    expect(
      flutterArgs(command: ['run'], flavor: flavor, mode: BuildMode.debug),
      ['run', '--flavor', 'development', '--debug'],
    );
  });

  test('adds the entry point, then extra flags in order', () {
    expect(
      flutterArgs(
        command: ['build', 'apk'],
        flavor: flavor,
        mode: BuildMode.release,
        entryPoint: 'lib/main_development.dart',
        extra: ['--split-per-abi', '--obfuscate'],
      ),
      [
        'build',
        'apk',
        '--flavor',
        'development',
        '--release',
        '-t',
        'lib/main_development.dart',
        '--split-per-abi',
        '--obfuscate',
      ],
    );
  });
}
