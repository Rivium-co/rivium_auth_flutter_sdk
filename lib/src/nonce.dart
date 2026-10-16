import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

/// Nonce for Sign in with Apple and Google.
///
/// Give the provider `sha256Hex(raw)` and give Rivium Auth the `raw` value.
/// Rivium checks they match and accepts each nonce once, so a captured ID
/// token cannot be replayed.
abstract final class RiviumAuthNonce {
  static const _charset =
      '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz-._';

  /// A new random raw nonce from a secure random source.
  /// [length] must be between 16 and 256.
  static String generate([int length = 32]) {
    if (length < 16 || length > 256) {
      throw ArgumentError.value(length, 'length', 'must be 16-256');
    }
    final random = Random.secure();
    return List.generate(length, (_) => _charset[random.nextInt(_charset.length)])
        .join();
  }

  /// Lowercase hex SHA-256 of [raw]: the value to pass to Apple or Google.
  static String sha256Hex(String raw) =>
      sha256.convert(utf8.encode(raw)).toString();
}
