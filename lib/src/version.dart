/// The SDK version. Keep it equal to `version:` in pubspec.yaml — a test checks it.
const String riviumAuthSdkVersion = '0.1.1';

/// Sent as `X-Rivium-SDK` with every request, so Rivium can show which SDK versions are in use.
const String riviumAuthSdkHeader = 'auth-flutter/$riviumAuthSdkVersion';
