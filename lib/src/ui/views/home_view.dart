import 'package:flutter/material.dart';

import '../controller.dart';
import '../widgets/error_banner.dart';
import '../widgets/field.dart';
import '../widgets/primary_button.dart';
import '../widgets/screen_header.dart';
import 'other_methods.dart';

/// The first screen: e-mail + password (when on), then the other methods.
class RiviumHomeView extends StatelessWidget {
  const RiviumHomeView({super.key, required this.c});

  final RiviumSignInController c;

  @override
  Widget build(BuildContext context) {
    final s = c.strings;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        RiviumScreenHeader(title: c.title, logo: c.options.logo),
        const SizedBox(height: 20),
        RiviumErrorBanner(text: c.errorText),
        if (c.canResend)
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton.icon(
              key: const ValueKey('rivium-resend'),
              onPressed: c.busy ? null : c.resendVerification,
              icon: c.resending
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.refresh, size: 18),
              label: Text(s['resend']),
            ),
          ),
        if (c.errorText != null) const SizedBox(height: 12),
        if (c.notice != null) ...[
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.secondaryContainer,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(c.notice!,
                key: const ValueKey('rivium-notice'),
                style: TextStyle(
                    color: Theme.of(context).colorScheme.onSecondaryContainer)),
          ),
          const SizedBox(height: 12),
        ],
        if (c.showPassword) ...[
          AutofillGroup(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                RiviumField(
                  key: const ValueKey('rivium-email'),
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
                  key: const ValueKey('rivium-password'),
                  label: s['password'],
                  initialValue: c.password,
                  onChanged: (v) => c.password = v,
                  errorText: c.passwordError,
                  obscure: true,
                  autofillHints: const [AutofillHints.password],
                  textInputAction: TextInputAction.done,
                  onSubmitted: c.signIn,
                ),
              ],
            ),
          ),
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: TextButton(
              key: const ValueKey('rivium-forgot'),
              onPressed: c.busy ? null : () => c.go(RiviumSignInView.forgot),
              child: Text(s['forgot']),
            ),
          ),
          RiviumPrimaryButton(
            key: const ValueKey('rivium-sign-in'),
            label: s['signIn'],
            busy: c.busy,
            onPressed: c.signIn,
          ),
          TextButton(
            key: const ValueKey('rivium-to-sign-up'),
            onPressed: c.busy ? null : () => c.go(RiviumSignInView.signUp),
            child: Text(s['noAccount']),
          ),
        ],
        if (c.showPassword && c.hasOtherMethods)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Row(children: [
              const Expanded(child: Divider()),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Text(s['or']),
              ),
              const Expanded(child: Divider()),
            ]),
          ),
        if (c.hasOtherMethods) RiviumOtherMethods(c: c),
      ],
    );
  }
}
