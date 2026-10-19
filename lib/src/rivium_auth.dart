import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'exception.dart';
import 'models.dart';
import 'storage.dart';
import 'version.dart';

/// Returns the signed-in user's Rivium user token, or null when no one is
/// signed in. The type the other Rivium SDKs accept as `tokenProvider`.
typedef RiviumAuthTokenProvider = Future<String?> Function();

/// Rivium Auth for Flutter: signs your app's users in and keeps their session.
///
/// ```dart
/// await RiviumAuth.initialize('rv_live_xxx');
/// await RiviumAuth.instance.signInAnonymously();
/// ```
class RiviumAuth {
  RiviumAuth._({
    required String apiKey,
    required String baseUrl,
    required Duration timeout,
    required Duration refreshMargin,
    required http.Client httpClient,
    required bool ownsHttp,
    required RiviumAuthStorage storage,
    required DateTime Function() clock,
  })  : _apiKey = apiKey,
        _baseUrl = baseUrl.endsWith('/')
            ? baseUrl.substring(0, baseUrl.length - 1)
            : baseUrl,
        _timeout = timeout,
        _refreshMargin = refreshMargin,
        _http = httpClient,
        _ownsHttp = ownsHttp,
        _storage = storage,
        _now = clock,
        _keyPrefix =
            'rivium_auth.${sha256.convert(utf8.encode(apiKey)).toString().substring(0, 12)}';

  static const defaultBaseUrl = 'https://auth-users.rivium.co';

  static RiviumAuth? _instance;

  /// The client created by [initialize]. Throws if [initialize] was not called.
  static RiviumAuth get instance {
    final i = _instance;
    if (i == null) {
      throw StateError('RiviumAuth.initialize() must be called first.');
    }
    return i;
  }

  /// Creates the shared client ([instance]) and restores the session saved on
  /// the device. Makes no network request.
  ///
  /// [apiKey] is the project's public key (`rv_live_...`).
  static Future<RiviumAuth> initialize(
    String apiKey, {
    String? baseUrl,
    Duration timeout = const Duration(seconds: 15),
    Duration refreshMargin = const Duration(minutes: 2),
    http.Client? httpClient,
    RiviumAuthStorage? storage,
    @visibleForTesting DateTime Function()? clock,
  }) async {
    final auth = await create(
      apiKey,
      baseUrl: baseUrl,
      timeout: timeout,
      refreshMargin: refreshMargin,
      httpClient: httpClient,
      storage: storage,
      clock: clock,
    );
    final previous = _instance;
    _instance = auth;
    previous?.dispose();
    return auth;
  }

  /// Like [initialize] but does not touch [instance].
  static Future<RiviumAuth> create(
    String apiKey, {
    String? baseUrl,
    Duration timeout = const Duration(seconds: 15),
    Duration refreshMargin = const Duration(minutes: 2),
    http.Client? httpClient,
    RiviumAuthStorage? storage,
    @visibleForTesting DateTime Function()? clock,
  }) async {
    if (apiKey.trim().isEmpty) {
      throw ArgumentError.value(apiKey, 'apiKey', 'must not be empty');
    }
    final auth = RiviumAuth._(
      apiKey: apiKey.trim(),
      baseUrl: baseUrl ?? defaultBaseUrl,
      timeout: timeout,
      refreshMargin: refreshMargin,
      httpClient: httpClient ?? http.Client(),
      ownsHttp: httpClient == null,
      storage: storage ?? SecureRiviumAuthStorage(),
      clock: clock ?? DateTime.now,
    );
    await auth._restore();
    return auth;
  }

  final String _apiKey;
  final String _baseUrl;
  final Duration _timeout;
  final Duration _refreshMargin;
  final http.Client _http;
  final bool _ownsHttp;
  final RiviumAuthStorage _storage;
  final DateTime Function() _now;
  final String _keyPrefix;

  final _changes = StreamController<RiviumAuthUser?>.broadcast();

  String? _refreshToken;
  String? _accessToken;
  DateTime? _accessExpiresAt;
  Duration _accessLifetime = const Duration(hours: 1);
  RiviumAuthUser? _user;

  /// Bumped whenever the session is replaced or cleared, so a refresh that
  /// finishes late never overwrites a newer session.
  int _generation = 0;
  Future<String?>? _refreshing;

  String get _refreshKey => '$_keyPrefix.refresh';
  String get _userKey => '$_keyPrefix.user';

  // ── State ───────────────────────────────────────────────────────────────

  /// The signed-in user, or null. Available right after [initialize].
  RiviumAuthUser? get currentUser => _user;

  bool get isSignedIn => _refreshToken != null;

  /// Emits the current user when listened to, then every time a user signs
  /// in, signs out or the user's profile changes (for example after linking).
  Stream<RiviumAuthUser?> get authStateChanges {
    late final StreamController<RiviumAuthUser?> c;
    StreamSubscription<RiviumAuthUser?>? sub;
    c = StreamController<RiviumAuthUser?>(
      onListen: () {
        c.add(_user);
        sub = _changes.stream.listen(c.add, onDone: c.close);
      },
      onCancel: () => sub?.cancel(),
    );
    return c.stream;
  }

  // ── Tokens ──────────────────────────────────────────────────────────────

  /// Pass this to the other Rivium SDKs:
  /// `RiviumSyncConfig(apiKey: ..., tokenProvider: RiviumAuth.instance.tokenProvider)`.
  RiviumAuthTokenProvider get tokenProvider => getToken;

  /// For Rivium Chat, whose provider must return a token: throws
  /// [RiviumAuthException] (`UNAUTHENTICATED`) when no one is signed in.
  Future<String> Function() get chatTokenProvider => () async {
        final token = await getToken();
        if (token == null) {
          throw RiviumAuthException(
              RiviumAuthErrorCode.unauthenticated, 'No user is signed in');
        }
        return token;
      };

  /// The signed-in user's access token (a 1-hour Rivium user token), renewed
  /// shortly before it expires. Null when no one is signed in or the session
  /// ended. Concurrent callers share one renewal request.
  ///
  /// Throws [RiviumAuthException] when the token could not be renewed for a
  /// temporary reason (offline, rate limited); the session is kept.
  Future<String?> getToken({bool forceRefresh = false}) async {
    if (_refreshToken == null) return null;
    if (!forceRefresh && _accessUsable(_effectiveMargin)) return _accessToken;
    return _refresh();
  }

  Duration get _effectiveMargin {
    final half = _accessLifetime ~/ 2;
    return _refreshMargin < half ? _refreshMargin : half;
  }

  bool _accessUsable(Duration margin) {
    final exp = _accessExpiresAt;
    return _accessToken != null &&
        exp != null &&
        _now().add(margin).isBefore(exp);
  }

  Future<String?> _refresh() {
    final running = _refreshing;
    if (running != null) return running;
    late final Future<String?> f;
    f = _runRefresh().whenComplete(() {
      if (identical(_refreshing, f)) _refreshing = null;
    });
    _refreshing = f;
    return f;
  }

  Future<String?> _runRefresh() async {
    final generation = _generation;
    final refreshToken = _refreshToken;
    if (refreshToken == null) return null;
    final Map<String, dynamic> json;
    try {
      json = _asMap(await _send('POST', '/v1/token/refresh',
          body: {'refreshToken': refreshToken}));
    } on RiviumAuthException catch (e) {
      if (generation != _generation) return getToken();
      if (e.isSessionEnded) {
        await _clear();
        return null;
      }
      // Temporary failure: keep the session; the current token may still work.
      if (_accessUsable(Duration.zero)) return _accessToken;
      rethrow;
    }
    final tokens = _Tokens.parse(json);
    if (generation != _generation) {
      // Signed out or signed in again meanwhile: this rotated token belongs to
      // a session nobody uses any more.
      unawaited(_revoke(tokens.refreshToken));
      return getToken();
    }
    _applyTokens(tokens);
    await _safeWrite(_refreshKey, tokens.refreshToken);
    return tokens.accessToken;
  }

  void _applyTokens(_Tokens t) {
    _refreshToken = t.refreshToken;
    _accessToken = t.accessToken;
    _accessLifetime = t.expiresIn;
    _accessExpiresAt = _now().add(t.expiresIn);
  }

  // ── Sign-in methods ─────────────────────────────────────────────────────

  /// Which sign-in methods the project offers. Empty when Rivium Auth is off.
  Future<RiviumAuthMethods> getMethods() async =>
      RiviumAuthMethods.fromJson(_asMap(await _send('GET', '/v1/methods')));

  /// Signs in as a new anonymous user. If an anonymous user is already signed
  /// in on this device, returns that user (no new account).
  Future<RiviumAuthUser> signInAnonymously() async {
    final current = _user;
    if (current != null && current.anonymous && isSignedIn) return current;
    final json = _asMap(await _send('POST', '/v1/anonymous'));
    final tokens = _Tokens.parse(json);
    return _startSession(tokens,
        known: RiviumAuthUser(
            id: tokens.userId, anonymous: true, createdAt: _now().toUtc()));
  }

  /// Signs in with an Apple ID token. [rawNonce] is the raw value whose
  /// [RiviumAuthNonce.sha256Hex] you gave Apple. [authorizationCode] lets
  /// Rivium revoke the Apple sign-in when the account is deleted; [name] is
  /// the name Apple returns on the first sign-in only.
  Future<RiviumAuthUser> signInWithApple({
    required String idToken,
    required String rawNonce,
    String? authorizationCode,
    String? name,
  }) =>
      _sessionCall('POST', '/v1/apple',
          _social(idToken, rawNonce, authorizationCode, name));

  /// Signs in with a Google ID token. [rawNonce] (16-256 characters) is the
  /// raw value whose [RiviumAuthNonce.sha256Hex] you gave Google; Rivium Auth
  /// rejects a Google sign-in without it.
  Future<RiviumAuthUser> signInWithGoogle({
    required String idToken,
    required String rawNonce,
  }) =>
      _sessionCall('POST', '/v1/google', _social(idToken, rawNonce, null, null));

  /// Adds Sign in with Apple to the signed-in user (typically anonymous); the
  /// user keeps its id. Throws [RiviumProviderAlreadyLinkedException] when
  /// this Apple account belongs to another user.
  Future<RiviumAuthUser> linkApple({
    required String idToken,
    required String rawNonce,
    String? authorizationCode,
    String? name,
  }) =>
      _sessionCall('POST', '/v1/link/apple',
          _social(idToken, rawNonce, authorizationCode, name),
          signedIn: true);

  /// Adds Sign in with Google to the signed-in user; the user keeps its id.
  /// Throws [RiviumProviderAlreadyLinkedException] when this Google account
  /// belongs to another user. [rawNonce] works as in [signInWithGoogle].
  Future<RiviumAuthUser> linkGoogle({
    required String idToken,
    required String rawNonce,
  }) =>
      _sessionCall('POST', '/v1/link/google',
          _social(idToken, rawNonce, null, null),
          signedIn: true);

  /// Gives the signed-in user (typically anonymous) an e-mail and password;
  /// the user keeps its id.
  Future<RiviumAuthUser> linkPassword({
    required String email,
    required String password,
  }) =>
      _sessionCall('POST', '/v1/link/password',
          {'email': email, 'password': password},
          signedIn: true);

  /// Creates an e-mail + password account. When the project requires a
  /// confirmed e-mail, the user is not signed in yet ([RiviumSignUpResult.user]
  /// is null). [redirectUrl] (one of the project's allowed redirect URLs)
  /// receives the confirmation link.
  Future<RiviumSignUpResult> signUpWithEmail({
    required String email,
    required String password,
    String? redirectUrl,
  }) async {
    final json = _asMap(await _send('POST', '/v1/password/sign-up', body: {
      'email': email,
      'password': password,
      if (redirectUrl != null) 'redirectUrl': redirectUrl,
    }));
    final session = json['session'];
    final user = session is Map<String, dynamic>
        ? await _startSession(_Tokens.parse(session))
        : null;
    return RiviumSignUpResult(
      userId: json['userId'] as String? ?? user?.id ?? '',
      verificationSent: json['verificationSent'] == true,
      user: user,
    );
  }

  Future<RiviumAuthUser> signInWithEmail({
    required String email,
    required String password,
  }) =>
      _sessionCall('POST', '/v1/password/sign-in',
          {'email': email, 'password': password});

  /// Sends a password reset link to [redirectUrl] + `?token=...`. Always
  /// succeeds, whether or not the address has an account.
  Future<void> sendPasswordReset(String email, {required String redirectUrl}) =>
      _send('POST', '/v1/password/forgot',
          body: {'email': email, 'redirectUrl': redirectUrl});

  /// Sets a new password with the token from the reset link. Ends every
  /// session of that user; it does not sign in.
  Future<void> resetPassword(String token, String newPassword) => _send(
      'POST', '/v1/password/reset',
      body: {'token': token, 'password': newPassword});

  /// Confirms the e-mail with the token from the confirmation link.
  Future<void> verifyEmail(String token) async {
    await _send('POST', '/v1/email/verify', body: {'token': token});
    if (isSignedIn) {
      try {
        await getMe();
      } on RiviumAuthException {
        // The profile updates on the next getMe().
      }
    }
  }

  /// Sends the signed-in user a new confirmation link.
  Future<void> sendEmailVerification({required String redirectUrl}) =>
      _authed('POST', '/v1/email/send-verification',
          body: {'redirectUrl': redirectUrl});

  /// E-mails a sign-in link to [redirectUrl] + `?token=...`. The account is
  /// created on first use.
  Future<void> sendMagicLink(String email, {required String redirectUrl}) =>
      _send('POST', '/v1/magic-link/send',
          body: {'email': email, 'redirectUrl': redirectUrl});

  /// Signs in with the token from a magic link.
  Future<RiviumAuthUser> signInWithMagicLink(String token) =>
      _sessionCall('POST', '/v1/magic-link/consume', {'token': token});

  /// Sends a 6-digit code to the user's Telegram. [phone] is in international
  /// format, for example `+37491234567`.
  Future<RiviumTelegramCodeResult> requestTelegramCode(String phone) async =>
      RiviumTelegramCodeResult.fromJson(_asMap(
          await _send('POST', '/v1/telegram/code', body: {'phone': phone})));

  Future<RiviumAuthUser> verifyTelegramCode(String phone, String code) =>
      _sessionCall(
          'POST', '/v1/telegram/verify', {'phone': phone, 'code': code});

  // ── Account ─────────────────────────────────────────────────────────────

  /// Loads the signed-in user from the server and updates [currentUser].
  Future<RiviumAuthUser> getMe() async {
    final user = RiviumAuthUser.fromJson(_asMap(await _authed('GET', '/v1/me')));
    await _setUser(user);
    return user;
  }

  /// Signs out on this device. Never fails: the session is cleared locally
  /// even when the server cannot be reached.
  Future<void> signOut() async {
    final refreshToken = _refreshToken;
    await _clear();
    if (refreshToken != null) await _revoke(refreshToken);
  }

  /// Ends every session of the user, on all devices, then signs out here.
  Future<void> signOutEverywhere() async {
    await _authed('POST', '/v1/sign-out-everywhere');
    await _clear();
  }

  /// Deletes the user and all its data, then signs out.
  Future<void> deleteAccount() async {
    await _authed('DELETE', '/v1/me');
    await _clear();
  }

  /// Closes the client. [instance] stays set until the next [initialize].
  void dispose() {
    _changes.close();
    if (_ownsHttp) _http.close();
  }

  // ── Internals ───────────────────────────────────────────────────────────

  Map<String, dynamic> _social(
          String idToken, String rawNonce, String? code, String? name) =>
      {
        'idToken': idToken,
        'nonce': rawNonce,
        if (code != null) 'authorizationCode': code,
        if (name != null) 'name': name,
      };

  Future<RiviumAuthUser> _sessionCall(
      String method, String path, Map<String, dynamic> body,
      {bool signedIn = false}) async {
    final res = signedIn
        ? await _authed(method, path, body: body)
        : await _send(method, path, body: body);
    return _startSession(_Tokens.parse(_asMap(res)));
  }

  /// Makes [t] the session, saves it, loads the user, and ends the session it
  /// replaces on the server.
  Future<RiviumAuthUser> _startSession(_Tokens t, {RiviumAuthUser? known}) async {
    final previous = _refreshToken;
    _generation++;
    _refreshing = null;
    _applyTokens(t);
    await _safeWrite(_refreshKey, t.refreshToken);
    final user = known ??
        await _fetchUser(t.accessToken) ??
        (_user?.id == t.userId ? _user! : RiviumAuthUser(id: t.userId));
    await _setUser(user);
    if (previous != null && previous != t.refreshToken) {
      unawaited(_revoke(previous));
    }
    return user;
  }

  Future<RiviumAuthUser?> _fetchUser(String accessToken) async {
    try {
      return RiviumAuthUser.fromJson(
          _asMap(await _send('GET', '/v1/me', bearer: accessToken)));
    } on RiviumAuthException {
      return null;
    }
  }

  Future<void> _setUser(RiviumAuthUser? user) async {
    final changed = user != _user;
    _user = user;
    if (user == null) {
      await _safeDelete(_userKey);
    } else {
      await _safeWrite(_userKey, jsonEncode(user.toJson()));
    }
    if (changed && !_changes.isClosed) _changes.add(user);
  }

  Future<void> _clear() async {
    _generation++;
    _refreshing = null;
    _refreshToken = null;
    _accessToken = null;
    _accessExpiresAt = null;
    await _safeDelete(_refreshKey);
    await _setUser(null);
  }

  Future<void> _restore() async {
    try {
      final refresh = await _storage.read(_refreshKey);
      final userJson = await _storage.read(_userKey);
      if (refresh == null || userJson == null) {
        if (refresh != null || userJson != null) {
          await _safeDelete(_refreshKey);
          await _safeDelete(_userKey);
        }
        return;
      }
      _refreshToken = refresh;
      _user = RiviumAuthUser.fromJson(
          jsonDecode(userJson) as Map<String, dynamic>);
    } catch (e) {
      // Unreadable storage (for example after a backup restore to a new
      // device): start signed out.
      debugPrint('RiviumAuth: saved session could not be read ($e)');
      _refreshToken = null;
      _user = null;
    }
  }

  /// Best effort: ends the session [refreshToken] belongs to.
  Future<void> _revoke(String refreshToken) async {
    try {
      await _send('POST', '/v1/sign-out', body: {'refreshToken': refreshToken});
    } on RiviumAuthException {
      // Sign-out never fails for the app; the session expires on its own.
    }
  }

  Future<void> _safeWrite(String key, String value) async {
    try {
      await _storage.write(key, value);
    } catch (e) {
      // Kept in memory for this run; the user signs in again next launch.
      debugPrint('RiviumAuth: could not save the session ($e)');
    }
  }

  Future<void> _safeDelete(String key) async {
    try {
      await _storage.delete(key);
    } catch (e) {
      debugPrint('RiviumAuth: could not clear the saved session ($e)');
    }
  }

  /// A request with the user's access token. Retries once with a renewed
  /// token when the server refuses the token.
  Future<dynamic> _authed(String method, String path,
      {Map<String, dynamic>? body}) async {
    for (var attempt = 0;; attempt++) {
      final token = await getToken(forceRefresh: attempt > 0);
      if (token == null) {
        throw RiviumAuthException(
            RiviumAuthErrorCode.unauthenticated, 'No user is signed in');
      }
      try {
        return await _send(method, path, body: body, bearer: token);
      } on RiviumAuthException catch (e) {
        if (attempt == 0 &&
            e.statusCode == 401 &&
            e.code == RiviumAuthErrorCode.unauthenticated) {
          continue;
        }
        if (e.code == RiviumAuthErrorCode.userDisabled) await _clear();
        rethrow;
      }
    }
  }

  Future<dynamic> _send(String method, String path,
      {Map<String, dynamic>? body, String? bearer}) async {
    final req = http.Request(method, Uri.parse('$_baseUrl$path'))
      ..headers['x-api-key'] = _apiKey
      ..headers['x-rivium-sdk'] = riviumAuthSdkHeader
      ..headers['accept'] = 'application/json';
    if (bearer != null) req.headers['authorization'] = 'Bearer $bearer';
    if (body != null) {
      req.headers['content-type'] = 'application/json';
      req.body = jsonEncode(body);
    }

    final int status;
    final String text;
    final Map<String, String> headers;
    try {
      final res = await _http.send(req).timeout(_timeout);
      text = await res.stream.bytesToString().timeout(_timeout);
      status = res.statusCode;
      headers = res.headers;
    } catch (e) {
      throw RiviumAuthException(RiviumAuthErrorCode.networkError,
          'Rivium Auth could not be reached',
          cause: e);
    }

    dynamic decoded;
    if (text.isNotEmpty) {
      try {
        decoded = jsonDecode(text);
      } on FormatException {
        decoded = null;
      }
    }
    if (status >= 200 && status < 300) return decoded;
    throw _errorFrom(status, decoded, headers);
  }

  static RiviumAuthException _errorFrom(
      int status, dynamic body, Map<String, String> headers) {
    final map = body is Map<String, dynamic> ? body : const <String, dynamic>{};
    final code = map['code'] is String
        ? map['code'] as String
        : status == 429
            ? RiviumAuthErrorCode.rateLimited
            : RiviumAuthErrorCode.unknown;
    final message = map['message'] is String
        ? map['message'] as String
        : 'Request failed ($status)';
    final details = Map<String, dynamic>.of(map)
      ..remove('code')
      ..remove('message');
    Duration? retryAfter;
    final sec = map['retryAfterSec'] is num
        ? (map['retryAfterSec'] as num).toInt()
        : int.tryParse(headers['retry-after'] ?? '');
    if (sec != null) retryAfter = Duration(seconds: sec);

    if (code == RiviumAuthErrorCode.providerAlreadyLinked) {
      return RiviumProviderAlreadyLinkedException(message,
          statusCode: status, details: details);
    }
    return RiviumAuthException(code, message,
        statusCode: status, retryAfter: retryAfter, details: details);
  }

  static Map<String, dynamic> _asMap(dynamic v) {
    if (v is Map<String, dynamic>) return v;
    throw RiviumAuthException(
        RiviumAuthErrorCode.unknown, 'Unexpected answer from Rivium Auth');
  }
}

/// The Apple or Google account is already the sign-in of another user, so it
/// cannot be linked. Offer to sign in with it instead (the current anonymous
/// user's data stays with the current user).
class RiviumProviderAlreadyLinkedException extends RiviumAuthException {
  RiviumProviderAlreadyLinkedException(String message,
      {super.statusCode, super.details})
      : super(RiviumAuthErrorCode.providerAlreadyLinked, message);
}

class _Tokens {
  _Tokens(this.accessToken, this.expiresIn, this.refreshToken, this.userId);

  final String accessToken;
  final Duration expiresIn;
  final String refreshToken;
  final String userId;

  static _Tokens parse(Map<String, dynamic> json) {
    final access = json['accessToken'];
    final refresh = json['refreshToken'];
    final userId = json['userId'];
    final expiresIn = json['expiresIn'];
    if (access is! String ||
        refresh is! String ||
        userId is! String ||
        expiresIn is! num) {
      throw RiviumAuthException(
          RiviumAuthErrorCode.unknown, 'Unexpected session from Rivium Auth');
    }
    return _Tokens(access, Duration(seconds: expiresIn.toInt()), refresh, userId);
  }
}
