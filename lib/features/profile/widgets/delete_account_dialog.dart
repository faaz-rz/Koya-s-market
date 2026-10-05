import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/services/network_status.dart';
import '../../../core/widgets/four_dot_loader.dart';
import '../../auth/data/auth_repository.dart';

/// Only the server callback can approve a real deletion. Codes are kept in
/// memory for this dialog and are never saved in preferences or app state.
class DeleteAccountDialog extends StatefulWidget {
  const DeleteAccountDialog({
    required this.requestCode,
    required this.confirmDeletion,
    required this.onOpenRequestPage,
    this.isDemo = false,
    this.now = DateTime.now,
    super.key,
  });

  final Future<AccountDeletionChallenge> Function() requestCode;
  final Future<void> Function(AccountDeletionChallenge, String) confirmDeletion;
  final VoidCallback onOpenRequestPage;
  final bool isDemo;
  final DateTime Function() now;

  @override
  State<DeleteAccountDialog> createState() => _DeleteAccountDialogState();
}

class _DeleteAccountDialogState extends State<DeleteAccountDialog> {
  final _confirmation = TextEditingController();
  final _otp = TextEditingController();
  AccountDeletionChallenge? _challenge;
  DateTime? _resendAt;
  DateTime? _verifyAt;
  Timer? _timer;
  bool _busy = false;
  bool _deleting = false;
  String? _error;

  bool get _confirmed => _confirmation.text.trim().toUpperCase() == 'DELETE';
  bool get _expired =>
      _challenge != null && !widget.now().isBefore(_challenge!.expiresAt);
  int _seconds(DateTime? until) => until == null
      ? 0
      : (until.difference(widget.now()).inMilliseconds / 1000).ceil().clamp(
          0,
          3600,
        );

  void _startTimer() {
    if (!mounted) return;
    _timer ??= Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  Future<void> _send() async {
    if (_busy || !_confirmed || _seconds(_resendAt) > 0) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final challenge = await widget.requestCode();
      if (!mounted) return;
      setState(() {
        _challenge = challenge;
        _otp.clear();
        _resendAt = widget.now().add(challenge.retryAfter);
        _verifyAt = null;
      });
      _startTimer();
    } on AccountDeletionException catch (error) {
      if (mounted) _showError(error);
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = connectionFailureMessage(
            error,
            'Could not request a code. Please try again.',
          );
          // A lost response may still have sent an email; avoid repeated sends.
          _resendAt = widget.now().add(const Duration(seconds: 60));
        });
      }
      _startTimer();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _showError(AccountDeletionException error) {
    setState(() {
      _error = connectionFailureMessage(error, error.message);
      if (error.needsNewCode) {
        _challenge = null;
        _otp.clear();
      }
      if (error.retryAfter > Duration.zero) {
        _resendAt = widget.now().add(error.retryAfter);
        if (_deleting) _verifyAt = _resendAt;
      }
    });
    _startTimer();
  }

  Future<void> _delete() async {
    final challenge = _challenge;
    if (_busy ||
        !_confirmed ||
        challenge == null ||
        _expired ||
        _seconds(_verifyAt) > 0 ||
        !RegExp(r'^\d{6,8}$').hasMatch(_otp.text)) {
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _deleting = true;
      _error = null;
    });
    try {
      await widget.confirmDeletion(challenge, _otp.text);
      if (mounted) Navigator.of(context).pop(true);
    } on AccountDeletionException catch (error) {
      if (mounted) _showError(error);
    } catch (error) {
      if (mounted) {
        setState(() {
          _challenge = null;
          _otp.clear();
          _error = connectionFailureMessage(
            error,
            'Deletion was not confirmed. Sign in again to check your account before requesting a new code.',
          );
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _deleting = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _confirmation.dispose();
    _otp.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final resend = _seconds(_resendAt);
    final verify = _seconds(_verifyAt);
    final canDelete =
        !_busy &&
        _confirmed &&
        _challenge != null &&
        !_expired &&
        verify == 0 &&
        RegExp(r'^\d{6,8}$').hasMatch(_otp.text);
    final textTheme = Theme.of(context).textTheme;
    final stage = _challenge == null ? 1 : 2;
    return PopScope(
      canPop: !_busy,
      child: AlertDialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        titlePadding: const EdgeInsets.fromLTRB(24, 24, 24, 12),
        contentPadding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
        actionsPadding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
        scrollable: true,
        title: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: AppColors.errorSoft,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(
                Icons.person_remove_outlined,
                color: AppColors.error,
                size: 22,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Delete account',
                    style: textTheme.titleLarge?.copyWith(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'This action is permanent.',
                    style: textTheme.bodySmall?.copyWith(
                      color: AppColors.inkSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        content: SizedBox(
          width: 392,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Your profile and saved addresses will be removed. Completed orders are kept without your personal details.',
                style: textTheme.bodyMedium?.copyWith(
                  color: AppColors.inkSecondary,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.warningSoft,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  'Finish or cancel active orders before continuing.',
                  style: textTheme.bodySmall?.copyWith(color: AppColors.ink),
                ),
              ),
              const SizedBox(height: 20),
              Text(
                'Step $stage of 2 · ${stage == 1 ? 'Confirm your request' : 'Verify your email'}',
                style: textTheme.labelLarge?.copyWith(
                  color: AppColors.brand700,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                key: const Key('delete-account-confirmation'),
                controller: _confirmation,
                enabled: !_busy && _challenge == null,
                autocorrect: false,
                enableSuggestions: false,
                textCapitalization: TextCapitalization.characters,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  labelText: 'Type DELETE',
                  helperText: 'We verify this request with an email code.',
                  helperMaxLines: 2,
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  key: const Key('delete-account-send-code'),
                  onPressed: !_busy && _confirmed && resend == 0 ? _send : null,
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(0, 48),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (_busy && !_deleting)
                        const FourDotLoader(size: 22)
                      else
                        const Icon(Icons.mail_outline_rounded, size: 18),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          _busy && !_deleting
                              ? 'Sending code…'
                              : resend > 0
                              ? 'Resend in ${resend}s'
                              : _challenge == null
                              ? 'Send email code'
                              : 'Resend email code',
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (_challenge != null) ...[
                const SizedBox(height: 16),
                Semantics(
                  liveRegion: true,
                  child: Text(
                    'Code sent to ${_challenge!.emailHint}. Use the latest code within 10 minutes.',
                    style: textTheme.bodySmall?.copyWith(
                      color: AppColors.inkSecondary,
                    ),
                  ),
                ),
                if (widget.isDemo)
                  const Text(
                    'Demo code: 123456 — no email sent.',
                    key: Key('delete-account-demo-code'),
                  ),
                const SizedBox(height: 12),
                TextField(
                  key: const Key('delete-account-otp'),
                  controller: _otp,
                  enabled: !_busy && !_expired,
                  keyboardType: TextInputType.number,
                  autofillHints: const [AutofillHints.oneTimeCode],
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(8),
                  ],
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                    labelText: 'Email code',
                    prefixIcon: Icon(Icons.lock_outline_rounded),
                  ),
                ),
              ],
              if (_expired || _error != null || verify > 0)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Semantics(
                    liveRegion: true,
                    child: Text(
                      _expired
                          ? 'Code expired. Request a new code.'
                          : verify > 0
                          ? '${_error ?? 'Please wait.'} Retry in ${verify}s.'
                          : _error!,
                      style: textTheme.bodySmall?.copyWith(
                        color: AppColors.error,
                      ),
                    ),
                  ),
                ),
              const SizedBox(height: 8),
              TextButton(
                key: const Key('delete-account-request-page'),
                onPressed: _busy ? null : widget.onOpenRequestPage,
                child: const Text(
                  'Request deletion on the web',
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          ),
        ),
        actions: [
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              key: const Key('delete-account-final'),
              onPressed: canDelete ? _delete : null,
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.error,
                minimumSize: const Size(0, 48),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (_deleting) ...[
                    const FourDotLoader(size: 22, color: AppColors.error),
                    const SizedBox(width: 8),
                  ],
                  Flexible(
                    child: Text(
                      _deleting ? 'Deleting…' : 'Delete permanently',
                      textAlign: TextAlign.center,
                    ),
                  ),
                ],
              ),
            ),
          ),
          SizedBox(
            width: double.infinity,
            child: TextButton(
              onPressed: _busy ? null : () => Navigator.of(context).pop(false),
              child: const Text('Keep account'),
            ),
          ),
        ],
      ),
    );
  }
}
