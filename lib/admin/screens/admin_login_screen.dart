import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/config/app_environment.dart';
import '../../core/services/network_status.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/widgets/koyas_button.dart';
import '../../core/widgets/koyas_logo.dart';
import '../../features/auth/data/auth_repository.dart';
import '../../features/auth/data/otp_send_limiter.dart';
import '../../features/store/data/supabase_store_repository.dart';
import '../../features/store/providers/store_provider.dart';

enum _AdminLoginStep { email, emailOtp, authenticator, enrollment }

class AdminLoginScreen extends ConsumerStatefulWidget {
  const AdminLoginScreen({
    this.accessDenied = false,
    this.mfaRequired = false,
    this.sessionExpired = false,
    this.authRepository,
    this.loadStore,
    super.key,
  });

  final bool accessDenied;
  final bool mfaRequired;
  final bool sessionExpired;
  final AuthRepository? authRepository;
  final Future<RemoteStoreBundle> Function()? loadStore;

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
  Timer? _resendTimer;
  int _resendSeconds = 0;

  bool get _remote =>
      widget.authRepository != null || AppEnvironment.hasSupabaseConfig;
  AuthRepository get _auth => widget.authRepository ?? AuthRepository();

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

    if (_remote && !widget.accessDenied && _auth.currentUser != null) {
      _emailController.text = _auth.currentUser!.email ?? '';
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
    _resendTimer?.cancel();
    _emailController.dispose();
    _otpController.dispose();
    super.dispose();
  }

  Future<void> _resumeSignedInAdmin() async {
    if (!mounted || _loading) return;
    setState(() => _loading = true);
    final auth = _auth;
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
    if (_loading) return;
    // A code may have succeeded before a later allowlist/MFA/store request
    // failed. Resume that session instead of replaying a consumed email code.
    if (_remote &&
        _auth.currentUser != null &&
        (!_isMfaStep || _auth.hasAal2Session)) {
      await _resumeSignedInAdmin();
      return;
    }
    if (!_formKey.currentState!.validate()) return;

    if (!_remote) {
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
    final auth = _auth;
    try {
      switch (_step) {
        case _AdminLoginStep.email:
          await auth.sendEmailOtp(
            _emailController.text,
            // Email verification creates the account; the database alone
            // decides whether a preapproved address receives staff access.
            shouldCreateUser: true,
          );
          if (mounted) {
            _startResendTimer();
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
    final userId = auth.currentUser?.id;
    final challenge = await auth.prepareAdminMfa();
    if (!mounted) return;
    if (userId == null || auth.currentUser?.id != userId) {
      throw const AuthException('Your session changed. Sign in again.');
    }
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
    final userId = auth.currentUser?.id;
    if (!auth.hasAal2Session) {
      throw const AuthException('Authenticator verification is required.');
    }
    final bundle =
        await (widget.loadStore ?? SupabaseStoreRepository().loadStore)();
    if (!mounted) return;
    if (userId == null ||
        auth.currentUser?.id != userId ||
        bundle.profile.id != userId ||
        !auth.hasAal2Session) {
      throw const AuthException('Your session changed. Sign in again.');
    }
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
      OtpCooldownException() => error.message,
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
      _message = connectionFailureMessage(error, message);
      _messageIsError = true;
      if (_remote && _isMfaStep && _auth.currentUser == null) {
        _step = _AdminLoginStep.email;
        _mfaFactorId = null;
        _mfaSecret = null;
        _otpController.clear();
        _message = 'Your session expired. Request a new email code to sign in.';
      }
    });
  }

  void _startResendTimer() {
    _resendTimer?.cancel();
    _resendSeconds = _auth.otpResendSeconds(_emailController.text);
    _resendTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(
        () => _resendSeconds = _auth.otpResendSeconds(_emailController.text),
      );
      if (_resendSeconds == 0) timer.cancel();
    });
  }

  Future<void> _resendCode() async {
    if (_loading || _resendSeconds > 0) return;
    setState(() => _loading = true);
    try {
      await _auth.sendEmailOtp(_emailController.text);
      if (!mounted) return;
      _startResendTimer();
      setState(() {
        _otpController.clear();
        _message = 'A new code was sent to your staff email.';
        _messageIsError = false;
      });
    } catch (error) {
      _showError(error);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _useAnotherEmail() async {
    setState(() => _loading = true);
    try {
      if (_remote && _auth.currentUser != null) {
        await _auth.signOut();
      }
      ref.read(storeProvider.notifier).logout();
      _emailController.clear();
      _otpController.clear();
      _resendTimer?.cancel();
      _resendSeconds = 0;
      if (mounted) {
        setState(() {
          _step = _AdminLoginStep.email;
          _mfaFactorId = null;
          _mfaSecret = null;
          _message = null;
          _messageIsError = false;
        });
      }
    } catch (error) {
      _showError(error);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String get _buttonLabel {
    if (!_remote) {
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
    final configured = _remote;
    return Scaffold(
      backgroundColor: AppColors.of(context).canvas,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.xxl),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 500),
              child: Card(
                elevation: 0,
                color: AppColors.of(context).surface,
                shape: RoundedRectangleBorder(
                  side: BorderSide(color: AppColors.of(context).outline),
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
                          'Manage Koya Stores orders, products and stock from your browser.',
                          style: Theme.of(context).textTheme.bodyLarge
                              ?.copyWith(
                                color: AppColors.of(context).inkSecondary,
                              ),
                        ),
                        const SizedBox(height: AppSpacing.xxl),
                        TextFormField(
                          key: const Key('admin-email'),
                          controller: _emailController,
                          enabled: !_loading && _step == _AdminLoginStep.email,
                          keyboardType: TextInputType.emailAddress,
                          autocorrect: false,
                          enableSuggestions: false,
                          autofillHints: const [AutofillHints.email],
                          decoration: const InputDecoration(
                            labelText: 'Staff email address',
                            prefixIcon: Icon(Icons.badge_outlined),
                          ),
                          validator: (value) {
                            final email = value?.trim() ?? '';
                            if (email.length > 254 ||
                                !RegExp(
                                  r'^[^\s@]+@[^\s@]+\.[^\s@]+$',
                                ).hasMatch(email)) {
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
                              color: AppColors.of(context).brandSoft,
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
                            enabled: !_loading,
                            maxLength: 6,
                            keyboardType: TextInputType.number,
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly,
                            ],
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
                          Semantics(
                            liveRegion: true,
                            child: Text(
                              _message!,
                              key: const Key('admin-login-message'),
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(
                                    color: _messageIsError
                                        ? AppColors.of(context).error
                                        : AppColors.of(context).success,
                                  ),
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
                        if (_step == _AdminLoginStep.emailOtp)
                          TextButton(
                            key: const Key('admin-resend-code'),
                            onPressed: _loading || _resendSeconds > 0
                                ? null
                                : _resendCode,
                            child: Text(
                              _resendSeconds > 0
                                  ? 'Resend code in ${_resendSeconds}s'
                                  : 'Resend email code',
                            ),
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
                            Icon(
                              Icons.lock_outline_rounded,
                              size: 18,
                              color: AppColors.of(context).inkSecondary,
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
                                    ?.copyWith(
                                      color: AppColors.of(context).inkSecondary,
                                    ),
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
