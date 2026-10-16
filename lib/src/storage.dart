import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Where the SDK keeps the session between app launches. The default is the
/// platform's secure storage (Keychain on iOS, Keystore-backed on Android).
///
/// Only the refresh token and the cached user are stored; the access token
/// stays in memory.
abstract class RiviumAuthStorage {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

/// [RiviumAuthStorage] on `flutter_secure_storage`.
class SecureRiviumAuthStorage implements RiviumAuthStorage {
  SecureRiviumAuthStorage([FlutterSecureStorage? storage])
      : _storage = storage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(encryptedSharedPreferences: true),
              iOptions: IOSOptions(
                accessibility: KeychainAccessibility.first_unlock_this_device,
              ),
            );

  final FlutterSecureStorage _storage;

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);

  @override
  Future<void> delete(String key) => _storage.delete(key: key);
}

/// Keeps the session in memory only (lost when the app closes). For tests.
class MemoryRiviumAuthStorage implements RiviumAuthStorage {
  final Map<String, String> values = {};

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async => values[key] = value;

  @override
  Future<void> delete(String key) async => values.remove(key);
}
