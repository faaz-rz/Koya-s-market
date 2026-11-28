import 'package:flutter/material.dart';

class AccountPasswordField extends StatelessWidget {
  const AccountPasswordField({
    required this.controller,
    required this.validator,
    this.label = 'Password',
    this.enabled = true,
    this.creating = false,
    super.key,
  });

  final TextEditingController controller;
  final FormFieldValidator<String> validator;
  final String label;
  final bool enabled, creating;

  @override
  Widget build(BuildContext context) => TextFormField(
    controller: controller,
    enabled: enabled,
    obscureText: true,
    autocorrect: false,
    enableSuggestions: false,
    autofillHints: [
      creating ? AutofillHints.newPassword : AutofillHints.password,
    ],
    validator: validator,
    decoration: InputDecoration(
      labelText: label,
      prefixIcon: const Icon(Icons.lock_outline),
      errorMaxLines: 2,
    ),
  );
}
