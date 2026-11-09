import 'package:flutter/material.dart';

import '../rivium_auth.dart';
import '../models.dart';
import 'controller.dart';
import 'options.dart';
import 'strings.dart';
import 'views/email_only_view.dart';
import 'views/home_view.dart';
import 'views/message_view.dart';
import 'views/sign_up_view.dart';
import 'views/telegram_view.dart';

/// The ready-made sign-in form, to put on any page of your app. It shows only
/// the methods turned on in the Console and calls [onSignedIn] once a user is
/// signed in. [RiviumSignIn.show] opens it as a dialog.
class RiviumSignInScreen extends StatelessWidget {
  const RiviumSignInScreen({
    super.key,
    this.auth,
    this.options = const RiviumSignInOptions(),
    this.onSignedIn,
    this.onClose,
  });

  /// Shows a close button (disabled while a sign-in runs). [RiviumSignIn.show]
  /// sets it.
  final VoidCallback? onClose;

  /// Null: [RiviumAuth.instance].
  final RiviumAuth? auth;
  final RiviumSignInOptions options;
  final void Function(RiviumAuthUser user)? onSignedIn;

  @override
  Widget build(BuildContext context) {
    final strings = RiviumSignInStrings.of(
        options.languageCode ?? Localizations.maybeLocaleOf(context)?.languageCode);
    return Directionality(
      textDirection: strings.rtl ? TextDirection.rtl : TextDirection.ltr,
      child: _ControllerHost(
        onClose: onClose,
        create: () => RiviumSignInController(
          auth: auth ?? RiviumAuth.instance,
          options: options,
          strings: strings,
          onSignedIn: onSignedIn,
        ),
      ),
    );
  }
}

/// Owns the controller's life (creates it once, disposes it with the screen).
/// All the state is in the controller; this only keeps it alive.
class _ControllerHost extends StatefulWidget {
  const _ControllerHost({required this.create, this.onClose});

  final RiviumSignInController Function() create;
  final VoidCallback? onClose;

  @override
  State<_ControllerHost> createState() => _ControllerHostState();
}

class _ControllerHostState extends State<_ControllerHost> {
  late final RiviumSignInController _c = widget.create()..load();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _SignInBody(c: _c, onClose: widget.onClose);
}

class _SignInBody extends StatelessWidget {
  const _SignInBody({required this.c, this.onClose});

  final RiviumSignInController c;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: c,
      builder: (context, _) {
        final s = c.strings;
        final Widget view = switch (c.view) {
          RiviumSignInView.loading => const Padding(
              padding: EdgeInsets.all(48),
              child: Center(child: CircularProgressIndicator()),
            ),
          RiviumSignInView.home => RiviumHomeView(c: c),
          RiviumSignInView.signUp => RiviumSignUpView(c: c),
          RiviumSignInView.forgot => RiviumEmailOnlyView(
              c: c, title: s['forgotTitle'], action: s['sendReset'], onSend: c.sendReset),
          RiviumSignInView.magicLink => RiviumEmailOnlyView(
              c: c, title: s['magicTitle'], action: s['sendLink'], onSend: c.sendMagicLink),
          RiviumSignInView.telegramPhone ||
          RiviumSignInView.telegramCode =>
            RiviumTelegramView(c: c),
          RiviumSignInView.sent ||
          RiviumSignInView.unavailable =>
            RiviumMessageView(c: c),
        };
        final body = SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(24, onClose == null ? 24 : 40, 24, 24),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: KeyedSubtree(key: ValueKey(c.view), child: view),
            ),
          ),
        );
        // No closing while a sign-in runs: it could land after the screen
        // answered null.
        return PopScope(
          canPop: !c.busy,
          child: onClose == null
              ? body
              : Stack(children: [
                  body,
                  PositionedDirectional(
                    top: 4,
                    end: 4,
                    child: IconButton(
                      key: const ValueKey('rivium-close'),
                      tooltip: s['close'],
                      icon: const Icon(Icons.close),
                      onPressed: c.busy ? null : onClose,
                    ),
                  ),
                ]),
        );
      },
    );
  }
}
