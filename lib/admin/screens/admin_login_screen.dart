import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/config/app_environment.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/widgets/koyas_button.dart';
import '../../core/widgets/koyas_logo.dart';
import '../../features/auth/data/auth_repository.dart';
import '../../features/store/data/supabase_store_repository.dart';
import '../../features/store/providers/store_provider.dart';

enum _AdminLoginStep { email, emailOtp, authenticator, enrollment }

class AdminLoginScreen extends ConsumerStatefulWidget {
  const AdminLoginScreen({
    this.accessDenied = false,
    this.mfaRequired = false,
    this.sessionExpired = false,
    super.key,
  });

  final bool accessDenied;
  final bool mfaRequired;
  final bool sessionExpired;

  @override
  ConsumerState<AdminLoginScreen> createState() => _AdminLoginScreenState();
}

class _AdminLoginScreenState extends ConsumerState<AdminLoginScreen> {
  final _emailController = TextEditingController();
  final _otpController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  _AdminLoginStep _step = _AdminLoginStep.email;
  bool _loading = false;
  bool _messageIsError = false;
  String? _message;
  String? _mfaFactorId;
  String? _mfaSecret;

  bool get _isMfaStep =>
      _step == _AdminLoginStep.authenticator ||
      _step == _AdminLoginStep.enrollment;

  @override
  void initState() {
    super.initState();
    if (widget.accessDenied) {
      _setInitialMessage('This account is not approved for staff access.');
    } else if (widget.sessionExpired) {
      _setInitialMessage(
        'The dashboard was locked after inactivity. Sign in again to continue.',
      );
    } else if (widget.mfaRequired) {
      _message = 'Enter your authenticator code to finish signing in.';
    }

    if (AppEnvironment.hasSupabaseConfig &&
        !widget.accessDenied &&
        AuthRepository().currentUser != null) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _resumeSignedInAdmin(),
      );
    }
  }

  void _setInitialMessage(String message) {
    _message = message;
    _messageIsError = true;
  }

  @override
  void dispose() {
    _emailController.dispose();
    _otpController.dispose();
    super.dispose();
  }

  Future<void> _resumeSignedInAdmin() async {
    if (!mounted) return;
    setState(() => _loading = true);
    final auth = AuthRepository();
    try {
      if (!await auth.isApprovedAdmin()) {
        await auth.signOut();
        throw const StoreValidationException(
          'This account is not approved for staff access.',
        );
      }
      if (auth.hasAal2Session) {
        await _openDashboard(auth);
      } else {
        await _prepareMfa(auth);
      }
    } catch (error) {
      _showError(error);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _continue() async {
    if (!_formKey.currentState!.validate()) return;

    if (!AppEnvironment.hasSupabaseConfig) {
      if (!AppEnvironment.allowAdminDemo) return;
      ref
          .read(storeProvider.notifier)
          .loginDemo(email: _emailController.text, isAdmin: true);
      if (mounted) context.go('/dashboard');
      return;
    }

    setState(() {
      _loading = true;
      _message = null;
      _messageIsError = false;
    });
    final auth = AuthRepository();
    try {
      switch (_step) {
        case _AdminLoginStep.email:
          await auth.sendEmailOtp(
            _emailController.text,
            shouldCreateUser: false,
          );
          if (mounted) {
            setState(() {
              _step = _AdminLoginStep.emailOtp;
              _message = 'A six-digit code was sent to your staff email.';
            });
          }
        case _AdminLoginStep.emailOtp:
          await auth.verifyEmailOtp(
            email: _emailController.text,
            token: _otpController.text,
          );
          if (!await auth.isApprovedAdmin()) {
            await auth.signOut();
            throw const StoreValidationException(
              'This account is not approved for staff access.',
            );
          }
          _otpController.clear();
          await _prepareMfa(auth);
        case _AdminLoginStep.authenticator:
        case _AdminLoginStep.enrollment:
          final factorId = _mfaFactorId;
          if (factorId == null) {
            throw const AuthException(
              'Authenticator setup expired. Sign in again.',
            );
          }
          await auth.verifyAdminMfa(
            factorId: factorId,
            code: _otpController.text,
          );
          await _openDashboard(auth);
      }
    } catch (error) {
      _showError(error);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _prepareMfa(AuthRepository auth) async {
    final challenge = await auth.prepareAdminMfa();
    if (!mounted) return;
    setState(() {
      _mfaFactorId = challenge.factorId;
      _mfaSecret = challenge.enrollmentSecret;
      _step = challenge.isEnrollment
          ? _AdminLoginStep.enrollment
          : _AdminLoginStep.authenticator;
      _message = challenge.isEnrollment
          ? 'Authenticator setup is required for this staff account.'
          : 'Enter the current code from your authenticator app.';
      _messageIsError = false;
    });
  }

  Future<void> _openDashboard(AuthRepository auth) async {
    if (!auth.hasAal2Session) {
      throw const AuthException('Authenticator verification is required.');
    }
    final bundle = await SupabaseStoreRepository().loadStore();
    if (!bundle.isAdmin) {
      await auth.signOut();
      throw const StoreValidationException(
        'This account is not approved for staff access.',
      );
    }
    ref.read(storeProvider.notifier).hydrateRemoteBundle(bundle);
    if (mounted) context.go('/dashboard');
  }

  void _showError(Object error) {
    if (!mounted) return;
    final message = switch (error) {
      StoreValidationException() => error.message,
      AuthException(statusCode: '429') =>
        'Too many attempts. Wait a few minutes and try again.',
      AuthException() when _isMfaStep =>
        'That authenticator code was not accepted. Check the code and try again.',
      AuthException() when _step == _AdminLoginStep.emailOtp =>
        'That email code was not accepted or has expired. Request a new code.',
      _ => 'Could not sign in. Check the details and try again.',
    };
    setState(() {
      _message = message;
      _messageIsError = true;
    });
  }

  Future<void> _useAnotherEmail() async {
    setState(() => _loading = true);
    try {
      if (AppEnvironment.hasSupabaseConfig &&
          AuthRepository().currentUser != null) {
        await AuthRepository().signOut();
      }
      ref.read(storeProvider.notifier).logout();
      _emailController.clear();
      _otpController.clear();
      if (mounted) {
        setState(() {
          _step = _AdminLoginStep.email;
          _mfaFactorId = null;
          _mfaSecret = null;
          _message = null;
          _messageIsError = false;
        });
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String get _buttonLabel {
    if (!AppEnvironment.hasSupabaseConfig) {
      return AppEnvironment.allowAdminDemo
          ? 'Open staff dashboard demo'
          : 'Production configuration required';
    }
    return switch (_step) {
      _AdminLoginStep.email => 'Send secure code',
      _AdminLoginStep.emailOtp => 'Verify email',
      _AdminLoginStep.authenticator => 'Verify and open dashboard',
      _AdminLoginStep.enrollment => 'Finish secure setup',
    };
  }

  @override
  Widget build(BuildContext context) {
    final configured = AppEnvironment.hasSupabaseConfig;
    return Scaffold(
      backgroundColor: AppColors.canvas,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.xxl),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 500),
              child: Card(
                elevation: 0,
                color: AppColors.surface,
                shape: RoundedRectangleBorder(
                  side: const BorderSide(color: AppColors.outline),
                  borderRadius: BorderRadius.circular(AppRadii.xxl),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.xxxl),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const KoyasLogo(),
                        const SizedBox(height: AppSpacing.xxxl),
                        Text(
                          'Staff sign in',
                          style: Theme.of(context).textTheme.headlineLarge,
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        Text(
                          'Manage Koyas orders, products and stock from your browser.',
                          style: Theme.of(context).textTheme.bodyLarge
                              ?.copyWith(color: AppColors.inkSecondary),
                        ),
                        const SizedBox(height: AppSpacing.xxl),
                        TextFormField(
                          key: const Key('admin-email'),
                          controller: _emailController,
                          enabled: _step == _AdminLoginStep.email,
                          keyboardType: TextInputType.emailAddress,
                          autofillHints: const [AutofillHints.email],
                          decoration: const InputDecoration(
                            labelText: 'Staff email address',
                            prefixIcon: Icon(Icons.badge_outlined),
                          ),
                          validator: (value) {
                            final email = value?.trim() ?? '';
                            if (!email.contains('@') || !email.contains('.')) {
                              return 'Enter a valid email address';
                            }
                            return null;
                          },
                        ),
                        if (_step == _AdminLoginStep.enrollment) ...[
                          const SizedBox(height: AppSpacing.lg),
                          Container(
                            padding: const EdgeInsets.all(AppSpacing.lg),
                            decoration: BoxDecoration(
                              color: AppColors.brandSoft,
                              borderRadius: BorderRadius.circular(AppRadii.lg),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Set up an authenticator',
                                  style: Theme.of(
                                    context,
                                  ).textTheme.titleMedium,
                                ),
                                const SizedBox(height: AppSpacing.sm),
                                const Text(
                                  'In Google Authenticator, Microsoft Authenticator, or another TOTP app, add an account manually. Use this setup key:',
                                ),
                                const SizedBox(height: AppSpacing.md),
                                SelectableText(
                                  _mfaSecret ?? '',
                                  key: const Key('admin-mfa-secret'),
                                  style: Theme.of(context).textTheme.titleMedium
                                      ?.copyWith(letterSpacing: 1.5),
                                ),
                                const SizedBox(height: AppSpacing.sm),
                                const Text(
                                  'Choose time-based and 6 digits, then enter the current code below. Keep this key private.',
                                ),
                              ],
                            ),
                          ),
                        ],
                        if (_step == _AdminLoginStep.emailOtp ||
                            _isMfaStep) ...[
                          const SizedBox(height: AppSpacing.lg),
                          TextFormField(
                            key: Key(
                              _isMfaStep ? 'admin-mfa-code' : 'admin-otp',
                            ),
                            controller: _otpController,
                            maxLength: 6,
                            keyboardType: TextInputType.number,
                            autofillHints: const [AutofillHints.oneTimeCode],
                            decoration: InputDecoration(
                              labelText: _isMfaStep
                                  ? 'Authenticator code'
                                  : 'Email verification code',
                              prefixIcon: const Icon(Icons.password_rounded),
                            ),
                            validator: (value) =>
                                RegExp(r'^\d{6}$').hasMatch(value?.trim() ?? '')
                                ? null
                                : 'Enter the 6-digit code',
                          ),
                        ],
                        if (_message != null) ...[
                          const SizedBox(height: AppSpacing.md),
                          Text(
                            _message!,
                            key: const Key('admin-login-message'),
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(
                                  color: _messageIsError
                                      ? AppColors.error
                                      : AppColors.success,
                                ),
                          ),
                        ],
                        const SizedBox(height: AppSpacing.lg),
                        KoyasButton(
                          key: const Key('admin-login'),
                          label: _buttonLabel,
                          loading: _loading,
                          icon: Icons.admin_panel_settings_outlined,
                          onPressed: configured || AppEnvironment.allowAdminDemo
                              ? _continue
                              : null,
                        ),
                        if (_step != _AdminLoginStep.email) ...[
                          const SizedBox(height: AppSpacing.sm),
                          TextButton(
                            key: const Key('admin-use-another-email'),
                            onPressed: _loading ? null : _useAnotherEmail,
                            child: const Text('Use another staff email'),
                          ),
                        ],
                        const SizedBox(height: AppSpacing.lg),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(
                              Icons.lock_outline_rounded,
                              size: 18,
                              color: AppColors.inkSecondary,
                            ),
                            const SizedBox(width: AppSpacing.sm),
                            Expanded(
                              child: Text(
                                configured
                                    ? 'Approved staff, email verification, and an authenticator code are all required. The dashboard locks after inactivity.'
                                    : AppEnvironment.allowAdminDemo
                                    ? 'Demo mode uses sample data and cannot change the live store.'
                                    : 'This release is locked because Supabase production configuration is missing.',
                                style: Theme.of(context).textTheme.bodySmall
                                    ?.copyWith(color: AppColors.inkSecondary),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
