/// The app's version, read from `pubspec.yaml` when it is built (`--dart-define=APP_VERSION`). A build
/// that doesn't pass it says so instead of showing a wrong number.
const appVersion = String.fromEnvironment(
  'APP_VERSION',
  defaultValue: 'sin definir',
);
