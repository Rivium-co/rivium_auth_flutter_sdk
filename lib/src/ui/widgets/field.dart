import 'package:flutter/material.dart';

/// A text field whose value lives in the controller (no TextEditingController).
class RiviumField extends StatelessWidget {
  const RiviumField({
    super.key,
    required this.label,
    required this.initialValue,
    required this.onChanged,
    this.errorText,
    this.hint,
    this.obscure = false,
    this.ltr = false,
    this.keyboardType,
    this.autofillHints,
    this.textInputAction,
    this.onSubmitted,
    this.enabled = true,
  });

  final String label;
  final String initialValue;
  final ValueChanged<String> onChanged;
  final String? errorText;
  final String? hint;
  final bool obscure;

  /// E-mail, phone and code read left to right, also in a right-to-left language.
  final bool ltr;
  final TextInputType? keyboardType;
  final Iterable<String>? autofillHints;
  final TextInputAction? textInputAction;
  final VoidCallback? onSubmitted;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      initialValue: initialValue,
      onChanged: onChanged,
      enabled: enabled,
      obscureText: obscure,
      autocorrect: false,
      enableSuggestions: !obscure,
      keyboardType: keyboardType,
      autofillHints: autofillHints,
      textInputAction: textInputAction,
      onFieldSubmitted: onSubmitted == null ? null : (_) => onSubmitted!(),
      textDirection: ltr ? TextDirection.ltr : null,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        hintTextDirection: ltr ? TextDirection.ltr : null,
        errorText: errorText,
        border: const OutlineInputBorder(),
      ),
    );
  }
}
