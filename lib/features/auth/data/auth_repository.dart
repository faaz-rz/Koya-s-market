import 'package:supabase_flutter/supabase_flutter.dart';
import '../../store/data/supabase_store_repository.dart';
import 'otp_send_limiter.dart';

class AccountDeletionException implements Exception {
  const AccountDeletionException(
    this.message, {
    this.code = 'deletion_unavailable',
    this.retryAfter = Duration.zero,
  });

  final String message;
  final String code;
  final Duration retryAfter;
  bool get hasActiveOrders => code == 'active_orders';
  bool get needsNewCode => const {
    'otp_expired',
    'attempts_exhausted',
    'deletion_unavailable',
    'active_orders',
  }.contains(code);

  @override
  String toString() => message;
}

class AccountDeletionChallenge {
  const AccountDeletionChallenge({
    required this.id,
    required this.expiresAt,
    required this.emailHint,
    this.retryAfter = const Duration(seconds: 60),
  });

  final String id;
  final DateTime expiresAt;
  final String emailHint;
  final Duration retryAfter;
}

class AdminMfaChallenge {
  const AdminMfaChallenge({required this.factorId, this.enrollmentSecret});

  final String factorId;
  final String? enrollmentSecret;

  bool get isEnrollment => enrollmentSecret != null;
}

class AuthRepository {
  AuthRepository({
    SupabaseClient? client,
    this.requestTimeout = const Duration(seconds: 20),
  }) : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;
  final Duration requestTimeout;
  static final otpLimiter = OtpSendLimiter();
  static final _deletedClients = Expando<bool>();

  static bool takeAccountDeleted(SupabaseClient client) {
    final deleted = _deletedClients[client] == true;
    _deletedClients[client] = null;
    return deleted;
  }

  User? get currentUser => _client.auth.currentUser;

  bool get hasAal2Session =>
      _client.auth.mfa.getAuthenticatorAssuranceLevel().currentLevel ==
      AuthenticatorAssuranceLevels.aal2;

  Future<void> sendEmailOtp(String email, {bool shouldCreateUser = true}) =>
      otpLimiter.send(
        email,
        () => _client.auth
            .signInWithOtp(
              email: email.trim(),
              shouldCreateUser: shouldCreateUser,
            )
            .timeout(requestTimeout),
      );

  Future<User> verifyEmailOtp({
    required String email,
    required String token,
  }) async {
    final response = await _client.auth
        .verifyOTP(
          email: email.trim(),
          token: token.trim(),
          type: OtpType.email,
        )
        .timeout(requestTimeout);
    final user = response.user;
    if (user == null) throw const AuthException('Unable to verify this code.');
    return user;
  }

  Future<User> signInWithPassword({
    required String email,
    required String password,
  }) async {
    final response = await _client.auth
        .signInWithPassword(email: email.trim(), password: password)
        .timeout(requestTimeout);
    final user = response.user;
    if (user == null) throw const AuthException('Unable to sign in.');
    return user;
  }

  Future<bool> isApprovedAdmin() async {
    final user = currentUser;
    if (user == null) return false;
    final row = await _client
        .from('admins')
        .select('user_id')
        .eq('user_id', user.id)
        .eq('active', true)
        .maybeSingle()
        .timeout(requestTimeout);
    return row != null;
  }

  Future<AdminMfaChallenge> prepareAdminMfa() async {
    if (currentUser == null) {
      throw const AuthException('Sign in again before setting up MFA.');
    }

    final factors = await _client.auth.mfa.listFactors().timeout(
      requestTimeout,
    );
    if (factors.totp.isNotEmpty) {
      return AdminMfaChallenge(factorId: factors.totp.first.id);
    }

    // An interrupted first-time setup leaves an unverified factor whose
    // secret cannot be retrieved. Remove it before issuing a fresh secret.
    for (final factor in factors.all.where(
      (factor) =>
          factor.factorType == FactorType.totp &&
          factor.status == FactorStatus.unverified,
    )) {
      await _client.auth.mfa.unenroll(factor.id).timeout(requestTimeout);
    }

    final response = await _client.auth.mfa
        .enroll(
          factorType: FactorType.totp,
          issuer: 'Koya Stores Admin',
          friendlyName: 'Koya Stores staff authenticator',
        )
        .timeout(requestTimeout);
    final secret = response.totp?.secret;
    if (secret == null || secret.isEmpty) {
      throw const AuthException('Could not create an authenticator secret.');
    }
    return AdminMfaChallenge(factorId: response.id, enrollmentSecret: secret);
  }

  Future<void> verifyAdminMfa({
    required String factorId,
    required String code,
  }) async {
    await _client.auth.mfa
        .challengeAndVerify(factorId: factorId, code: code.trim())
        .timeout(requestTimeout);
    if (!hasAal2Session) {
      throw const AuthException('Authenticator verification was incomplete.');
    }
  }

  Future<void> signOut() async {
    SupabaseStoreRepository.clearReadCache(_client);
    await _client.auth.signOut().timeout(requestTimeout);
  }

  Future<Map> _deletionRequest(Map<String, dynamic> body) async {
    if (_client.auth.currentUser == null) {
      throw const AccountDeletionException(
        'Sign in again to delete your account.',
        code: 'invalid_session',
      );
    }
    try {
      final response = await _client.functions
          // Never send legacy DELETE: an older backend would immediately
          // delete even when this request only asks it to send an email code.
          .invoke(
            'delete-account',
            body: {'confirmation': 'DELETE_WITH_OTP', ...body},
          )
          .timeout(const Duration(seconds: 30));
      if (response.status != 200 || response.data is! Map) {
        throw _deletionError(response.data, response.status);
      }
      return response.data as Map;
    } on FunctionException catch (error) {
      throw _deletionError(error.details, error.status);
    }
  }

  Future<AccountDeletionChallenge> requestAccountDeletionOtp() async {
    final userId = currentUser?.id;
    final data = await _deletionRequest({'action': 'request_otp'});
    final expires = DateTime.tryParse(data['expires_at']?.toString() ?? '');
    if (data['sent'] != true ||
        data['challenge_id'] is! String ||
        expires == null ||
        userId != currentUser?.id) {
      throw const AccountDeletionException(
        'A deletion code could not be requested. Please try again.',
      );
    }
    return AccountDeletionChallenge(
      id: data['challenge_id'] as String,
      expiresAt: expires,
      emailHint: data['email_hint'] as String? ?? 'your registered email',
      retryAfter: Duration(
        seconds: (data['retry_after'] as num? ?? 60).toInt().clamp(0, 3600),
      ),
    );
  }

  Future<void> deleteAccount({
    required String challengeId,
    required String otp,
  }) async {
    final userId = currentUser?.id;
    if (!RegExp(r'^\d{6,8}$').hasMatch(otp.trim())) {
      throw const AccountDeletionException(
        'Enter the code from your email.',
        code: 'invalid_code',
      );
    }
    final data = await _deletionRequest({
      'action': 'confirm_delete',
      'challenge_id': challengeId,
      'otp': otp.trim(),
    });
    if (data['deleted'] != true) throw _deletionError(data, 503);
    if (currentUser?.id != userId) {
      throw const AccountDeletionException(
        'The previous account was deleted. Your current sign-in was not changed.',
        code: 'account_changed',
      );
    }
    _deletedClients[_client] = true;
    SupabaseStoreRepository.clearReadCache(_client);
    try {
      // The SDK clears local credentials before attempting remote sign-out.
      await _client.auth
          .signOut(scope: SignOutScope.local)
          .timeout(const Duration(seconds: 10));
    } catch (_) {
      // Backend deletion already committed. A logout network error must not
      // incorrectly tell the customer their account still exists.
    }
  }

  AccountDeletionException _deletionError(dynamic details, int status) {
    final code = status == 401
        ? 'invalid_session'
        : details is Map
        ? details['code']?.toString() ?? 'deletion_unavailable'
        : 'deletion_unavailable';
    final retry = details is Map ? details['retry_after'] : null;
    const messages = {
      'invalid_session':
          'Your session expired. Sign in again before deleting your account.',
      'verified_email_required':
          'Verify your email before deleting your account, or use the web request page.',
      'staff_account':
          'Staff accounts must be removed by an authorized administrator.',
      'active_orders':
          'Complete or cancel your active orders before deleting your account.',
      'rate_limited': 'Too many requests. Wait before trying again.',
      'deletion_in_progress':
          'Account deletion is already being processed. Please wait.',
      'email_unavailable':
          'The email could not be sent. Please wait and try again.',
      'verification_unavailable':
          'Verification is temporarily unavailable. Please try again.',
      'invalid_code':
          'That code is incorrect or expired. Check your latest email.',
      'otp_expired': 'This deletion code has expired. Request a new code.',
      'attempts_exhausted': 'Too many incorrect attempts. Request a new code.',
    };
    return AccountDeletionException(
      messages[code] ??
          'Deletion could not be completed. Request a new code or use the web request page.',
      code: code,
      retryAfter: Duration(
        seconds: retry is num ? retry.toInt().clamp(0, 3600) : 0,
      ),
    );
  }
}
