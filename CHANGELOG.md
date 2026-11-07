## 0.5.0

- New `remove` command removes a flavor and everything flavorpilot created
  for it (Android and iOS setup, scheme, icons, IDE run configurations). It
  asks for confirmation first (`--yes` skips it) and keeps
  `lib/main_<flavor>.dart` and `.env` files that hold values.
- New `signing` command sets up the Android signing key for release builds:
  one key for every flavor by default, or one per flavor
  (`flavorpilot signing prod`). It creates the key with `keytool` or uses an
  existing keystore (`--keystore`), keeps the key files out of Git, and never
  replaces a key. `release` stops if the key files are missing.

## 0.4.0

- `build` and `release` accept `--split-per-abi` (shortcuts `--split` and
  `-s`) to make one APK per CPU architecture. `release` copies every split
  APK to `dist/` with its architecture in the name.
- `.env` files per flavor: `init` asks whether to create them, and the new
  `dotenv` command adds them to an existing setup. Each flavor's file is
  added to `.gitignore` and loaded automatically by `run`, `build`,
  `release` and the IDE run configurations. `add` creates one for the new
  flavor.
- Fix: `release` now undoes the version change whenever the build doesn't
  finish, including when Flutter can't start or Ctrl+C is pressed.
- Fix: a missing `flutter` shows a clear message instead of a stack trace.

## 0.3.0

- `init` adds `base_url` and `enable_logs` with example values to every flavor,
  so `AppFlavor.current.baseUrl` works right away.
- New `env` command adds the same settings to an existing setup, without
  changing values already there.
- `init`, `env`, `doctor` and `release` warn about example values still in use.

## 0.2.0

- `env` in `flavorpilot.yaml`: per-flavor settings like `base_url`, available
  in the app as `AppFlavor.current.baseUrl`.
- `icon` in `flavorpilot.yaml`: a separate app icon per flavor on Android and
  iOS.
- `add` asks for the value of each env key.
- `init --force` warns that it replaces env values and icons.
- Clearer `init` question about main files. Answering `y` now means one main
  file per flavor.

## 0.1.0

- `init`: set up flavors for Android, iOS, Dart and IDEs.
- `add`, `sync` and `doctor` to manage flavors after setup.
- `run`, `build` and `release` shortcuts for any flavor or alias.
- All file changes are applied together; nothing is written if a step fails.
