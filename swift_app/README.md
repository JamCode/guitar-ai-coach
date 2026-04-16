# Swift Migration Project Skeleton

This directory holds the Swift Package used by the native iOS app (`swift_ios_host/`).

## Structure

- `Sources/App`: App entry, lifecycle, navigation bootstrap
- `Sources/Core`: Shared infrastructure (networking, storage, constants, utils)
- `Sources/Features/*`: Feature modules (historically aligned with former Flutter `lib/*` areas)
- `Resources/Assets`: Static assets (images/icons)
- `Resources/Audio`: Audio resources (for later migration from Flutter assets)
- `Tests/Unit`: Unit tests
- `Tests/Integration`: API/integration tests
- `Tests/UI`: UI/E2E tests
- `Scripts`: Build/dev helper scripts
- `Docs`: Swift-side migration docs

## Feature Mapping (from Flutter)

- `audio` -> `Sources/Features/Audio`
- `auth` -> `Sources/Features/Auth`
- `chords` -> `Sources/Features/Chords`
- `chords_live` -> `Sources/Features/ChordsLive`
- `config` -> `Sources/Features/Config`
- `diagnostics` -> `Sources/Features/Diagnostics`
- `ear` -> `Sources/Features/Ear`
- `practice` -> `Sources/Features/Practice`
- `profile` -> `Sources/Features/Profile`
- `settings` -> `Sources/Features/Settings`
- `sheets` -> `Sources/Features/Sheets`
- `shell` -> `Sources/Features/Shell`
- `tools` -> `Sources/Features/Tools`
- `tuner` -> `Sources/Features/Tuner`

