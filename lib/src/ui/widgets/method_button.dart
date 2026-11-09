import 'package:flutter/material.dart';

/// A full-width button for another sign-in method.
class RiviumMethodButton extends StatelessWidget {
  const RiviumMethodButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final Widget icon;
  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 48,
      child: OutlinedButton.icon(
        onPressed: onPressed,
        icon: icon,
        label: Text(label),
      ),
    );
  }
}
