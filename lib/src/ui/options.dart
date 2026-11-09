import 'package:flutter/widgets.dart';

/// Gets a Google ID token for [hashedNonce] with your Google sign-in (for
/// example the google_sign_in package). Return null when the user cancels.
typedef RiviumGoogleIdToken = Future<String?> Function(String hashedNonce);

/// What Sign in with Apple returned.
class RiviumAppleCredential {
  const RiviumAppleCredential({
    required this.idToken,
    this.authorizationCode,
    this.name,
  });

  final String idToken;

  /// Lets Rivium revoke the Apple sign-in when the account is deleted.
  final String? authorizationCode;

  /// The name Apple gives on the first sign-in only.
  final String? name;
}

/// Runs Sign in with Apple for [hashedNonce] (for example with the
/// sign_in_with_apple package). Return null when the user cancels.
typedef RiviumAppleCredentialFor = Future<RiviumAppleCredential?> Function(
    String hashedNonce);

/// Opens [url] (the Telegram bot), for example with url_launcher. Without it the
/// screen shows the link for the user to copy.
typedef RiviumOpenUrl = Future<void> Function(Uri url);

/// What the sign-in screen offers and how it looks. Every method also has to be
/// turned on in the Console (Rivium Auth › Sign-in methods).
class RiviumSignInOptions {
  const RiviumSignInOptions({
    this.appName,
    this.logo,
    this.languageCode,
    this.allowGuest = false,
    this.google,
    this.apple,
    this.magicLinkRedirectUrl,
    this.verifyRedirectUrl,
    this.resetRedirectUrl,
    this.openUrl,
  });

  /// Shown as "Sign in to [appName]". Null: "Sign in".
  final String? appName;

  /// Shown above the title, for example your app icon.
  final Widget? logo;

  /// The screen's language, a code such as `en`. Null: the app's language
  /// (`Localizations`), English when the screen doesn't have it. The e-mails
  /// Rivium sends follow it too, unless you set [RiviumAuth.languageCode]
  /// yourself.
  final String? languageCode;

  /// Shows "Continue as guest" when anonymous sign-in is on. Off by default:
  /// every guest is a new user and counts toward the plan's monthly users.
  final bool allowGuest;

  /// Shows "Continue with Google" when Google sign-in is on.
  final RiviumGoogleIdToken? google;

  /// Shows "Continue with Apple" when Apple sign-in is on.
  final RiviumAppleCredentialFor? apple;

  /// One of the project's allowed redirect URLs that opens your app. Shows the
  /// magic link button when set and magic link is on. Your app finishes it with
  /// `RiviumAuth.instance.signInWithMagicLink(token)`.
  final String? magicLinkRedirectUrl;

  /// Where the confirm e-mail link goes. Null: Rivium's own confirm page.
  final String? verifyRedirectUrl;

  /// Where the password reset link goes. Null: Rivium's own reset page.
  final String? resetRedirectUrl;

  /// Opens the Telegram bot link.
  final RiviumOpenUrl? openUrl;
}
