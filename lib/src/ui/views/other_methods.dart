import 'package:flutter/material.dart';

import '../controller.dart';
import '../widgets/method_button.dart';

/// Magic link, Telegram, Google, Apple and guest buttons (only those on).
class RiviumOtherMethods extends StatelessWidget {
  const RiviumOtherMethods({super.key, required this.c});

  final RiviumSignInController c;

  @override
  Widget build(BuildContext context) {
    final s = c.strings;
    final off = c.busy;
    final buttons = <Widget>[
      if (c.showGoogle)
        RiviumMethodButton(
          key: const ValueKey('rivium-google'),
          icon: const Text('G', style: TextStyle(fontWeight: FontWeight.bold)),
          label: s['withGoogle'],
          onPressed: off ? null : c.continueWithGoogle,
        ),
      if (c.showApple)
        RiviumMethodButton(
          key: const ValueKey('rivium-apple'),
          icon: const Icon(Icons.apple),
          label: s['withApple'],
          onPressed: off ? null : c.continueWithApple,
        ),
      if (c.showMagicLink)
        RiviumMethodButton(
          key: const ValueKey('rivium-magic-link'),
          icon: const Icon(Icons.mail_outline),
          label: s['withEmailLink'],
          onPressed: off ? null : () => c.go(RiviumSignInView.magicLink),
        ),
      if (c.showTelegram)
        RiviumMethodButton(
          key: const ValueKey('rivium-telegram'),
          icon: const Icon(Icons.telegram),
          label: s['withTelegram'],
          onPressed: off ? null : () => c.go(RiviumSignInView.telegramPhone),
        ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final b in buttons) ...[b, const SizedBox(height: 10)],
        if (c.showGuest)
          TextButton(
            key: const ValueKey('rivium-guest'),
            onPressed: off ? null : c.continueAsGuest,
            child: Text(s['guest']),
          ),
      ],
    );
  }
}
