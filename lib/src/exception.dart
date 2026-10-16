/// Error codes returned by Rivium Auth, plus [networkError] and [unknown]
/// which the SDK uses when there is no answer from the server.
///
/// Localize your messages from the code; [RiviumAuthException.message] is an
/// English hint for developers.
abstract final class RiviumAuthErrorCode {
  static const invalidInput = 'INVALID_INPUT';
  static const invalidApiKey = 'INVALID_API_KEY';
  static const methodDisabled = 'METHOD_DISABLED';
  static const invalidCredentials = 'INVALID_CREDENTIALS';
  static const emailTaken = 'EMAIL_TAKEN';
  static const emailNotVerified = 'EMAIL_NOT_VERIFIED';
  static const weakPassword = 'WEAK_PASSWORD';
  static const invalidIdToken = 'INVALID_ID_TOKEN';
  static const nonceReused = 'NONCE_REUSED';
  static const providerAlreadyLinked = 'PROVIDER_ALREADY_LINKED';
  static const tokenInvalid = 'TOKEN_INVALID';
  static const sessionExpired = 'SESSION_EXPIRED';
  static const sessionRevoked = 'SESSION_REVOKED';
  static const userDisabled = 'USER_DISABLED';
  static const unauthenticated = 'UNAUTHENTICATED';
  static const rateLimited = 'RATE_LIMITED';
  static const limitReached = 'LIMIT_REACHED';

  /// Rivium Auth is turned off for this project in the Console.
  static const productDisabled = 'PRODUCT_DISABLED';

  /// The project's plan reached its monthly active user limit.
  static const mauLimit = 'MAU_LIMIT';
  static const notConfigured = 'NOT_CONFIGURED';
  static const internal = 'INTERNAL';

  /// No answer from the server (offline, timeout, DNS). The session is kept.
  static const networkError = 'NETWORK_ERROR';

  /// The server answered with something the SDK could not read.
  static const unknown = 'UNKNOWN';
}

/// Every error thrown by the SDK.
class RiviumAuthException implements Exception {
  RiviumAuthException(
    this.code,
    this.message, {
    this.statusCode,
    this.retryAfter,
    this.details = const {},
    this.cause,
  });

  /// One of [RiviumAuthErrorCode].
  final String code;

  /// English hint for developers. Do not show it to users as is.
  final String message;

  /// HTTP status, or null when the server was not reached.
  final int? statusCode;

  /// For [RiviumAuthErrorCode.rateLimited]: how long to wait before retrying.
  final Duration? retryAfter;

  /// Extra fields from the server, for example `fields` on `INVALID_INPUT`.
  final Map<String, dynamic> details;

  /// The underlying error for [RiviumAuthErrorCode.networkError].
  final Object? cause;

  /// True when the server could not be reached; nothing changed on the device.
  bool get isNetworkError => code == RiviumAuthErrorCode.networkError;

  /// True when the session ended for good and the user must sign in again.
  bool get isSessionEnded =>
      code == RiviumAuthErrorCode.sessionRevoked ||
      code == RiviumAuthErrorCode.sessionExpired ||
      code == RiviumAuthErrorCode.tokenInvalid ||
      code == RiviumAuthErrorCode.userDisabled;

  @override
  String toString() => 'RiviumAuthException($code): $message';
}
