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
