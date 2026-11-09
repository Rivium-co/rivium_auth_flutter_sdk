import 'package:flutter/material.dart';

import '../controller.dart';
import '../widgets/error_banner.dart';
import '../widgets/field.dart';
import '../widgets/primary_button.dart';
import '../widgets/screen_header.dart';

/// Telegram: the phone number, then the code (or "open the bot first").
class RiviumTelegramView extends StatelessWidget {
  const RiviumTelegramView({super.key, required this.c});

  final RiviumSignInController c;

  @override
  Widget build(BuildContext context) {
    final s = c.strings;
    final codeStep = c.view == RiviumSignInView.telegramCode;
    final bot = c.safeBotUrl?.toString();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        RiviumScreenHeader(
            title: s['telegramTitle'],
            logo: c.options.logo,
            onBack: c.busy
                ? null
                : () => codeStep ? c.go(RiviumSignInView.telegramPhone) : c.back(),
            backLabel: s['back']),
        const SizedBox(height: 20),
        RiviumErrorBanner(text: c.errorText),
        if (c.errorText != null) const SizedBox(height: 12),
        if (!codeStep) ...[
          RiviumField(
            key: const ValueKey('rivium-phone'),
            label: s['phone'],
            hint: s['phoneHint'],
            initialValue: c.phone,
            onChanged: (v) => c.phone = v,
            ltr: true,
            keyboardType: TextInputType.phone,
            autofillHints: const [AutofillHints.telephoneNumber],
            textInputAction: TextInputAction.done,
            onSubmitted: c.sendTelegramCode,
          ),
          if (bot != null) ...[
            const SizedBox(height: 12),
            Text(s['botFirst'].replaceAll('{bot}', _botName(bot))),
            const SizedBox(height: 4),
            if (c.options.openUrl != null)
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: TextButton(onPressed: c.openBot, child: Text(bot)),
              )
            else
              SelectableText(bot, textDirection: TextDirection.ltr),
          ],
          const SizedBox(height: 16),
          RiviumPrimaryButton(
            key: const ValueKey('rivium-send-code'),
            label: bot != null ? s['retry'] : s['sendCode'],
            busy: c.busy,
            onPressed: c.sendTelegramCode,
          ),
        ] else ...[
          Text(s['codeSent']),
          const SizedBox(height: 12),
          RiviumField(
            key: const ValueKey('rivium-code'),
            label: s['code'],
            initialValue: c.code,
            onChanged: (v) => c.code = v,
            ltr: true,
            keyboardType: TextInputType.number,
            autofillHints: const [AutofillHints.oneTimeCode],
            textInputAction: TextInputAction.done,
            onSubmitted: c.verifyTelegramCode,
          ),
          const SizedBox(height: 16),
          RiviumPrimaryButton(
            key: const ValueKey('rivium-verify-code'),
            label: s['verify'],
            busy: c.busy,
            onPressed: c.verifyTelegramCode,
          ),
        ],
      ],
    );
  }

  static String _botName(String url) {
    final name = Uri.tryParse(url)?.pathSegments.where((p) => p.isNotEmpty).firstOrNull;
    return name == null ? 'Telegram' : '@$name';
  }
}
