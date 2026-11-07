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
- [`.env` files per flavor](#env-files-per-flavor)
- [Icons per flavor](#icons-per-flavor)
- [Android signing keys](#android-signing-keys)
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
Create a .env file for each flavor? (y/N):
```

| Question | What it means |
| --- | --- |
| App name | The base name shown on the device. Other flavors add a suffix, e.g. "My App DEV". |
| Base app id | Your production id. Other flavors add a suffix, e.g. `.dev`, so all flavors can be **installed side by side** on one device. |
| Flavors | The flavor names, separated by commas. |
| short alias | A short name you'll type in commands, e.g. `dev` in `flavorpilot run dev`. |
| app name / app id | The name and id for that flavor. `production` keeps the base values. |
| Separate main file? | **No** (recommended, the default): one `lib/main.dart` for all flavors. **Yes**: one `lib/main_<flavor>.dart` per flavor, useful when each flavor needs different startup code (for example a separate Firebase project). |
| `.env` file for each flavor? | **No** (the default): no `.env` files. **Yes**: creates `.env.<flavor>` for every flavor. See [`.env` files per flavor](#env-files-per-flavor). |

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

  print('Running ${flavor.appName} against ${flavor.baseUrl}');
  if (flavor.enableLogs) {
    // Something only for flavors with logs turned on.
  }
  // runApp(...);
}
```

`baseUrl` and `enableLogs` are ready to use, with **example values**. Replace
the example URLs in `flavorpilot.yaml`, then run `flavorpilot sync`. See
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
| dotenv | `.env.<flavor>` | **Created** only if you answered yes to the `.env` question. Existing files are kept. |
| dotenv | `.gitignore` | Lists the `.env` files between `# flavorpilot:start` / `# flavorpilot:end`, only when they are used. |

`lib/main.dart` is **never** changed.

`init` doesn't add icons, because they need a real image. See
[Icons per flavor](#icons-per-flavor).

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
| `-s`, `--split`, `--split-per-abi` | off | One smaller APK per CPU architecture instead of one large APK. Only with `--target apk`. |

```sh
flavorpilot build prod                       # release APK
flavorpilot build prod -s                    # one APK per CPU architecture
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

If the build fails, the version change is **undone automatically**. It also
warns you if the flavor still has example `env` values, but doesn't stop the
build.

| Option | Default | Meaning |
| --- | --- | --- |
| `--target` | `apk` | `apk`, `appbundle` or `ipa`. |
| `--bump` | `build` | Which part of the version to increase (see below). |
| `--out` | `dist` | Folder for the finished file. |
| `-s`, `--split`, `--split-per-abi` | off | One APK per CPU architecture, each copied with its architecture in the name, e.g. `dist/my_app-production-arm64-v8a-1.4.0+12.apk`. Only with `--target apk`. |

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
flavorpilot release prod -s --bump patch     # split APKs
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

### `signing`: set up the Android signing key

```sh
flavorpilot signing [<flavor>] [--keystore <path>] [--alias <name>]
```

Sets up the key that Android release builds are signed with, which Google
Play needs. Without a flavor, **one key is used by every flavor**. With a
flavor, that flavor gets its own key. See [Android signing keys](#android-signing-keys).

| Option | Default | Meaning |
| --- | --- | --- |
| `--keystore` | | Use a keystore (`.jks`) you already have, instead of creating a new key. |
| `--alias` | `upload` | Name of the key inside the keystore. |

```sh
flavorpilot signing                          # one new key for every flavor
flavorpilot signing prod                     # a separate key for production
flavorpilot signing --keystore ~/keys/old.jks --alias release
```

### `remove`: remove a flavor

```sh
flavorpilot remove <flavor> [--yes]
```

Removes the flavor from `flavorpilot.yaml` and everything for it: the Android
flavor, the iOS configurations and scheme, its icons, its main file and `.env`
file, and the VS Code and Android Studio run configurations. It lists what it
will delete and asks you to confirm first.

| Option | Meaning |
| --- | --- |
| `-y`, `--yes` | Remove without asking. |

```sh
flavorpilot remove qa
flavorpilot remove staging --yes
```

> ⚠️ It deletes **everything** for the flavor, including
> `lib/main_<flavor>.dart` and its `.env` file, even if you added your own
> code or values to them. Copy anything you want to keep first. The question
> lists every file before anything is deleted.

Only the flavor's own **signing key** is kept, because losing a key can stop
you from updating your app. It is no longer in `.gitignore`, so move it
somewhere safe before your next commit.

The last flavor can't be removed. Like `add`, it rewrites `flavorpilot.yaml`,
so comments you wrote in it are removed.

### `env`: add example settings to an existing setup

```sh
flavorpilot env
```

Adds `base_url` and `enable_logs` with example values to every flavor, then
updates the project. Use it in a project set up with flavorpilot 0.2.0 or
older; `init` already does this for new projects.

Values already in `flavorpilot.yaml` are never changed, so it's safe to run
again. When it adds something, it rewrites `flavorpilot.yaml`, so comments you
wrote in it are removed.

### `dotenv`: add a `.env` file to every flavor

```sh
flavorpilot dotenv
```

Gives every flavor its own `.env` file (`.env.development`, `.env.production`,
…), adds them to `.gitignore`, and makes `run`, `build`, `release` and the IDE
run configurations load them. Use it in a project where you answered **No** to
the `.env` question in `init`. See [`.env` files per flavor](#env-files-per-flavor).

Existing `.env` files are never changed, so it's safe to run again. It rewrites
`flavorpilot.yaml`, so comments you wrote in it are removed.

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

Handy in CI to catch a forgotten `sync`. It also warns about example `env`
values, without failing the check.

## Settings per flavor: `env`

Use `env` for values that differ between flavors, like a base URL or a logging
switch. `init` adds `base_url` and `enable_logs` with example values for you.
In an older setup, run `flavorpilot env` to add them.

**1. Change the values or add your own in `flavorpilot.yaml`:**

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

## `.env` files per flavor

Use `.env` files for values you don't want in Git, like API keys. Each flavor
gets its own file, and flavorpilot always loads the right one.

**1. Create the files.** Answer **yes** to the `.env` question in `init`, or
run:

```sh
flavorpilot dotenv
```

This creates one file per flavor and adds them to `.gitignore`:

```text
.env.development
.env.staging
.env.production
```

**2. Add your values**, one per line:

```sh
# .env.development
API_KEY=dev-key-123
MAPS_KEY=abc
```

**3. Read them in your app:**

```dart
const apiKey = String.fromEnvironment('API_KEY');
```

**4. Run as usual.** No extra flags are needed:

```sh
flavorpilot run dev          # loads .env.development
flavorpilot release prod     # loads .env.production
```

flavorpilot passes the file to Flutter with `--dart-define-from-file`, and the
VS Code and Android Studio run configurations do the same. If a flavor's file
is missing, flavorpilot stops with a clear message instead of building without
your values.

Each flavor has an `env_file` setting in `flavorpilot.yaml`. Change it to use
another file name, then run `flavorpilot sync`. A flavor added later with `add`
gets its own `.env` file automatically.

- **Share the key names with your team** in a file like `.env.example`
  (without the values); the `.env` files themselves stay on each computer.
- **In CI**, create the file from your CI secrets before building, e.g.
  `echo "$PROD_ENV" > .env.production`.
- These values are kept out of Git, but they are still **inside the built
  app**. Use them for keys meant for apps (Maps, analytics, publishable
  payment keys), never for server passwords or private keys.
- `env` and `env_file` are different: `env` values live in
  `flavorpilot.yaml` and become fields on `AppFlavor`; `env_file` values stay
  in your `.env` files and are read with `String.fromEnvironment`.

## Android signing keys

Every Android app must be signed to be installed. Flutter signs builds with a
**debug key** that is different on every computer, so:

- testers can't update an app built on another computer (they must uninstall
  it first), and
- Google Play rejects it.

flavorpilot sets up **your own key** so every release build is signed the same
way, on every computer and in CI.

**1. Create the key:**

```sh
flavorpilot signing
```

```text
Key password (at least 6 characters):
Repeat the password:
Your name or company (stored in the key) [My app]:
✓ Release builds of every flavor are now signed with this key.
```

This creates two files and keeps them out of Git:

| File | What it is |
| --- | --- |
| `android/keys/upload.jks` | The key itself. |
| `android/keys/upload.properties` | Its passwords and alias. |

It needs Java's `keytool`, which comes with Android Studio; flavorpilot finds
it there, in `JAVA_HOME`, or on your `PATH`. Already have a key? Use
`flavorpilot signing --keystore path/to/key.jks` instead.

**2. Build as usual:**

```sh
flavorpilot release prod --target appbundle    # signed with your key
```

Debug builds (`flavorpilot run dev`) keep using the debug key, as before.

> ⚠️ **Back up `android/keys/`** (the key and its password) somewhere safe,
> outside the project, like a password manager. If you lose the key, you may
> not be able to update your app on Google Play.

### One key for every flavor, or one per flavor

One key for every flavor is the simplest choice and fine for most apps: each
flavor has its own app id, so the stores treat them as separate apps anyway.
To give a flavor its own key, for example to keep the production key with
fewer people:

```sh
flavorpilot signing prod
```

`flavorpilot.yaml` then looks like this:

```yaml
android_signing: "android/keys/upload.properties"      # every flavor
flavors:
  production:
    android_signing: "android/keys/production.properties"  # this one only
```

### Teammates and CI

Everyone who builds releases needs the same files in `android/keys/`. Share
them privately, never through Git. In CI, write them from your CI secrets
before building:

```sh
mkdir -p android/keys
echo "$UPLOAD_KEYSTORE_BASE64" | base64 --decode > android/keys/upload.jks
echo "$UPLOAD_PROPERTIES" > android/keys/upload.properties
flavorpilot release prod --target appbundle
```

Without the files, debug builds and plain `flutter build` still work (they use
the debug key), but `flavorpilot release` stops with a clear message, so an
unsigned build never reaches the store by mistake.

### Good to know

- Passwords can't contain `\` or start or end with a space, so every tool
  reads them the same way.
- The `.properties` file uses Flutter's usual `key.properties` format.
  `storeFile` is relative to the `.properties` file.
- To make it work, flavorpilot adds a short marked block at the **end** of
  `android/app/build.gradle(.kts)`. It stops the release build type from
  forcing the debug key, which Flutter's template does and which would win
  over a flavor's key.

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
| `android_signing` (top level) | No | Signing key of every flavor's Android release builds. See [Android signing keys](#android-signing-keys). |
| `flavors` | Yes | One entry per flavor. The key is the flavor name used by `--flavor`. |
| `alias` | No | Short name for commands. Must be unique across all names and aliases. |
| `app_name` | No | Name on the device. Defaults to the flavor name. |
| `android_id` | No | Android `applicationId`. Defaults to the project's own id. |
| `ios_bundle_id` | No | iOS bundle identifier. Defaults to the project's own id. |
| `icon` | No | Path to the flavor's icon. See [Icons per flavor](#icons-per-flavor). |
| `env` | No | Custom settings for the flavor. See [Settings per flavor](#settings-per-flavor-env). |
| `env_file` | No | Path of the flavor's `.env` file, e.g. `.env.development`. See [`.env` files per flavor](#env-files-per-flavor). |
| `android_signing` | No | This flavor's own signing key, instead of the top-level one. See [Android signing keys](#android-signing-keys). |

Rules: flavor names start with a lowercase letter and contain only letters
and digits; no name or alias can appear twice. See
[example/flavorpilot.yaml](example/flavorpilot.yaml) for a full example.

## Common tasks

### Change an app name or id

1. Edit the value in `flavorpilot.yaml`.
2. Run `flavorpilot sync`.

### Remove a flavor

```sh
flavorpilot remove qa
```

See [`remove`](#remove-remove-a-flavor). Then search your code for
`AppFlavor.<flavor>` and update it.

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

Use `--bump none` if your CI sets the version itself. If you use a signing key,
write its files first; see [Teammates and CI](#teammates-and-ci).

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
- **Never replaces or deletes a signing key**, not even with `remove`.
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
| `Can't sign "…": … was not found` | The flavor's signing key files are missing on this computer. Copy them from your team into `android/keys/`, or see [Android signing keys](#android-signing-keys). |
| `"…" will be signed with the debug key` (warning) | A release `build` can't find the key, so Gradle uses the debug key. Fine for testing; Google Play rejects it. |
| `keytool … was not found` | Install Android Studio or a JDK, or set `JAVA_HOME`. |
| `Unsupported version "…" in pubspec.yaml` | `release` needs a version like `1.2.3+4` in `pubspec.yaml`. |
| `env key "…" is missing from: …` | Every flavor needs the same `env` keys. Add the key to the flavors listed. |
| `env key "…" has different types across flavors` | Use the same type in every flavor. Check for a number or `true` written in quotes. |
| `.env.… was not found (the env_file of "…")` | The flavor's `.env` file is missing. Run `flavorpilot sync` to create it, then add your values. |
| `Flavor "…": icon "…" was not found` | Fix the path in `flavorpilot.yaml`. It's relative to the project root. |
| `Flavor "…": icon "…" is …×…` | The icon must be square and at least 1024×1024. |
| `… already has … icons that were not created by flavorpilot` | The flavor has hand-made icons. Delete them, or remove `icon` from the flavor. |
| App throws `Unknown flavor "null"` at startup | The app was started without a flavor. Use `flavorpilot run <flavor>` or one of the IDE run configurations. |
| `doctor` lists files as out of date | A file was edited by hand or `flavorpilot.yaml` changed. Run `flavorpilot sync`, then review with `git diff`. |
| `These env values are still examples: …` (warning) | Replace the `example.com` URLs in `flavorpilot.yaml` with your real ones, then run `flavorpilot sync`. |
| iOS build can't find Pods settings | Run `cd ios && pod install`. If `ios/Podfile` was created after `init`, run `flavorpilot sync` first. |

### Exit codes

| Code | Meaning |
| --- | --- |
| `0` | Success. |
| `1` | A known problem (see the message), or `doctor` found issues. |
| `64` | Wrong usage, e.g. a missing flavor name. The command's help is printed. |
| other | `run`, `build` and `release` return Flutter's own exit code when Flutter fails. |
