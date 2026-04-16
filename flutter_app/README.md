# guitar_helper

## Deprecated

`flutter_app/` is deprecated and temporarily out of use.

- Do not add new features in this directory for now.
- Do not treat this app as an active delivery target.
- Keep existing code for historical reference only.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Learn Flutter](https://docs.flutter.dev/get-started/learn-flutter)
- [Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Flutter learning resources](https://docs.flutter.dev/reference/learning-resources)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.

## API base URL config

- Do not hardcode API IP/domain in Dart files.
- Put environment values in a local json file (for example `env/dev.json`), based on `env/dev.json.example`.
- If no dart-define is provided, app uses bundled default: `http://47.110.78.65/api`.
- Run Flutter with dart-define file:

```bash
flutter run --dart-define-from-file=env/dev.json
```
