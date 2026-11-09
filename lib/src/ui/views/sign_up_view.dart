import 'package:flutter/material.dart';

import '../controller.dart';
import '../widgets/error_banner.dart';
import '../widgets/field.dart';
import '../widgets/primary_button.dart';
import '../widgets/screen_header.dart';

/// E-mail + password sign-up.
class RiviumSignUpView extends StatelessWidget {
  const RiviumSignUpView({super.key, required this.c});

  final RiviumSignInController c;

  @override
  Widget build(BuildContext context) {
    final s = c.strings;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        RiviumScreenHeader(
            title: s['signUpTitle'],
            logo: c.options.logo,
            onBack: c.busy ? null : c.back,
            backLabel: s['back']),
        const SizedBox(height: 20),
        RiviumErrorBanner(text: c.errorText),
        if (c.errorText != null) const SizedBox(height: 12),
        AutofillGroup(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              RiviumField(
                key: const ValueKey('rivium-sign-up-email'),
                label: s['email'],
                initialValue: c.email,
                onChanged: (v) => c.email = v,
                errorText: c.emailError,
                ltr: true,
                keyboardType: TextInputType.emailAddress,
                autofillHints: const [AutofillHints.email],
                textInputAction: TextInputAction.next,
              ),
              const SizedBox(height: 12),
              RiviumField(
                key: const ValueKey('rivium-sign-up-password'),
                label: s['password'],
                initialValue: c.password,
                onChanged: (v) => c.password = v,
                errorText: c.passwordError,
                obscure: true,
                autofillHints: const [AutofillHints.newPassword],
                textInputAction: TextInputAction.done,
                onSubmitted: c.signUp,
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        RiviumPrimaryButton(
          key: const ValueKey('rivium-sign-up'),
          label: s['signUp'],
          busy: c.busy,
          onPressed: c.signUp,
        ),
        TextButton(
          onPressed: c.busy ? null : c.back,
          child: Text(s['haveAccount']),
        ),
      ],
    );
  }
}
