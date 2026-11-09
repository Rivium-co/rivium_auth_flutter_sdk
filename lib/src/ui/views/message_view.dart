import 'package:flutter/material.dart';

import '../controller.dart';
import '../widgets/screen_header.dart';

/// "Check your e-mail" after a link was sent, and "sign-in is not available".
class RiviumMessageView extends StatelessWidget {
  const RiviumMessageView({super.key, required this.c});

  final RiviumSignInController c;

  @override
  Widget build(BuildContext context) {
    final s = c.strings;
    if (c.view == RiviumSignInView.unavailable) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          RiviumScreenHeader(title: c.title, logo: c.options.logo),
          const SizedBox(height: 20),
          Text(c.errorText ?? s['noMethods'],
              key: const ValueKey('rivium-unavailable'),
              textAlign: TextAlign.center),
          const SizedBox(height: 16),
          OutlinedButton(onPressed: c.load, child: Text(s['retry'])),
        ],
      );
    }
    final key = switch (c.sent) {
      RiviumSentKind.reset => 'resetSent',
      RiviumSentKind.magicLink => 'linkSent',
      _ => 'verifySent',
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        RiviumScreenHeader(title: s['checkEmail'], logo: c.options.logo),
        const SizedBox(height: 12),
        const Icon(Icons.mark_email_read_outlined, size: 48),
        const SizedBox(height: 12),
        Text(s[key].replaceAll('{email}', '\u2068${c.email.trim()}\u2069'),
            key: const ValueKey('rivium-sent'), textAlign: TextAlign.center),
        const SizedBox(height: 16),
        OutlinedButton(onPressed: c.back, child: Text(s['back'])),
      ],
    );
  }
}
