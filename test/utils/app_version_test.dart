import 'package:flavorpilot/flavorpilot.dart';
import 'package:test/test.dart';

void main() {
  group('AppVersion.parse', () {
    test('reads a version with a build number', () {
      expect(AppVersion.parse('1.2.3+4').toString(), '1.2.3+4');
    });

    test('treats a missing build number as 0', () {
      expect(AppVersion.parse('1.2.3').build, 0);
    });

    test('rejects versions it cannot bump safely', () {
      for (final bad in ['1.2', '1.2.3-beta', 'v1.2.3', '']) {
        expect(
          () => AppVersion.parse(bad),
          throwsA(isA<FlavorPilotException>()),
          reason: bad,
        );
      }
    });
  });

  group('AppVersion.bump', () {
    final version = AppVersion.parse('1.2.3+4');

    test('every bump except none increases the build number', () {
      expect(version.bump(VersionBump.build).toString(), '1.2.3+5');
      expect(version.bump(VersionBump.patch).toString(), '1.2.4+5');
      expect(version.bump(VersionBump.minor).toString(), '1.3.0+5');
      expect(version.bump(VersionBump.major).toString(), '2.0.0+5');
      expect(version.bump(VersionBump.none).toString(), '1.2.3+4');
    });
  });
}
