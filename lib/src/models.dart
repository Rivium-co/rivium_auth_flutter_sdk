import 'dart:convert';

/// A signed-in user of your app.
class RiviumAuthUser {
  const RiviumAuthUser({
    required this.id,
    this.anonymous = false,
    this.emailVerified = false,
    this.createdAt,
    this.providers = const [],
  });

  /// Stable user id. Use it as the user id in the other Rivium SDKs.
  final String id;

  /// True for a user from [RiviumAuth.signInAnonymously] that has not linked
  /// a sign-in method yet.
  final bool anonymous;
  final bool emailVerified;
  final DateTime? createdAt;

  /// Linked sign-in methods: `apple`, `google`, `password`, `telegram`, ...
  final List<String> providers;

  factory RiviumAuthUser.fromJson(Map<String, dynamic> json) => RiviumAuthUser(
        id: json['id'] as String,
        anonymous: json['anonymous'] == true,
        emailVerified: json['emailVerified'] == true,
        createdAt: json['createdAt'] is String
            ? DateTime.tryParse(json['createdAt'] as String)
            : null,
        providers: (json['providers'] as List?)?.whereType<String>().toList() ??
            const [],
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'anonymous': anonymous,
        'emailVerified': emailVerified,
        if (createdAt != null)
          'createdAt': createdAt!.toUtc().toIso8601String(),
        'providers': providers,
      };

  @override
  bool operator ==(Object other) =>
      other is RiviumAuthUser &&
      other.id == id &&
      other.anonymous == anonymous &&
      other.emailVerified == emailVerified &&
      other.createdAt == createdAt &&
      _sameList(other.providers, providers);

  @override
  int get hashCode => Object.hash(
      id, anonymous, emailVerified, createdAt, Object.hashAll(providers));

  @override
  String toString() => 'RiviumAuthUser($id, anonymous: $anonymous)';
}

bool _sameList(List<String> a, List<String> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// The sign-in methods this project offers (turned on in the Console).
class RiviumAuthMethods {
  const RiviumAuthMethods({required this.methods, this.telegramBot});

  /// Any of `anonymous`, `apple`, `google`, `password`, `magicLink`, `telegram`.
  /// Empty when Rivium Auth is off for the project.
  final List<String> methods;

  /// The project's Telegram bot username, when Telegram sign-in is on.
  final String? telegramBot;

  bool get anonymous => methods.contains('anonymous');
  bool get apple => methods.contains('apple');
  bool get google => methods.contains('google');
  bool get password => methods.contains('password');
  bool get magicLink => methods.contains('magicLink');
  bool get telegram => methods.contains('telegram');

  factory RiviumAuthMethods.fromJson(Map<String, dynamic> json) =>
      RiviumAuthMethods(
        methods: (json['methods'] as List?)?.whereType<String>().toList() ??
            const [],
        telegramBot: json['telegramBot'] as String?,
      );
}

/// Result of [RiviumAuth.signUpWithEmail].
class RiviumSignUpResult {
  const RiviumSignUpResult({
    required this.userId,
    required this.verificationSent,
    this.user,
  });

  final String userId;

  /// A confirmation e-mail was sent.
  final bool verificationSent;

  /// The signed-in user, or null when the project requires a confirmed e-mail
  /// before the first sign-in.
  final RiviumAuthUser? user;

  bool get signedIn => user != null;
}

/// Result of [RiviumAuth.requestTelegramCode].
class RiviumTelegramCodeResult {
  const RiviumTelegramCodeResult({
    required this.sent,
    required this.expiresIn,
    this.botUrl,
  });

  /// The code was sent to the user's Telegram.
  final bool sent;

  /// When [sent] is false: the user must open this bot link once and share
  /// their phone number; then call [RiviumAuth.requestTelegramCode] again.
  final String? botUrl;

  /// How long the code stays valid.
  final Duration expiresIn;

  factory RiviumTelegramCodeResult.fromJson(Map<String, dynamic> json) =>
      RiviumTelegramCodeResult(
        sent: json['sent'] == true,
        botUrl: json['botUrl'] as String?,
        expiresIn: Duration(seconds: (json['expiresIn'] as num?)?.toInt() ?? 0),
      );
}

/// The access token with its decoded fields, like Firebase's `IdTokenResult`.
///
/// For display only (a "Pro" badge, unlocked lessons): the app can read the
/// token but never change it. Rivium's servers check the token on every
/// request and decide access with rules.
class RiviumTokenResult {
  const RiviumTokenResult({
    required this.token,
    required this.claims,
    required this.expirationTime,
    required this.issuedAtTime,
    required this.authTime,
    this.signInProvider,
  });

  /// The access token itself (the same one [RiviumAuth.getToken] gives).
  final String token;

  /// Every field of the token: `sub` (the user id), `pid`, `iss`, `aud`,
  /// `iat`, `exp`, `auth_time`, `amr`, and the custom claims your server set
  /// with `setCustomUserClaims` (for example `plan`, `role`).
  final Map<String, dynamic> claims;

  /// When this token expires (UTC).
  final DateTime expirationTime;

  /// When this token was issued (UTC).
  final DateTime issuedAtTime;

  /// When the user signed in: the session's start; a refresh doesn't change it.
  final DateTime authTime;

  /// How the user signed in: `anonymous`, `apple`, `google`, `password`,
  /// `magic_link`, `telegram`.
  final String? signInProvider;

  /// Reads a token; null when it isn't one Rivium signs.
  static RiviumTokenResult? fromToken(String token) {
    final parts = token.split('.');
    if (parts.length != 3) return null;
    Object? payload;
    try {
      payload = jsonDecode(
          utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))));
    } catch (_) {
      return null;
    }
    if (payload is! Map<String, dynamic>) return null;
    DateTime? at(Object? seconds) => seconds is num
        ? DateTime.fromMillisecondsSinceEpoch((seconds * 1000).round(),
            isUtc: true)
        : null;
    final exp = at(payload['exp']);
    final iat = at(payload['iat']);
    if (exp == null || iat == null) return null;
    // `meta` is Rivium's own bookkeeping for its servers, not a claim.
    final claims = Map<String, dynamic>.of(payload)..remove('meta');
    final amr = payload['amr'];
    return RiviumTokenResult(
      token: token,
      claims: claims,
      expirationTime: exp,
      issuedAtTime: iat,
      authTime: at(payload['auth_time']) ?? iat,
      signInProvider: amr is List && amr.isNotEmpty && amr.first is String
          ? amr.first as String
          : null,
    );
  }
}
