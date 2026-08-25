import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/config/app_environment.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/koyas_button.dart';
import '../../../core/widgets/koyas_logo.dart';
import '../data/auth_repository.dart';
import '../../notifications/services/push_notification_service.dart';
import '../../store/providers/store_provider.dart';
import '../../store/data/supabase_store_repository.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

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
          final bundle = await SupabaseStoreRepository().loadStore();
          ref.read(storeProvider.notifier).hydrateRemoteBundle(bundle);
          try {
            await PushNotificationService.instance.registerForCurrentUser();
          } catch (_) {
            // Notification permission never blocks a successful sign-in.
          }
          if (mounted) context.go('/home');
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
    ref.read(storeProvider.notifier).loginDemo(email: _emailController.text);
    context.go('/home');
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
                    const SizedBox(height: AppSpacing.xxl),
                    if (!AppEnvironment.hasSupabaseConfig)
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
