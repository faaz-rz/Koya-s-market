import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/config/app_environment.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/koyas_button.dart';
import '../../../core/widgets/koyas_logo.dart';
import '../data/auth_repository.dart';
import '../../store/providers/store_provider.dart';
import '../../store/data/supabase_store_repository.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key, this.initialMessage});

  final String? initialMessage;

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _emailController = TextEditingController(
    text: AppEnvironment.hasSupabaseConfig ? '' : 'ezlin@example.com',
  );
  final _otpController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _otpSent = false;
  bool _loading = false;
  String? _authMessage;

  @override
  void initState() {
    super.initState();
    _authMessage = widget.initialMessage;
  }

  @override
  void dispose() {
    _emailController.dispose();
    _otpController.dispose();
    super.dispose();
  }

  Future<void> _continue() async {
    if (!_formKey.currentState!.validate()) return;
    if (AppEnvironment.hasSupabaseConfig) {
      setState(() {
        _loading = true;
        _authMessage = null;
      });
      try {
        final repository = AuthRepository();
        if (!_otpSent) {
          await repository.sendEmailOtp(_emailController.text);
          if (mounted) {
            setState(() {
              _otpSent = true;
              _authMessage = 'A six-digit code was sent to your email.';
            });
          }
        } else {
          await repository.verifyEmailOtp(
            email: _emailController.text,
            token: _otpController.text,
          );
          await _completeRemoteSignIn();
        }
      } catch (_) {
        if (mounted) {
          setState(
            () => _authMessage = _otpSent
                ? 'Could not verify that code. Check it and try again.'
                : 'Could not send a code. Please try again shortly.',
          );
        }
      } finally {
        if (mounted) setState(() => _loading = false);
      }
      return;
    }
    if (!AppEnvironment.allowCustomerDemo) {
      setState(
        () => _authMessage =
            'This build is missing its secure service configuration.',
      );
      return;
    }
    ref.read(storeProvider.notifier).loginDemo(email: _emailController.text);
    context.go('/home');
  }

  Future<void> _completeRemoteSignIn() async {
    final bundle = await SupabaseStoreRepository().loadStore();
    ref.read(storeProvider.notifier).hydrateRemoteBundle(bundle);
    if (mounted) context.go('/home');
  }

  Future<void> _openPlayReviewLogin() async {
    final credentials = await showDialog<_PasswordCredentials>(
      context: context,
      builder: (context) => const _PlayReviewLoginDialog(),
    );
    if (credentials == null || !mounted) return;
    setState(() {
      _loading = true;
      _authMessage = null;
    });
    try {
      await AuthRepository().signInWithPassword(
        email: credentials.email,
        password: credentials.password,
      );
      await _completeRemoteSignIn();
    } catch (_) {
      if (mounted) {
        setState(
          () => _authMessage =
              'Reviewer credentials were not accepted. Check them and try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _openPrivacyPolicy() async {
    final uri = Uri.tryParse(AppEnvironment.privacyPolicyUrl);
    if (uri == null || !uri.isScheme('https')) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Privacy policy is not configured yet.'),
          ),
        );
      }
      return;
    }
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication) &&
        mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Privacy policy could not be opened.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.xxl),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Align(
                      alignment: Alignment.centerLeft,
                      child: KoyasLogo(),
                    ),
                    const SizedBox(height: AppSpacing.page),
                    Text(
                      'Groceries made simple.',
                      style: Theme.of(context).textTheme.displayLarge,
                    ),
                    const SizedBox(height: AppSpacing.md),
                    Text(
                      'Sign in to shop, schedule pickup or arrange home delivery.',
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        color: AppColors.inkSecondary,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xxxl),
                    TextFormField(
                      key: const Key('login-email'),
                      controller: _emailController,
                      keyboardType: TextInputType.emailAddress,
                      autofillHints: const [AutofillHints.email],
                      decoration: const InputDecoration(
                        labelText: 'Email address',
                        prefixIcon: Icon(Icons.mail_outline_rounded),
                      ),
                      validator: (value) {
                        final email = value?.trim() ?? '';
                        if (!email.contains('@') || !email.contains('.')) {
                          return 'Enter a valid email address';
                        }
                        return null;
                      },
                    ),
                    if (_otpSent) ...[
                      const SizedBox(height: AppSpacing.lg),
                      TextFormField(
                        controller: _otpController,
                        maxLength: 6,
                        keyboardType: TextInputType.number,
                        autofillHints: const [AutofillHints.oneTimeCode],
                        decoration: const InputDecoration(
                          labelText: 'Verification code',
                          prefixIcon: Icon(Icons.password_rounded),
                        ),
                        validator: (value) {
                          if (!_otpSent) return null;
                          return RegExp(
                                r'^\d{6}$',
                              ).hasMatch(value?.trim() ?? '')
                              ? null
                              : 'Enter the 6-digit code';
                        },
                      ),
                    ],
                    if (_authMessage != null) ...[
                      const SizedBox(height: AppSpacing.md),
                      Text(
                        _authMessage!,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: _authMessage!.startsWith('Could')
                              ? AppColors.error
                              : AppColors.success,
                        ),
                      ),
                    ],
                    const SizedBox(height: AppSpacing.lg),
                    KoyasButton(
                      key: const Key('customer-login'),
                      label: AppEnvironment.hasSupabaseConfig
                          ? (_otpSent
                                ? 'Verify and continue'
                                : 'Send secure code')
                          : 'Continue to Koya Stores',
                      loading: _loading,
                      icon: Icons.arrow_forward_rounded,
                      onPressed: _continue,
                    ),
                    if (AppEnvironment.hasSupabaseConfig &&
                        AppEnvironment.enablePlayReviewLogin) ...[
                      const SizedBox(height: AppSpacing.sm),
                      TextButton.icon(
                        key: const Key('play-review-login'),
                        onPressed: _loading ? null : _openPlayReviewLogin,
                        icon: const Icon(Icons.fact_check_outlined),
                        label: const Text('App review access'),
                      ),
                    ],
                    const SizedBox(height: AppSpacing.sm),
                    TextButton.icon(
                      key: const Key('login-privacy-policy'),
                      onPressed: _openPrivacyPolicy,
                      icon: const Icon(Icons.privacy_tip_outlined),
                      label: const Text('Privacy policy'),
                    ),
                    const SizedBox(height: AppSpacing.xxl),
                    if (AppEnvironment.allowCustomerDemo)
                      Container(
                        padding: const EdgeInsets.all(AppSpacing.lg),
                        decoration: BoxDecoration(
                          color: AppColors.brandSoft,
                          borderRadius: BorderRadius.circular(AppRadii.lg),
                        ),
                        child: const Row(
                          children: [
                            Icon(Icons.verified_user_outlined),
                            SizedBox(width: AppSpacing.md),
                            Expanded(
                              child: Text(
                                'This local demo uses sample data. Production login uses Supabase OTP.',
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PasswordCredentials {
  const _PasswordCredentials({required this.email, required this.password});

  final String email;
  final String password;
}

class _PlayReviewLoginDialog extends StatefulWidget {
  const _PlayReviewLoginDialog();

  @override
  State<_PlayReviewLoginDialog> createState() => _PlayReviewLoginDialogState();
}

class _PlayReviewLoginDialogState extends State<_PlayReviewLoginDialog> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _obscurePassword = true;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.of(context).pop(
      _PasswordCredentials(email: _email.text.trim(), password: _password.text),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('App review access'),
      content: SizedBox(
        width: 420,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'This sign-in is reserved for the reusable review account supplied through Google Play Console.',
              ),
              const SizedBox(height: AppSpacing.lg),
              TextFormField(
                key: const Key('play-review-email'),
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                autofillHints: const [AutofillHints.email],
                decoration: const InputDecoration(labelText: 'Reviewer email'),
                validator: (value) {
                  final email = value?.trim() ?? '';
                  return email.contains('@') && email.contains('.')
                      ? null
                      : 'Enter the reviewer email';
                },
              ),
              const SizedBox(height: AppSpacing.md),
              TextFormField(
                key: const Key('play-review-password'),
                controller: _password,
                obscureText: _obscurePassword,
                autofillHints: const [AutofillHints.password],
                onFieldSubmitted: (_) => _submit(),
                decoration: InputDecoration(
                  labelText: 'Reviewer password',
                  suffixIcon: IconButton(
                    tooltip: _obscurePassword
                        ? 'Show password'
                        : 'Hide password',
                    onPressed: () =>
                        setState(() => _obscurePassword = !_obscurePassword),
                    icon: Icon(
                      _obscurePassword
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
                    ),
                  ),
                ),
                validator: (value) => (value?.length ?? 0) >= 8
                    ? null
                    : 'Enter the reviewer password',
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const Key('play-review-submit'),
          onPressed: _submit,
          child: const Text('Sign in'),
        ),
      ],
    );
  }
}
