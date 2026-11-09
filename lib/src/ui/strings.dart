import '../exception.dart';

/// The sign-in screens' texts: English, and each language in [_languages].
class RiviumSignInStrings {
  const RiviumSignInStrings._(this.languageCode, this._t, this.rtl);

  /// The language whose texts are shown: one the screens have (see
  /// [_languages]), English for any other.
  final String languageCode;
  final Map<String, String> _t;

  /// Whether the language reads right to left.
  final bool rtl;

  /// The languages of the screens, by the part of a language code before "-"
  /// or "_" ("en-US" → "en").
  static const _languages = <String, RiviumSignInStrings>{
    'en': RiviumSignInStrings._('en', _en, false),
  };

  /// The texts of [languageCode] when the screens have them, English for
  /// everything else.
  static RiviumSignInStrings of(String? languageCode) {
    final code =
        (languageCode ?? '').trim().toLowerCase().split(RegExp('[-_]')).first;
    return _languages[code] ?? _languages['en']!;
  }

  String operator [](String key) => _t[key] ?? _en[key] ?? key;

  /// The user-facing message for an error code.
  String error(String code) => this['error.$code'] == 'error.$code'
      ? this['error.other']
      : this['error.$code'];

  static const _en = <String, String>{
    'title': 'Sign in',
    'titleTo': 'Sign in to {app}',
    'signUpTitle': 'Create an account',
    'forgotTitle': 'Reset your password',
    'magicTitle': 'Sign in with a link',
    'telegramTitle': 'Sign in with Telegram',
    'email': 'E-mail',
    'password': 'Password',
    'phone': 'Phone number',
    'phoneHint': '+98 912 345 6789',
    'code': 'Code',
    'signIn': 'Sign in',
    'signUp': 'Create account',
    'noAccount': 'No account? Create one',
    'haveAccount': 'Have an account? Sign in',
    'forgot': 'Forgot password?',
    'sendReset': 'Send reset link',
    'sendLink': 'Send sign-in link',
    'sendCode': 'Send code',
    'verify': 'Verify',
    'or': 'or',
    'withEmailLink': 'E-mail me a sign-in link',
    'withTelegram': 'Continue with Telegram',
    'withGoogle': 'Continue with Google',
    'withApple': 'Continue with Apple',
    'guest': 'Continue as guest',
    'back': 'Back',
    'close': 'Close',
    'retry': 'Try again',
    'checkEmail': 'Check your e-mail',
    'resetSent':
        'If {email} has an account, a link to choose a new password is on its way.',
    'linkSent': 'We sent a sign-in link to {email}. Open it on this device.',
    'verifySent':
        'We sent a confirmation link to {email}. Confirm your e-mail, then sign in.',
    'codeSent': 'Enter the code Telegram sent you.',
    'botFirst':
        'Open {bot} in Telegram once and share your phone number, then try again.',
    'noMethods': 'Sign-in is not available right now.',
    'required': 'Required',
    'badEmail': 'Enter a valid e-mail',
    'error.INVALID_CREDENTIALS': 'Wrong e-mail or password.',
    'error.EMAIL_TAKEN': 'This e-mail already has an account. Sign in instead.',
    'error.EMAIL_NOT_VERIFIED': 'Confirm your e-mail first. Check your inbox.',
    'error.WEAK_PASSWORD': 'Choose a longer password that is not a common one.',
    'error.INVALID_INPUT': 'Check what you entered.',
    'error.TOKEN_INVALID': 'This code is wrong or has expired.',
    'error.RATE_LIMITED': 'Too many tries. Wait a little and try again.',
    'error.USER_DISABLED': 'This account is disabled.',
    'error.METHOD_DISABLED': 'This sign-in method is turned off.',
    'error.PRODUCT_DISABLED': 'Sign-in is not available right now.',
    'error.MAU_LIMIT': 'Sign-in is not available right now.',
    'error.NETWORK_ERROR': 'No connection. Check your internet and try again.',
    'error.PROVIDER_ALREADY_LINKED': 'This account is linked to another user.',
    'error.INVALID_ID_TOKEN': 'Sign-in could not be confirmed. Try again.',
    'error.VERIFY_NOT_SENT':
        'Your account was created, but the confirmation e-mail could not be sent. Try again later with “Forgot password?”.',
    'error.other': 'Something went wrong. Try again.',
  };

}

/// The error code of [e], [RiviumAuthErrorCode.unknown] for anything else.
String errorCodeOf(Object e) =>
    e is RiviumAuthException ? e.code : RiviumAuthErrorCode.unknown;
