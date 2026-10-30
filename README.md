# flavorpilot

**Flutter flavors made simple: set up once, run anywhere with one command.**

flavorpilot is a command-line tool that sets up
[flavors](https://docs.flutter.dev/deployment/flavors) (development, staging,
production, …) in a Flutter project for **Android and iOS in one step**, then
gives you short commands to run, build and release any of them.

```sh
# Without flavorpilot
flutter run --flavor development -t lib/main_development.dart
flutter build appbundle --flavor production --release

# With flavorpilot
flavorpilot run dev
flavorpilot build prod --target appbundle
```

---

## Contents

- [What problem does it solve?](#what-problem-does-it-solve)
- [Requirements](#requirements)
- [Install](#install)
- [Before you start](#before-you-start)
- [Getting started, step by step](#getting-started-step-by-step)
- [What `init` changes in your project](#what-init-changes-in-your-project)
- [Commands](#commands)
- [Settings per flavor: `env`](#settings-per-flavor-env)
- [Icons per flavor](#icons-per-flavor)
- [The `flavorpilot.yaml` file](#the-flavorpilotyaml-file)
- [Common tasks](#common-tasks)
- [Safety: what flavorpilot will and won't do](#safety-what-flavorpilot-will-and-wont-do)
- [Troubleshooting](#troubleshooting)

---

## What problem does it solve?

Setting up flavors by hand means editing several files on two platforms:
Gradle product flavors, the Android manifest, Xcode build configurations and
schemes, Info.plist, the Podfile, and Dart entry points. It's easy to miss a
step, and the mistake often only shows up when a build fails.

flavorpilot does all of that from a few answers, keeps the settings in one
file (`flavorpilot.yaml`), and can check at any time that everything is
still in sync.

## Requirements

- **Flutter** with Dart **3.8 or newer**.
- A project created with `flutter create` (standard `android/` and
  `ios/Runner.xcodeproj` folders).
- **Xcode** to build iOS flavors (macOS only), and **CocoaPods** if your
  project uses it.
- **Git** is strongly recommended, so you can review and undo changes.

## Install

```sh
dart pub global activate flavorpilot
```

Check that it works:

```sh
flavorpilot --version
```

If your terminal says `command not found`, add Dart's global bin folder to
your `PATH` (the `dart pub global activate` output shows the exact line).

## Before you start

Run through this checklist once. It takes a minute and avoids most problems.

1. **Commit or stash your work.** flavorpilot edits native project files.
   With a clean Git state, `git diff` shows exactly what changed and
   `git checkout .` undoes it.
2. **Open a terminal in your project root**, the folder that contains
   `pubspec.yaml`. Every command must be run from there.
3. **Already have flavors made by hand?** flavorpilot will not overwrite
   them; it stops with a message instead. Remove the old `productFlavors`
   block from Gradle and the old `Debug-*`/`Release-*`/`Profile-*`
   configurations from Xcode first, then run `init`. See
   [Moving from hand-made flavors](#moving-from-hand-made-flavors).
4. **Decide on your flavor names.** They must start with a lowercase letter
   and contain only letters and digits, e.g. `development`, `staging`,
   `qualityAssurance`. No spaces, `-` or `_` (Gradle doesn't allow them).

## Getting started, step by step

### Step 1: Run `init`

```sh
flavorpilot init
```

You'll be asked a few questions. Every question shows a default in
`[brackets]`; press **Enter** to accept it.

```text
App name [My app]: My App
Base app id (Android applicationId / iOS bundle id) [com.example.my_app]:
Flavors (comma separated) [development,staging,production]:
  [development] short alias [dev]:
  [development] app name [My App DEV]:
  [development] app id [com.example.my_app.dev]:
  [staging] short alias [stg]:
  ...
Create a separate main file for each flavor? (y/N):
```

| Question | What it means |
| --- | --- |
| App name | The base name shown on the device. Other flavors add a suffix, e.g. "My App DEV". |
| Base app id | Your production id. Other flavors add a suffix, e.g. `.dev`, so all flavors can be **installed side by side** on one device. |
| Flavors | The flavor names, separated by commas. |
| short alias | A short name you'll type in commands, e.g. `dev` in `flavorpilot run dev`. |
| app name / app id | The name and id for that flavor. `production` keeps the base values. |
| Separate main file? | **No** (recommended, the default): one `lib/main.dart` for all flavors. **Yes**: one `lib/main_<flavor>.dart` per flavor, useful when each flavor needs different startup code (for example a separate Firebase project). |

> Want to skip the questions? `flavorpilot init --yes` uses every default.

When it finishes, you'll see a list of every file it changed.

### Step 2: Review the changes

```sh
git status
git diff
```

The section [What `init` changes](#what-init-changes-in-your-project)
explains each file.

### Step 3: iOS with CocoaPods only

If your project has an `ios/Podfile`, install pods so CocoaPods creates the
settings for the new configurations:

```sh
cd ios && pod install && cd ..
```

Projects that use Swift Package Manager (no Podfile) can skip this step.

### Step 4: Read the flavor in your code

`init` creates `lib/flavors.dart` with an `AppFlavor` enum:

```dart
import 'flavors.dart';

void main() {
  final flavor = AppFlavor.current; // e.g. AppFlavor.development

  print('Running ${flavor.appName}');
  if (flavor == AppFlavor.development) {
    // Something only for development.
  }
  // runApp(...);
}
```

Need a different base URL or other settings per flavor? See
[Settings per flavor](#settings-per-flavor-env).

> `AppFlavor.current` only works when the app was started with a flavor
> (through flavorpilot, `flutter run --flavor …`, or the IDE run
> configurations it created). Running plain `flutter run` throws an error
> that tells you so.

### Step 5: Run it

```sh
flavorpilot run dev
```

You can also pick a flavor from your IDE: flavorpilot added run
configurations for **VS Code** (Run and Debug panel) and **Android Studio**
(the run configurations dropdown).

### Step 6: Check everything is in sync

```sh
flavorpilot doctor
```

Run this any time something looks wrong, and after editing project files
by hand.

## What `init` changes in your project

Every change is listed here, so nothing is a surprise.

| Platform | File | Change |
| --- | --- | --- |
| Config | `flavorpilot.yaml` | **Created.** Your flavors and settings; the source of truth. |
| Android | `android/app/build.gradle.kts` (or `build.gradle`) | Adds a `productFlavors` block between `// flavorpilot:start` and `// flavorpilot:end` comments. |
| Android | `android/app/src/main/AndroidManifest.xml` | Sets `android:label="@string/app_name"`, so each flavor shows its own name. |
| iOS | `ios/Runner.xcodeproj/project.pbxproj` | Adds `Debug-<flavor>`, `Release-<flavor>` and `Profile-<flavor>` build configurations with the flavor's bundle id and app name. |
| iOS | `ios/Runner.xcodeproj/xcshareddata/xcschemes/<flavor>.xcscheme` | **Created** for each flavor (Flutter needs a scheme with the flavor's exact name). Existing schemes are kept. |
| iOS | `ios/Flutter/flavorpilot/*.xcconfig` | **Created.** One per configuration, so CocoaPods settings load correctly. |
| iOS | `ios/Runner/Info.plist` | Sets the display name to `$(FLAVOR_APP_NAME)`. |
| iOS | `ios/Podfile` (if it exists) | Maps each new configuration to `:debug` or `:release` between `# flavorpilot:start` / `# flavorpilot:end`. |
| Dart | `lib/flavors.dart` | **Created.** The `AppFlavor` enum, with a field for each [`env`](#settings-per-flavor-env) key. |
| Dart | `lib/main_<flavor>.dart` | **Created** only if you chose one main file per flavor. Existing files are kept. |
| IDE | `.vscode/launch.json` | Adds entries named `<flavor> (flavorpilot)`. Your own entries are kept. |
| IDE | `.run/<flavor>.run.xml` | **Created.** Android Studio run configurations. |

`lib/main.dart` is **never** changed.

`env` and `icon` aren't part of the `init` questions: add them to
`flavorpilot.yaml` afterwards and run `flavorpilot sync`.

## Commands

Run `flavorpilot help <command>` to see every option of a command.

Wherever a command takes `<flavor>`, you can type the flavor's **name or
its alias** (`development` or `dev`).

Any Flutter flag that flavorpilot doesn't know can be passed **after `--`**:

```sh
flavorpilot run dev -- --dart-define=API_LOG=true
flavorpilot build prod -- --obfuscate --split-debug-info=build/symbols
```

### `init`: set up flavors

```sh
flavorpilot init [--yes] [--force]
```

Asks the setup questions, saves `flavorpilot.yaml`, and updates every
platform. Use it **once per project**.

| Option | Meaning |
| --- | --- |
| `-y`, `--yes` | Skip the questions and use the defaults. |
| `--force` | Start over even if `flavorpilot.yaml` exists. Your answers replace the old file, so its `env` values and icons are lost (it warns you first). |

### `run`: run a flavor

```sh
flavorpilot run <flavor> [--mode debug|profile|release] [-d <device>]
```

| Option | Default | Meaning |
| --- | --- | --- |
| `-m`, `--mode` | `debug` | Build mode. |
| `-d`, `--device` | | Device id, same as `flutter run -d`. |

```sh
flavorpilot run dev
flavorpilot run prod --mode release -d emulator-5554
```

Hot reload (`r`) and hot restart (`R`) work as usual.

### `build`: build a flavor

```sh
flavorpilot build <flavor> [--target apk|appbundle|ios|ipa] [--mode ...]
```

| Option | Default | Meaning |
| --- | --- | --- |
| `--target` | `apk` | What to build. |
| `-m`, `--mode` | `release` | Build mode. |

```sh
flavorpilot build prod                       # release APK
flavorpilot build prod --target appbundle    # for Google Play
flavorpilot build qa --target ipa            # for TestFlight / App Store
flavorpilot build dev --target ios --mode debug -- --simulator
```

The output is where Flutter normally puts it, e.g.
`build/app/outputs/flutter-apk/app-production-release.apk`.

### `release`: bump the version and build a release

```sh
flavorpilot release <flavor> [--target apk|appbundle|ipa] [--bump ...] [--out dist]
```

It does three things in order:

1. Increases `version:` in `pubspec.yaml`.
2. Builds the flavor in release mode.
3. Copies the result to `dist/<app>-<flavor>-<version>.<ext>`, e.g.
   `dist/my_app-production-1.4.0+12.aab`.

If the build fails, the version change is **undone automatically**.

| Option | Default | Meaning |
| --- | --- | --- |
| `--target` | `apk` | `apk`, `appbundle` or `ipa`. |
| `--bump` | `build` | Which part of the version to increase (see below). |
| `--out` | `dist` | Folder for the finished file. |

| `--bump` | `1.2.3+4` becomes |
| --- | --- |
| `build` | `1.2.3+5` |
| `patch` | `1.2.4+5` |
| `minor` | `1.3.0+5` |
| `major` | `2.0.0+5` |
| `none` | `1.2.3+4` (unchanged) |

The build number (after `+`) goes up with every bump, because the app
stores reject an upload that reuses one.

```sh
flavorpilot release prod --target appbundle --bump patch
```

> For `ipa`, signing must already be set up in Xcode for that flavor's
> bundle id.

### `add`: add a flavor later

```sh
flavorpilot add <name> [--alias <a>] [--app-name <n>] [--app-id <id>] [--yes]
```

Adds the flavor to `flavorpilot.yaml` and updates every platform. Anything
you don't pass as an option is asked (or defaulted with `--yes`). Default
ids are based on your `production` flavor, e.g. `com.example.app.qa`.

```sh
flavorpilot add qualityAssurance --yes
flavorpilot add uat --alias u --app-name "My App UAT" --app-id com.example.app.uat
```

If your flavors use `env`, it also asks for each value. The suggested value
comes from `production` (or your first flavor). With `--yes` those values are
copied as they are and a warning reminds you to change them, so **update the
new flavor's `base_url` before using it**.

> `add` rewrites `flavorpilot.yaml`, so comments you wrote in it are removed.

### `sync`: apply changes from `flavorpilot.yaml`

```sh
flavorpilot sync
```

Re-applies `flavorpilot.yaml` to every platform. Use it after you **edit
`flavorpilot.yaml` by hand** (for example to rename an app or change an id),
or after **Flutter creates `ios/Podfile`** (this happens when you add your
first plugin that uses CocoaPods). It is safe to run any number of times.

### `doctor`: check the setup

```sh
flavorpilot doctor
```

Works out what every flavor file *should* contain for the current
`flavorpilot.yaml`, without writing anything, and compares that with what's
on disk. It lists any file that is missing or out of date.

- Exit code `0`: everything is in sync.
- Exit code `1`: something needs fixing; usually `flavorpilot sync` fixes it.

Handy in CI to catch a forgotten `sync`.

## Settings per flavor: `env`

Use `env` for values that differ between flavors, like a base URL or a logging
switch.

**1. Add them to `flavorpilot.yaml`:**

```yaml
flavors:
  development:
    alias: dev
    env:
      base_url: "https://dev.api.example.com"
      enable_logs: true
      timeout_seconds: 60
  production:
    alias: prod
    env:
      base_url: "https://api.example.com"
      enable_logs: false
      timeout_seconds: 30
```

**2. Apply them:**

```sh
flavorpilot sync
```

**3. Use them in your app.** Each key becomes a field on `AppFlavor`, with its
type:

```dart
import 'flavors.dart';

final dio = Dio(BaseOptions(baseUrl: AppFlavor.current.baseUrl));

if (AppFlavor.current.enableLogs) {
  // ...
}
```

Rules, checked before any file changes:

- **Every flavor needs the same keys.** A missing key is an error, so you find
  out now and not when the app crashes.
- **Each key keeps one type across flavors:** text, number or `true`/`false`.
  Whole and decimal numbers can be mixed, and the field becomes `double`.
- **Keys are `snake_case`**, like `base_url`. Names `AppFlavor` already uses,
  like `name` or `app_name`, and Dart keywords, like `class`, aren't allowed.

> ⚠️ **Never put secrets in `env`** (passwords, private API keys). These values
> are stored in `flavorpilot.yaml` in your Git repository and inside the built
> app, where anyone can extract them.

## Icons per flavor

Give a flavor its own icon so you can tell the builds apart on your device.

**1. Add `icon` to the flavor in `flavorpilot.yaml`.** The path is relative to
the project root:

```yaml
flavors:
  development:
    alias: dev
    icon: "assets/icons/dev.png"
```

The image must be a **PNG**, **square**, and at least **1024×1024**.

**2. Apply it:**

```sh
flavorpilot sync
```

| Platform | What it creates |
| --- | --- |
| Android | Five sizes in `android/app/src/<flavor>/res/mipmap-*`, using the icon name from your manifest. |
| iOS | `ios/Runner/Assets.xcassets/AppIcon-<flavor>.appiconset`, used by that flavor's build configurations. Transparent areas become white, because Apple rejects transparency in app icons. |

A flavor without `icon` keeps the project's current icon. If you remove `icon`
and run `sync`, the icons flavorpilot created are deleted.

- **Adaptive icons:** if your project has an adaptive icon in
  `android/app/src/main/res/mipmap-anydpi-v26`, it can hide the flavor icon on
  Android 8 and newer. flavorpilot warns you when this applies.
- **Your own icons are safe:** if a flavor already has hand-made icons in those
  locations, flavorpilot stops instead of replacing them.

## The `flavorpilot.yaml` file

This file lives next to `pubspec.yaml` and is the **single source of truth**.
Commit it to Git. After editing it, run `flavorpilot sync`.

```yaml
main_mode: single            # single | multiple

flavors:
  development:
    alias: dev
    app_name: "My App DEV"
    android_id: "com.example.myapp.dev"
    ios_bundle_id: "com.example.myapp.dev"
  production:
    alias: prod
    app_name: "My App"
    android_id: "com.example.myapp"
    ios_bundle_id: "com.example.myapp"
```

| Key | Required | Meaning |
| --- | --- | --- |
| `main_mode` | No (default `single`) | `single`: one `lib/main.dart`. `multiple`: one `lib/main_<flavor>.dart` per flavor. |
| `flavors` | Yes | One entry per flavor. The key is the flavor name used by `--flavor`. |
| `alias` | No | Short name for commands. Must be unique across all names and aliases. |
| `app_name` | No | Name on the device. Defaults to the flavor name. |
| `android_id` | No | Android `applicationId`. Defaults to the project's own id. |
| `ios_bundle_id` | No | iOS bundle identifier. Defaults to the project's own id. |
| `icon` | No | Path to the flavor's icon. See [Icons per flavor](#icons-per-flavor). |
| `env` | No | Custom settings for the flavor. See [Settings per flavor](#settings-per-flavor-env). |

Rules: flavor names start with a lowercase letter and contain only letters
and digits; no name or alias can appear twice. See
[example/flavorpilot.yaml](example/flavorpilot.yaml) for a full example.

## Common tasks

### Change an app name or id

1. Edit the value in `flavorpilot.yaml`.
2. Run `flavorpilot sync`.

### Remove a flavor

1. Delete its entry from `flavorpilot.yaml`.
2. Run `flavorpilot sync`.
3. Delete what `sync` doesn't remove on purpose (they may contain your own
   changes): `ios/Runner.xcodeproj/xcshareddata/xcschemes/<flavor>.xcscheme`,
   `.run/<flavor>.run.xml` and, in multiple mode, `lib/main_<flavor>.dart`.
   If the flavor had an icon, also delete `android/app/src/<flavor>` and
   `ios/Runner/Assets.xcassets/AppIcon-<flavor>.appiconset`.

### Added your first CocoaPods plugin after `init`

Flutter creates `ios/Podfile` at that point, without your flavors. Run:

```sh
flavorpilot sync
cd ios && pod install
```

### Build in CI

```sh
dart pub global activate flavorpilot
flavorpilot doctor                      # fail fast if setup is out of sync
flavorpilot release prod --target appbundle --bump none
```

Use `--bump none` if your CI sets the version itself.

### Moving from hand-made flavors

flavorpilot refuses to touch flavors it didn't create. To switch:

1. Note your current flavor names, ids and app names.
2. Remove the `productFlavors` (and `flavorDimensions`) block from
   `android/app/build.gradle(.kts)`.
3. In Xcode, delete the `Debug-*`, `Release-*` and `Profile-*`
   configurations (Project → Info → Configurations).
4. Run `flavorpilot init` and enter the same names and ids.
5. Build each flavor once to confirm, then commit.

### Undo everything

If you committed before running `init` (see
[Before you start](#before-you-start)):

```sh
git checkout . && git clean -fd
```

`git clean -fd` deletes **every** untracked file, not only flavorpilot's.
Run `git clean -nd` first to see what it would remove.

## Safety: what flavorpilot will and won't do

- **All or nothing.** Every change is worked out in memory first. If any step
  fails, flavorpilot stops and **no file is written**.
- **Never overwrites your own setup.** It stops instead when it finds
  `productFlavors`, Xcode flavor configurations or flavor icons it didn't
  create. It never replaces an existing scheme, a hand-written
  `lib/flavors.dart`, or an existing `lib/main_<flavor>.dart`.
- **Never touches `lib/main.dart`.**
- **Marks what it owns.** Its blocks are wrapped in `flavorpilot:start` /
  `flavorpilot:end` comments, and its Xcode configurations carry a
  `FLAVORPILOT = YES` build setting. That's how running it again replaces
  its own work instead of duplicating it.
- **Shows what it runs.** `run`, `build` and `release` print the exact
  `flutter` command before running it.

Don't edit the marked blocks by hand: `sync` will replace them. Change
`flavorpilot.yaml` instead.

## Troubleshooting

| Message | Cause and fix |
| --- | --- |
| `flavorpilot.yaml not found` | You're not in the project root, or `init` hasn't been run. `cd` to the folder with `pubspec.yaml`. |
| `No pubspec.yaml found` | Same as above: run from the project root. |
| `flavorpilot.yaml already exists` | `init` was already run. Use `flavorpilot sync` to apply changes, or `init --force` to start over. |
| `… already has productFlavors that were not created by flavorpilot` | Hand-made Android flavors. See [Moving from hand-made flavors](#moving-from-hand-made-flavors). |
| `ios/Runner.xcodeproj already has a "Debug-…" build configuration that was not created by flavorpilot` | Hand-made iOS flavors. Same fix as above. |
| `Unknown flavor "…"` | Typo, or the flavor doesn't exist. The message lists the available flavors and aliases. |
| `Invalid flavor name "…"` | Use a lowercase first letter and only letters and digits. |
| `.vscode/launch.json has comments or invalid JSON` (warning) | flavorpilot can't safely edit a launch.json with comments, so it skips it. Remove the comments and run `flavorpilot sync`, or add the entries yourself. |
| `lib/flavors.dart already exists and was not created by flavorpilot` (warning) | You have your own `flavors.dart`; it was left alone. Rename yours to use the generated `AppFlavor`. |
| `Unsupported version "…" in pubspec.yaml` | `release` needs a version like `1.2.3+4` in `pubspec.yaml`. |
| `env key "…" is missing from: …` | Every flavor needs the same `env` keys. Add the key to the flavors listed. |
| `env key "…" has different types across flavors` | Use the same type in every flavor. Check for a number or `true` written in quotes. |
| `Flavor "…": icon "…" was not found` | Fix the path in `flavorpilot.yaml`. It's relative to the project root. |
| `Flavor "…": icon "…" is …×…` | The icon must be square and at least 1024×1024. |
| `… already has … icons that were not created by flavorpilot` | The flavor has hand-made icons. Delete them, or remove `icon` from the flavor. |
| App throws `Unknown flavor "null"` at startup | The app was started without a flavor. Use `flavorpilot run <flavor>` or one of the IDE run configurations. |
| `doctor` lists files as out of date | A file was edited by hand or `flavorpilot.yaml` changed. Run `flavorpilot sync`, then review with `git diff`. |
| iOS build can't find Pods settings | Run `cd ios && pod install`. If `ios/Podfile` was created after `init`, run `flavorpilot sync` first. |

### Exit codes

| Code | Meaning |
| --- | --- |
| `0` | Success. |
| `1` | A known problem (see the message), or `doctor` found issues. |
| `64` | Wrong usage, e.g. a missing flavor name. The command's help is printed. |
| other | `run`, `build` and `release` return Flutter's own exit code when Flutter fails. |
