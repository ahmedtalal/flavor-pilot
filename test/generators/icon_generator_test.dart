import 'dart:io';

import 'package:flavorpilot/flavorpilot.dart';
import 'package:flavorpilot/src/generators/icon_generator.dart';
import 'package:flavorpilot/src/utils/file_changes.dart';
import 'package:flavorpilot/src/utils/logger.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../helpers.dart';

void main() {
  const androidFlavorDir = 'android/app/src/development';
  const iosSetDir = 'ios/Runner/Assets.xcassets/AppIcon-development.appiconset';
  const iconPath = 'assets/dev.png';

  const withIcon = ProjectConfig(
    flavors: [Flavor(name: 'development', icon: iconPath)],
  );
  const withoutIcon = ProjectConfig(flavors: [Flavor(name: 'development')]);

  /// A fixture project with an asset catalog and a valid source icon.
  String createProject() {
    final dir = createTempProject();
    writeFile(dir, 'ios/Runner/Assets.xcassets/Contents.json', '{}');
    writePng(dir, iconPath);
    return dir;
  }

  /// Runs the generator on [dir] and writes the result.
  void generate(String dir, ProjectConfig config) {
    final changes = FileChanges();
    IconGenerator(
      projectDir: dir,
      logger: Logger(useColors: false),
    ).generate(config, changes);
    changes.apply();
  }

  bool exists(String dir, String path) => File(p.join(dir, path)).existsSync();

  /// Decodes a generated PNG.
  img.Image decode(String dir, String path) =>
      img.decodePng(File(p.join(dir, path)).readAsBytesSync())!;

  test('creates every Android size with the icon name from the manifest', () {
    final dir = createProject();
    generate(dir, withIcon);

    const sizes = {
      'mdpi': 48,
      'hdpi': 72,
      'xhdpi': 96,
      'xxhdpi': 144,
      'xxxhdpi': 192,
    };
    sizes.forEach((density, size) {
      final icon = decode(
        dir,
        '$androidFlavorDir/res/mipmap-$density/ic_launcher.png',
      );
      expect(icon.width, size, reason: density);
      expect(icon.height, size, reason: density);
    });
  });

  test('follows a custom icon name in the manifest', () {
    final dir = createProject();
    const manifest = 'android/app/src/main/AndroidManifest.xml';
    writeFile(
      dir,
      manifest,
      readFile(
        dir,
        manifest,
      ).replaceFirst('@mipmap/ic_launcher', '@mipmap/launcher_icon'),
    );

    generate(dir, withIcon);

    expect(
      exists(dir, '$androidFlavorDir/res/mipmap-mdpi/launcher_icon.png'),
      isTrue,
    );
    expect(
      exists(dir, '$androidFlavorDir/res/mipmap-mdpi/ic_launcher.png'),
      isFalse,
    );
  });

  test('skips Android when the manifest icon is not a mipmap', () {
    final dir = createProject();
    const manifest = 'android/app/src/main/AndroidManifest.xml';
    writeFile(
      dir,
      manifest,
      readFile(
        dir,
        manifest,
      ).replaceFirst('@mipmap/ic_launcher', '@drawable/logo'),
    );

    generate(dir, withIcon);

    expect(Directory(p.join(dir, androidFlavorDir)).existsSync(), isFalse);
    expect(exists(dir, '$iosSetDir/AppIcon.png'), isTrue);
  });

  test('creates the iOS icon set with no transparency', () {
    final dir = createProject();
    writePng(dir, iconPath, alpha: 0);
    generate(dir, withIcon);

    expect(readFile(dir, '$iosSetDir/Contents.json'), contains('AppIcon.png'));
    final icon = decode(dir, '$iosSetDir/AppIcon.png');
    expect(icon.width, 1024);
    expect(icon.numChannels, 3);
    // A fully transparent source shows the white background.
    final pixel = icon.getPixel(512, 512);
    expect([pixel.r, pixel.g, pixel.b], [255, 255, 255]);
  });

  test('running again leaves every file unchanged', () {
    final dir = createProject();
    generate(dir, withIcon);
    final first = snapshot(dir);

    generate(dir, withIcon);
    expect(snapshot(dir), first);
  });

  test('removing icon deletes only what flavorpilot created', () {
    final dir = createProject();
    generate(dir, withIcon);
    writeFile(dir, '$androidFlavorDir/res/values/strings.xml', '<resources/>');

    generate(dir, withoutIcon);

    expect(exists(dir, '$androidFlavorDir/.flavorpilot-icon'), isFalse);
    expect(
      Directory(p.join(dir, '$androidFlavorDir/res/mipmap-mdpi')).existsSync(),
      isFalse,
    );
    expect(Directory(p.join(dir, iosSetDir)).existsSync(), isFalse);
    expect(
      readFile(dir, '$androidFlavorDir/res/values/strings.xml'),
      '<resources/>',
    );
  });

  test('a flavor without icon does nothing', () {
    final dir = createProject();
    final before = snapshot(dir);

    generate(dir, withoutIcon);
    expect(snapshot(dir), before);
  });

  /// Expects generating [config] on [dir] to fail with [message] and to leave
  /// every file unchanged.
  void expectRefused(String dir, ProjectConfig config, String message) {
    final before = snapshot(dir);
    expect(
      () => generate(dir, config),
      throwsA(
        isA<FlavorPilotException>().having(
          (e) => e.message,
          'message',
          contains(message),
        ),
      ),
    );
    expect(snapshot(dir), before);
  }

  test('refuses to replace hand-made Android icons', () {
    final dir = createProject();
    writeFile(dir, '$androidFlavorDir/res/mipmap-hdpi/ic_launcher.png', 'mine');

    expectRefused(dir, withIcon, 'not created by flavorpilot');
  });

  test('refuses to replace a hand-made iOS icon set', () {
    final dir = createProject();
    writeFile(dir, '$iosSetDir/Contents.json', '{"author": "xcode"}');

    expectRefused(dir, withIcon, 'not created by flavorpilot');
  });

  test('leaves hand-made icons alone when a flavor has no icon', () {
    final dir = createProject();
    writeFile(dir, '$androidFlavorDir/res/mipmap-hdpi/ic_launcher.png', 'mine');
    writeFile(dir, '$iosSetDir/Contents.json', '{"author": "xcode"}');
    final before = snapshot(dir);

    generate(dir, withoutIcon);
    expect(snapshot(dir), before);
  });

  group('rejects a bad source image', () {
    test('missing file', () {
      final dir = createProject();
      File(p.join(dir, iconPath)).deleteSync();
      expectRefused(dir, withIcon, 'was not found');
    });

    test('not a PNG', () {
      final dir = createProject();
      writeFile(dir, iconPath, 'not an image');
      expectRefused(dir, withIcon, 'not a valid PNG');
    });

    test('not square', () {
      final dir = createProject();
      writePng(dir, iconPath, height: 1200);
      expectRefused(dir, withIcon, 'must be square');
    });

    test('too small', () {
      final dir = createProject();
      writePng(dir, iconPath, width: 512, height: 512);
      expectRefused(dir, withIcon, 'at least 1024');
    });
  });

  test('needs an asset catalog for iOS', () {
    final dir = createProject();
    Directory(
      p.join(dir, 'ios/Runner/Assets.xcassets'),
    ).deleteSync(recursive: true);

    expectRefused(dir, withIcon, 'Assets.xcassets was not found');
  });
}
