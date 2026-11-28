import 'dart:convert';

import 'package:flutter/material.dart';

import '../../../core/services/network_status.dart';
import '../../../core/theme/app_spacing.dart';
import '../data/auth_repository.dart';
import 'account_password_field.dart';

class SetPasswordDialog extends StatefulWidget {
  const SetPasswordDialog({
    required this.auth,
    required this.userId,
    super.key,
  });

  final AuthRepository auth;
  final String userId;

  @override
  State<SetPasswordDialog> createState() => _SetPasswordDialogState();
}

class _SetPasswordDialogState extends State<SetPasswordDialog> {
  final _form = GlobalKey<FormState>();
  final _password = TextEditingController();
  final _confirmation = TextEditingController();
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _password.dispose();
    _confirmation.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving || !_form.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.auth.setPasswordAfterVerification(
        userId: widget.userId,
        password: _password.text,
      );
      if (mounted) Navigator.of(context).pop();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = connectionFailureMessage(
          error,
          'The password could not be saved. Try a different password or sign in again with a code.',
        );
      });
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_saving,
    child: AlertDialog(
      title: const Text('Set a password'),
      scrollable: true,
      content: Form(
        key: _form,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Use at least 15 characters.'),
            const SizedBox(height: AppSpacing.md),
            AccountPasswordField(
              key: const Key('new-account-password'),
              controller: _password,
              enabled: !_saving,
              creating: true,
              label: 'New password',
              validator: (value) {
                final password = value ?? '';
                if (password.runes.length < 15) {
                  return 'Use at least 15 characters';
                }
                if (utf8.encode(password).length > 72) {
                  return 'Use a shorter password';
                }
                return null;
              },
            ),
            const SizedBox(height: AppSpacing.md),
            AccountPasswordField(
              key: const Key('confirm-account-password'),
              controller: _confirmation,
              enabled: !_saving,
              creating: true,
              label: 'Confirm password',
              validator: (value) =>
                  value != _password.text ? 'Passwords do not match' : null,
            ),
            if (_error != null) ...[
              const SizedBox(height: AppSpacing.md),
              Semantics(liveRegion: true, child: Text(_error!)),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: const Text('Skip'),
        ),
        FilledButton(
          key: const Key('save-account-password'),
          onPressed: _saving ? null : _save,
          child: Text(_saving ? 'Saving…' : 'Save password'),
        ),
      ],
    ),
  );
}
