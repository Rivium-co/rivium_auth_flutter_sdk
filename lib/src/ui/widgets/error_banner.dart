import 'package:flutter/material.dart';

/// The last error, in the screen's language.
class RiviumErrorBanner extends StatelessWidget {
  const RiviumErrorBanner({super.key, required this.text});

  final String? text;

  @override
  Widget build(BuildContext context) {
    final t = text;
    if (t == null) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.errorContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(t,
          key: const ValueKey('rivium-sign-in-error'),
          style: TextStyle(color: scheme.onErrorContainer)),
    );
  }
}
