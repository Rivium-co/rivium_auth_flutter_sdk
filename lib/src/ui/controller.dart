import 'package:flutter/foundation.dart';

import '../rivium_auth.dart';
import '../exception.dart';
import '../models.dart';
import '../nonce.dart';
import 'options.dart';
import 'strings.dart';

/// The sign-in screens.
enum RiviumSignInView {
  loading,
  home,
  signUp,
  forgot,
  magicLink,
  telegramPhone,
  telegramCode,
  sent,
  unavailable,
}

/// Which e-mail the "check your e-mail" screen is about.
enum RiviumSentKind { reset, magicLink, verify }

/// The language the open sign-in screens set on a client, and how many are
/// open: given back (unset) when the last one closes.
class _LanguageHold {
  int count = 0;
  String value = '';
}

final _languageHolds = Expando<_LanguageHold>('rivium sign-in language');

final _emailShape = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');

/// Holds the sign-in screen's state and runs the SDK calls. The widgets only
/// read it and call its methods.
class RiviumSignInController extends ChangeNotifier {
  RiviumSignInController({
    required this.auth,
    required this.options,
    required this.strings,
    this.onSignedIn,
  });

  final RiviumAuth auth;
  final RiviumSignInOptions options;
  final RiviumSignInStrings strings;

  /// Called once a user is signed in.
  final void Function(RiviumAuthUser user)? onSignedIn;

  RiviumSignInView _view = RiviumSignInView.loading;
  RiviumSignInView get view => _view;

  RiviumAuthMethods _methods = const RiviumAuthMethods(methods: []);
  RiviumAuthMethods get methods => _methods;

  bool _busy = false;
  bool get busy => _busy;

  /// The error code of the last failed action, or null.
  String? _error;
  String? get error => _error;

  /// The message for [error], in the screen's language.
  String? get errorText => _error == null ? null : strings.error(_error!);

  RiviumSentKind? _sent;
  RiviumSentKind? get sent => _sent;

  /// The Telegram bot link when the user has to open the bot first.
  String? _botUrl;
  String? get botUrl => _botUrl;

  String email = '';
  String password = '';
  String phone = '';
  String code = '';

  /// Field errors, shown under the field.
  String? emailError;
  String? passwordError;

  bool _disposed = false;

  /// The screen set [RiviumAuth.languageCode] (it was unset) and gives it back.
  bool _languageSet = false;

  bool get showPassword => _methods.password;
  bool get showMagicLink =>
      _methods.magicLink && (options.magicLinkRedirectUrl ?? '').isNotEmpty;
  bool get showTelegram => _methods.telegram;
  bool get showGoogle => _methods.google && options.google != null;
  bool get showApple => _methods.apple && options.apple != null;
  bool get showGuest => _methods.anonymous && options.allowGuest;

  /// Buttons under the e-mail form (or alone when there is no form).
  bool get hasOtherMethods =>
      showMagicLink || showTelegram || showGoogle || showApple || showGuest;

  String get title => (options.appName ?? '').trim().isEmpty
      ? strings['title']
      : strings['titleTo'].replaceAll('{app}', options.appName!.trim());

  /// Loads the project's methods and opens the first screen.
  Future<void> load() async {
    // While the screen is open, the e-mails follow its language, unless the
    // app chose a language itself. Given back when the last screen closes.
    if (!_languageSet) {
      final hold = _languageHolds[auth];
      if (auth.languageCode == null || (hold != null && auth.languageCode == hold.value)) {
        // Book-keeping first: another screen may close during the await.
        final h = hold ?? _LanguageHold();
        h.count++;
        h.value = strings.languageCode;
        _languageHolds[auth] = h;
        _languageSet = true;
        await auth.setLanguageCode(strings.languageCode);
      }
    }
    _set(view: RiviumSignInView.loading);
    try {
      _methods = await auth.getMethods();
      _error = null;
      _set(
          view: showPassword || hasOtherMethods
              ? RiviumSignInView.home
              : RiviumSignInView.unavailable);
    } catch (e) {
      _error = errorCodeOf(e);
      _set(view: RiviumSignInView.unavailable);
    }
  }

  /// Opens [view], clearing the last error.
  void go(RiviumSignInView view) {
    _error = null;
    emailError = null;
    passwordError = null;
    if (view == RiviumSignInView.telegramPhone) {
      code = '';
      _botUrl = null;
    }
    _set(view: view);
  }

  void back() => go(RiviumSignInView.home);

  Future<void> signIn() async {
    if (!_checkEmail(needPassword: true)) return;
    await _run(() async => _done(
        await auth.signInWithEmail(email: email.trim(), password: password)));
  }

  Future<void> signUp() async {
    if (!_checkEmail(needPassword: true)) return;
    await _run(() async {
      final r = await auth.signUpWithEmail(
        email: email.trim(),
        password: password,
        redirectUrl: options.verifyRedirectUrl ?? '${auth.baseUrl}/pages/verify',
      );
      final user = r.user;
      if (user != null) return _done(user);
      password = '';
      if (!r.verificationSent) {
        // The account exists but must be confirmed, and no e-mail went out.
        _error = 'VERIFY_NOT_SENT';
        _set(view: RiviumSignInView.home);
        return;
      }
      _sent = RiviumSentKind.verify;
      _set(view: RiviumSignInView.sent);
    });
  }

  Future<void> sendReset() async {
    if (!_checkEmail()) return;
    await _run(() async {
      // No URL of the app's own: the server uses Rivium's reset page.
      await auth.sendPasswordReset(email.trim(),
          redirectUrl: options.resetRedirectUrl);
      _sent = RiviumSentKind.reset;
      _set(view: RiviumSignInView.sent);
    });
  }

  Future<void> sendMagicLink() async {
    if (!_checkEmail()) return;
    await _run(() async {
      await auth.sendMagicLink(email.trim(),
          redirectUrl: options.magicLinkRedirectUrl!);
      _sent = RiviumSentKind.magicLink;
      _set(view: RiviumSignInView.sent);
    });
  }

  Future<void> sendTelegramCode() async {
    if (phone.trim().isEmpty) {
      _error = RiviumAuthErrorCode.invalidInput;
      return _set();
    }
    await _run(() async {
      final r = await auth.requestTelegramCode(_phone());
      _botUrl = r.sent ? null : r.botUrl;
      if (r.sent) {
        code = '';
        _set(view: RiviumSignInView.telegramCode);
      } else {
        _set();
      }
    });
  }

  Future<void> verifyTelegramCode() async {
    if (code.trim().isEmpty) {
      _error = RiviumAuthErrorCode.invalidInput;
      return _set();
    }
    await _run(() async =>
        _done(await auth.verifyTelegramCode(_phone(), code.trim())));
  }

  Future<void> continueAsGuest() =>
      _run(() async => _done(await auth.signInAnonymously()));

  Future<void> continueWithGoogle() => _run(() async {
        final raw = RiviumAuthNonce.generate();
        final idToken = await options.google!(RiviumAuthNonce.sha256Hex(raw));
        if (idToken == null) return; // cancelled
        _done(await auth.signInWithGoogle(idToken: idToken, rawNonce: raw));
      });

  Future<void> continueWithApple() => _run(() async {
        final raw = RiviumAuthNonce.generate();
        final c = await options.apple!(RiviumAuthNonce.sha256Hex(raw));
        if (c == null) return; // cancelled
        _done(await auth.signInWithApple(
          idToken: c.idToken,
          rawNonce: raw,
          authorizationCode: c.authorizationCode,
          name: c.name,
        ));
      });

  Future<void> openBot() async {
    final url = safeBotUrl;
    if (url == null || options.openUrl == null) return;
    await options.openUrl!(url);
  }

  /// The bot link, only when it is an https Telegram address.
  Uri? get safeBotUrl {
    final u = Uri.tryParse(_botUrl ?? '');
    return u != null && u.scheme == 'https' && u.host == 't.me' ? u : null;
  }

  String _phone() => phone.replaceAll(RegExp(r'[\s\-()]'), '');

  bool _checkEmail({bool needPassword = false}) {
    final e = email.trim();
    emailError = e.isEmpty
        ? strings['required']
        : _emailShape.hasMatch(e)
            ? null
            : strings['badEmail'];
    passwordError = needPassword && password.isEmpty ? strings['required'] : null;
    _error = null;
    _set();
    return emailError == null && passwordError == null;
  }

  void _done(RiviumAuthUser user) {
    password = '';
    if (_disposed) return;
    onSignedIn?.call(user);
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    _error = null;
    _set(busy: true);
    try {
      await action();
    } catch (e) {
      _error = errorCodeOf(e);
    } finally {
      _set(busy: false);
    }
  }

  void _set({RiviumSignInView? view, bool? busy}) {
    if (_disposed) return;
    if (view != null) _view = view;
    if (busy != null) _busy = busy;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    password = '';
    final hold = _languageHolds[auth];
    if (_languageSet && hold != null && --hold.count == 0) {
      _languageHolds[auth] = null;
      if (auth.languageCode == hold.value) auth.setLanguageCode(null);
    }
    super.dispose();
  }
}
