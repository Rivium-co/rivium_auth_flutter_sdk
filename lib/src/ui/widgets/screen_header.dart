import 'package:flutter/material.dart';

/// Logo, title and an optional back button.
class RiviumScreenHeader extends StatelessWidget {
  const RiviumScreenHeader({
    super.key,
    required this.title,
    this.logo,
    this.onBack,
    this.backLabel,
  });

  final String title;
  final Widget? logo;
  final VoidCallback? onBack;
  final String? backLabel;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (onBack != null)
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: IconButton(
              onPressed: onBack,
              tooltip: backLabel,
              icon: const BackButtonIcon(),
            ),
          ),
        if (logo != null) Center(child: logo!),
        if (logo != null) const SizedBox(height: 12),
        Text(title,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.headlineSmall),
      ],
    );
  }
}
