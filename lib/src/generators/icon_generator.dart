import 'dart:io';
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;

import '../models/flavor.dart';
import '../models/project_config.dart';
import '../utils/exceptions.dart';
import '../utils/file_changes.dart';
import 'generator.dart';
import 'ios/pbxproj_editor.dart';

/// Creates a separate app icon for every flavor that sets `icon`.
///
/// - Android: resized copies in `android/app/src/<flavor>/res/mipmap-*`.
///   Gradle uses them instead of the main icons for that flavor.
/// - iOS: `ios/Runner/Assets.xcassets/AppIcon-<flavor>.appiconset`. The
///   flavor's build configurations point to it (see [PbxprojEditor]).
///
/// When `icon` is removed from a flavor, the icons created here are deleted
/// again. Icons the developer added by hand are never replaced or deleted.
class IconGenerator extends Generator {
  IconGenerator({required super.projectDir, required super.logger});

  /// Smallest source size: iOS needs a 1024×1024 icon.
  static const minSize = 1024;

  /// Android icon sizes, by density folder.
  static const _androidSizes = {
    'mdpi': 48,
    'hdpi': 72,
    'xhdpi': 96,
    'xxhdpi': 144,
    'xxxhdpi': 192,
  };

  /// Marks a flavor's Android icons as ours. It sits outside `res/`, so it
  /// never reaches the Android build.
  static const _androidMarker = '.flavorpilot-icon';

  /// Marks an iOS icon set as ours, inside its Contents.json.
  static const _iosAuthor = '"author" : "flavorpilot"';

  static const _iosIconFile = 'AppIcon.png';

  String get _appDir => p.join(projectDir, 'android', 'app');
  String get _manifestPath =>
      p.join(_appDir, 'src', 'main', 'AndroidManifest.xml');
  String get _catalogDir =>
      p.join(projectDir, 'ios', 'Runner', 'Assets.xcassets');

  @override
  String get label => 'Icons';

  @override
  void generate(ProjectConfig config, FileChanges changes) {
    final hasAndroid = Directory(_appDir).existsSync();
    final hasIos = Directory(
      p.join(projectDir, 'ios', 'Runner.xcodeproj'),
    ).existsSync();
    final usesIcons = config.flavors.any((f) => f.icon != null);

    final androidIcon = hasAndroid ? _androidIconName() : null;
    if (hasAndroid && usesIcons) _warnAboutAndroidIcon(androidIcon);

    for (final flavor in config.flavors) {
      final source = flavor.icon == null ? null : _loadIcon(flavor);
      if (androidIcon != null) {
        _updateAndroid(flavor, source, androidIcon, changes);
      }
      if (hasIos) _updateIos(flavor, source, changes);
    }
  }

  /// Reads and checks the source PNG of [flavor].
  img.Image _loadIcon(Flavor flavor) {
    // `join` keeps an absolute path as it is.
    final file = File(p.join(projectDir, flavor.icon!));
    if (!file.existsSync()) {
      throw FlavorPilotException(
        'Flavor "${flavor.name}": icon "${flavor.icon}" was not found.',
      );
    }

    final image = img.decodePng(file.readAsBytesSync());
    if (image == null) {
      throw FlavorPilotException(
        'Flavor "${flavor.name}": icon "${flavor.icon}" is not a valid PNG.',
      );
    }
    if (image.width != image.height || image.width < minSize) {
      throw FlavorPilotException(
        'Flavor "${flavor.name}": icon "${flavor.icon}" is '
        '${image.width}×${image.height}. It must be square and at least '
        '$minSize×$minSize.',
      );
    }
    // Normalize PNG variants, like palette or 16-bit images, before resizing.
    return image.convert(
      format: img.Format.uint8,
      numChannels: 4,
      noAnimation: true,
    );
  }

  /// The icon file name in the manifest, e.g. `ic_launcher` from
  /// `@mipmap/ic_launcher`. Returns null when the icon isn't a mipmap, since
  /// mipmap copies wouldn't replace it.
  String? _androidIconName() {
    final manifest = File(_manifestPath);
    if (!manifest.existsSync()) return 'ic_launcher';

    final icon = RegExp(
      r'android:icon="([^"]+)"',
    ).firstMatch(manifest.readAsStringSync())?[1];
    if (icon == null) return 'ic_launcher';
    return icon.startsWith('@mipmap/')
        ? icon.substring('@mipmap/'.length)
        : null;
  }

  /// Warns when the project's main icon would hide the flavor icons.
  void _warnAboutAndroidIcon(String? iconName) {
    if (iconName == null) {
      logger.warn(
        'android:icon in AndroidManifest.xml is not a @mipmap icon, so '
        'Android flavor icons were skipped.',
      );
      return;
    }
    final adaptive = File(
      p.join(
        _appDir,
        'src',
        'main',
        'res',
        'mipmap-anydpi-v26',
        '$iconName.xml',
      ),
    );
    if (adaptive.existsSync()) {
      logger.warn(
        'The project has an adaptive icon ($iconName.xml in mipmap-anydpi-v26). '
        'On Android 8 and newer it can hide the flavor icons.',
      );
    }
  }

  /// Adds or removes the Android icons of [flavor].
  void _updateAndroid(
    Flavor flavor,
    img.Image? source,
    String iconName,
    FileChanges changes,
  ) {
    final flavorDir = p.join(_appDir, 'src', flavor.name);
    final marker = File(p.join(flavorDir, _androidMarker));
    final isOurs = marker.existsSync();
    final targets = {
      for (final MapEntry(key: density, value: size) in _androidSizes.entries)
        p.join(flavorDir, 'res', 'mipmap-$density', '$iconName.png'): size,
    };

    if (source == null) {
      if (!isOurs) return;
      changes
        ..deleteFile(marker.path)
        ..note('Removed the Android icons of "${flavor.name}"');
      targets.keys.forEach(changes.deleteFile);
      return;
    }

    if (!isOurs && targets.keys.any((path) => File(path).existsSync())) {
      throw FlavorPilotException(
        'android/app/src/${flavor.name}/res already has $iconName icons that '
        'were not created by flavorpilot. Remove them first, or remove '
        '"icon" from this flavor.',
      );
    }

    targets.forEach((path, size) {
      changes.writeBytes(path, _png(source, size));
    });
    changes
      ..write(
        marker.path,
        'Android icons in this folder were created by flavorpilot.\n',
      )
      ..note('Created the Android icons of "${flavor.name}"');
  }

  /// Adds or removes the iOS icon set of [flavor].
  void _updateIos(Flavor flavor, img.Image? source, FileChanges changes) {
    final setName = PbxprojEditor.iconSetName(flavor);
    final setDir = p.join(_catalogDir, '$setName.appiconset');
    final contents = File(p.join(setDir, 'Contents.json'));
    final exists = contents.existsSync();
    final isOurs = exists && contents.readAsStringSync().contains(_iosAuthor);

    if (source == null) {
      if (!isOurs) return;
      changes
        ..deleteFile(p.join(setDir, _iosIconFile))
        ..deleteFile(contents.path)
        ..note('Removed the iOS icon of "${flavor.name}"');
      return;
    }

    if (exists && !isOurs) {
      throw FlavorPilotException(
        'ios/Runner/Assets.xcassets already has $setName, which was not '
        'created by flavorpilot. Remove it first, or remove "icon" from this '
        'flavor.',
      );
    }
    if (!Directory(_catalogDir).existsSync()) {
      throw const FlavorPilotException(
        'ios/Runner/Assets.xcassets was not found, so iOS flavor icons can '
        'not be created.',
      );
    }

    changes
      ..writeBytes(p.join(setDir, _iosIconFile), _iosPng(source))
      ..write(contents.path, '''
{
  "images" : [
    {
      "filename" : "$_iosIconFile",
      "idiom" : "universal",
      "platform" : "ios",
      "size" : "1024x1024"
    }
  ],
  "info" : {
    $_iosAuthor,
    "version" : 1
  }
}
''')
      ..note('Created the iOS icon of "${flavor.name}"');
  }

  /// A PNG of [source] resized to [size]×[size].
  Uint8List _png(img.Image source, int size) => img.encodePng(
    img.copyResize(
      source,
      width: size,
      height: size,
      interpolation: img.Interpolation.cubic,
    ),
  );

  /// The 1024×1024 iOS icon. Apple rejects transparency in app icons, so the
  /// image is placed on a white background.
  Uint8List _iosPng(img.Image source) {
    final resized = img.copyResize(
      source,
      width: minSize,
      height: minSize,
      interpolation: img.Interpolation.cubic,
    );
    final background = img.Image(
      width: minSize,
      height: minSize,
      numChannels: 3,
    );
    img.fill(background, color: img.ColorRgb8(255, 255, 255));
    img.compositeImage(background, resized);
    return img.encodePng(background);
  }
}
