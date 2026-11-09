import 'package:flutter/material.dart';

import '../rivium_auth.dart';
import '../models.dart';
import 'options.dart';
import 'sign_in_screen.dart';

/// Opens Rivium's sign-in screen, like FirebaseUI.
abstract final class RiviumSignIn {
  /// Below this width the screen opens full screen, above it as a dialog.
  static const dialogMinWidth = 600.0;

  /// Opens the sign-in screen and answers the signed-in user, or null when the
  /// user closed it. A dialog on wide screens, a full page on phones.
  ///
  /// ```dart
  /// final user = await RiviumSignIn.show(context);
  /// ```
  static Future<RiviumAuthUser?> show(
    BuildContext context, {
    RiviumAuth? auth,
    RiviumSignInOptions options = const RiviumSignInOptions(),
  }) {
    Widget screen(BuildContext inner) => RiviumSignInScreen(
          auth: auth,
          options: options,
          onSignedIn: (user) => Navigator.of(inner).pop(user),
          onClose: () => Navigator.of(inner).maybePop(),
        );
    if (MediaQuery.sizeOf(context).width < dialogMinWidth) {
      return Navigator.of(context).push<RiviumAuthUser>(MaterialPageRoute(
        fullscreenDialog: true,
        builder: (inner) => Scaffold(body: SafeArea(child: screen(inner))),
      ));
    }
    return showDialog<RiviumAuthUser>(
      context: context,
      builder: (inner) => Dialog(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460, maxHeight: 720),
          child: screen(inner),
        ),
      ),
    );
  }
}
