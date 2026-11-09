import 'package:flutter/material.dart';

import '../controller.dart';
import '../widgets/error_banner.dart';
import '../widgets/field.dart';
import '../widgets/primary_button.dart';
import '../widgets/screen_header.dart';

/// One e-mail field and a send button: forgot password and magic link.
class RiviumEmailOnlyView extends StatelessWidget {
  const RiviumEmailOnlyView({
    super.key,
    required this.c,
    required this.title,
    required this.action,
    required this.onSend,
  });

  final RiviumSignInController c;
  final String title;
  final String action;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    final s = c.strings;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        RiviumScreenHeader(
            title: title,
            logo: c.options.logo,
            onBack: c.busy ? null : c.back,
            backLabel: s['back']),
        const SizedBox(height: 20),
        RiviumErrorBanner(text: c.errorText),
        if (c.errorText != null) const SizedBox(height: 12),
        RiviumField(
          key: ValueKey('rivium-${c.view.name}-email'),
          label: s['email'],
          initialValue: c.email,
          onChanged: (v) => c.email = v,
          errorText: c.emailError,
          ltr: true,
          keyboardType: TextInputType.emailAddress,
          autofillHints: const [AutofillHints.email],
          textInputAction: TextInputAction.done,
          onSubmitted: onSend,
        ),
        const SizedBox(height: 16),
        RiviumPrimaryButton(
          key: ValueKey('rivium-${c.view.name}-send'),
          label: action,
          busy: c.busy,
          onPressed: onSend,
        ),
      ],
    );
  }
}
