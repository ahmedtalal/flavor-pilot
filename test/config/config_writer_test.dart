import 'package:flavorpilot/flavorpilot.dart';
import 'package:test/test.dart';

void main() {
  const writer = ConfigWriter();
  const loader = ConfigLoader();

  test('written YAML loads back to the same config', () {
    const config = ProjectConfig(
      mainMode: MainMode.multiple,
      flavors: [
        Flavor(
          name: 'development',
          alias: 'dev',
          appName: 'App DEV',
          androidId: 'com.example.app.dev',
          iosBundleId: 'com.example.app.dev',
        ),
        Flavor(name: 'production'),
      ],
    );

    final loaded = loader.parse(writer.toYaml(config));

    expect(loaded.mainMode, MainMode.multiple);
    expect(loaded.flavors.map((f) => f.name), ['development', 'production']);
    expect(loaded.flavors.first.toMap(), config.flavors.first.toMap());
    expect(loaded.flavors.last.toMap(), isEmpty);
  });

  test('app names with YAML special characters survive', () {
    const name = r'My: App #1 "Beta" \ test';
    final yaml = writer.toYaml(
      const ProjectConfig(
        flavors: [Flavor(name: 'beta', appName: name)],
      ),
    );

    expect(loader.parse(yaml).flavors.single.appName, name);
  });
}
