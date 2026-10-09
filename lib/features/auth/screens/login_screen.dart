import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/config/app_environment.dart';
import '../../../core/services/network_status.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_motion.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/koyas_button.dart';
import '../../../core/widgets/koyas_logo.dart';
import '../data/auth_repository.dart';
import '../data/otp_send_limiter.dart';
import '../../store/providers/store_provider.dart';
import '../../store/data/supabase_store_repository.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({
    super.key,
    this.initialMessage,
    this.authRepository,
    this.loadStore,
  });

  final String? initialMessage;
  final AuthRepository? authRepository;
  final Future<RemoteStoreBundle> Function()? loadStore;

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
  bool _verified = false;
  bool _loading = false;
  bool _loadingStore = false;
  bool _messageIsError = false;
  String? _authMessage;
  AuthRepository? _auth;
  Timer? _cooldownTimer;
  int _resendSeconds = 0;

  bool get _remote => _auth != null;

  @override
  void initState() {
    super.initState();
    _authMessage = widget.initialMessage;
    _auth =
        widget.authRepository ??
        (AppEnvironment.hasSupabaseConfig ? AuthRepository() : null);
    if (_remote) {
      _emailController.text = _auth!.currentUser?.email ?? '';
      _verified = _auth!.currentUser != null;
    }
  }

  @override
  void dispose() {
    _cooldownTimer?.cancel();
    _emailController.dispose();
    _otpController.dispose();
    super.dispose();
  }

  Future<void> _continue() async {
    if (_loading) return;
    if (!_verified && !_formKey.currentState!.validate()) return;
    FocusManager.instance.primaryFocus?.unfocus();
    if (_remote) {
      setState(() {
        _loading = true;
        _authMessage = null;
        _messageIsError = false;
      });
      try {
        if (_verified) {
          await _completeRemoteSignIn();
        } else if (!_otpSent) {
          await _auth!.sendEmailOtp(_emailController.text);
          if (mounted) {
            setState(() {
              _otpSent = true;
              _authMessage = 'A six-digit code was sent to your email.';
            });
          }
        } else {
          await _auth!.verifyEmailOtp(
            email: _emailController.text,
            token: _otpController.text,
          );
          if (!mounted) return;
          setState(() {
            _verified = true;
            _otpController.clear();
          });
          await _completeRemoteSignIn();
        }
      } catch (error) {
        _showError(error);
      } finally {
        if (mounted) {
          setState(() => _loading = false);
          _updateCooldown();
        }
      }
      return;
    }
    if (!AppEnvironment.allowCustomerDemo) {
      setState(() {
        _authMessage =
            'Koya Stores is temporarily unavailable. Please try again later.';
        _messageIsError = true;
      });
      return;
    }
    ref.read(storeProvider.notifier).loginDemo(email: _emailController.text);
    context.go('/home');
  }

  Future<void> _completeRemoteSignIn() async {
    final userId = _auth!.currentUser?.id;
    if (userId == null) {
      if (mounted) {
        setState(() {
          _verified = false;
          _otpSent = false;
        });
      }
      throw const AuthException(
        'Your session expired. Request a new email code.',
      );
    }
    if (mounted) setState(() => _loadingStore = true);
    final bundle =
        await (widget.loadStore ?? SupabaseStoreRepository().loadStore)();
    if (!mounted) return;
    if (_auth!.currentUser?.id != userId || bundle.profile.id != userId) {
      setState(() {
        _verified = false;
        _otpSent = false;
      });
      throw const AuthException('Your session changed. Sign in again.');
    }
    ref.read(storeProvider.notifier).hydrateRemoteBundle(bundle);
    context.go('/home');
  }

  void _showError(Object error) {
    if (!mounted) return;
    if (_loadingStore && _auth!.currentUser == null) {
      _verified = false;
      _otpSent = false;
    }
    final message = switch (error) {
      OtpCooldownException() => error.message,
      AuthException(statusCode: '429') =>
        'Too many attempts. Please wait a few minutes and try again.',
      _ when _loadingStore && _verified =>
        'You are signed in, but the store could not load. Tap Retry opening store.',
      AuthException() when !_verified && _loadingStore =>
        'Your session expired. Request a new email code.',
      TimeoutException() =>
        'This is taking longer than expected. Please try again.',
      _ when _otpSent =>
        'That code was not accepted or has expired. Check it or request a new code.',
      _ => 'Could not send a code. Please try again shortly.',
    };
    setState(() {
      _authMessage = connectionFailureMessage(error, message);
      _messageIsError = true;
      _loadingStore = false;
    });
  }

  void _updateCooldown() {
    _cooldownTimer?.cancel();
    if (!mounted || !_remote) return;
    setState(
      () => _resendSeconds = _auth!.otpResendSeconds(_emailController.text),
    );
    if (_resendSeconds == 0) return;
    _cooldownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(
        () => _resendSeconds = _auth!.otpResendSeconds(_emailController.text),
      );
      if (_resendSeconds == 0) timer.cancel();
    });
  }

  Future<void> _resendCode() async {
    if (_loading || _resendSeconds > 0) return;
    setState(() {
      _loading = true;
      _authMessage = null;
      _messageIsError = false;
    });
    try {
      await _auth!.sendEmailOtp(_emailController.text);
      if (mounted) {
        setState(
          () => _authMessage =
              'A new code was sent. Enter the latest code from your email.',
        );
      }
    } catch (error) {
      _showError(error);
    } finally {
      if (mounted) {
        setState(() => _loading = false);
        _updateCooldown();
      }
    }
  }

  Future<void> _changeEmail() async {
    if (_loading) return;
    setState(() => _loading = true);
    try {
      if (_auth?.currentUser != null) {
        await _auth!.signOut();
        if (!mounted) return;
        ref.read(storeProvider.notifier).logout();
      }
      if (!mounted) return;
      _cooldownTimer?.cancel();
      setState(() {
        _otpSent = false;
        _verified = false;
        _loadingStore = false;
        _otpController.clear();
        _emailController.clear();
        _authMessage = null;
        _messageIsError = false;
        _resendSeconds = 0;
      });
    } catch (error) {
      _showError(error);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _openPlayReviewLogin() async {
    if (_loading) return;
    final credentials = await showDialog<_PasswordCredentials>(
      context: context,
      animationStyle: AppMotion.dialogStyle(context),
      builder: (context) => const _PlayReviewLoginDialog(),
    );
    if (credentials == null || !mounted) return;
    setState(() {
      _loading = true;
      _authMessage = null;
      _messageIsError = false;
    });
    try {
      await _auth!.signInWithPassword(
        email: credentials.email,
        password: credentials.password,
      );
      if (!mounted) return;
      setState(() {
        _verified = true;
        _emailController.text = _auth!.currentUser?.email ?? credentials.email;
      });
      await _completeRemoteSignIn();
    } catch (error) {
      if (mounted) {
        if (_verified) {
          _showError(error);
        } else {
          setState(() {
            _authMessage = connectionFailureMessage(
              error,
              'Reviewer credentials were not accepted. Check them and try again.',
            );
            _messageIsError = true;
          });
        }
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
    try {
      if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
        throw StateError('Could not open privacy policy');
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Privacy policy could not be opened. Please try again.',
            ),
          ),
        );
      }
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
                    Row(
                      children: [
                        const Expanded(
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.centerLeft,
                              child: KoyasLogo(),
                            ),
                          ),
                        ),
                        const SizedBox(width: AppSpacing.md),
                        ExcludeSemantics(
                          child: Image.asset(
                            'assets/category_images/fresh-produce.png',
                            width: 96,
                            height: 140,
                            fit: BoxFit.contain,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.xxl),
                    Text(
                      'Groceries made simple.',
                      style: Theme.of(context).textTheme.displayLarge?.copyWith(
                        fontSize: MediaQuery.sizeOf(context).width < 360
                            ? 28
                            : 32,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    Text(
                      'Sign in to shop, schedule pickup or arrange home delivery.',
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        color: AppColors.of(context).inkSecondary,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xxxl),
                    TextFormField(
                      key: const Key('login-email'),
                      controller: _emailController,
                      readOnly: _otpSent || _verified || _loading,
                      keyboardType: TextInputType.emailAddress,
                      textInputAction: TextInputAction.done,
                      autocorrect: false,
                      enableSuggestions: false,
                      onFieldSubmitted: (_) => _continue(),
                      autofillHints: const [AutofillHints.email],
                      decoration: const InputDecoration(
                        labelText: 'Email address',
                        prefixIcon: Icon(Icons.mail_outline_rounded),
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
                    if (_otpSent && !_verified) ...[
                      const SizedBox(height: AppSpacing.lg),
                      TextFormField(
                        key: const Key('login-otp'),
                        controller: _otpController,
                        enabled: !_loading,
                        maxLength: 6,
                        keyboardType: TextInputType.number,
                        textInputAction: TextInputAction.done,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                        ],
                        onFieldSubmitted: (_) => _continue(),
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
                      TextButton(
                        key: const Key('login-resend-code'),
                        onPressed: _loading || _resendSeconds > 0
                            ? null
                            : _resendCode,
                        child: Text(
                          _resendSeconds > 0
                              ? 'Resend code in ${_resendSeconds}s'
                              : 'Resend email code',
                        ),
                      ),
                    ],
                    if (_otpSent || _verified)
                      TextButton(
                        key: const Key('login-change-email'),
                        onPressed: _loading ? null : _changeEmail,
                        child: const Text('Use another email'),
                      ),
                    if (_authMessage != null) ...[
                      const SizedBox(height: AppSpacing.md),
                      Semantics(
                        liveRegion: true,
                        child: Text(
                          _authMessage!,
                          key: const Key('login-message'),
                          style: Theme.of(context).textTheme.bodyMedium
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
                      key: const Key('customer-login'),
                      label: _remote
                          ? (_verified
                                ? (_messageIsError
                                      ? 'Retry opening store'
                                      : 'Open store')
                                : _otpSent
                                ? 'Verify and continue'
                                : _resendSeconds > 0
                                ? 'Request code in ${_resendSeconds}s'
                                : 'Send secure code')
                          : 'Continue to Koya Stores',
                      loading: _loading,
                      icon: Icons.arrow_forward_rounded,
                      onPressed: !_otpSent && !_verified && _resendSeconds > 0
                          ? null
                          : _continue,
                    ),
                    if (_remote &&
                        !_verified &&
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
                    if (!_remote && AppEnvironment.allowCustomerDemo)
                      Container(
                        padding: const EdgeInsets.all(AppSpacing.lg),
                        decoration: BoxDecoration(
                          color: AppColors.of(context).brandSoft,
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
