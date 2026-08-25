import 'package:supabase_flutter/supabase_flutter.dart';

class AdminMfaChallenge {
  const AdminMfaChallenge({required this.factorId, this.enrollmentSecret});

  final String factorId;
  final String? enrollmentSecret;

  bool get isEnrollment => enrollmentSecret != null;
}

class AuthRepository {
  AuthRepository({SupabaseClient? client})
    : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  User? get currentUser => _client.auth.currentUser;

  bool get hasAal2Session =>
      _client.auth.mfa.getAuthenticatorAssuranceLevel().currentLevel ==
      AuthenticatorAssuranceLevels.aal2;

  Future<void> sendEmailOtp(String email, {bool shouldCreateUser = true}) =>
      _client.auth.signInWithOtp(
        email: email.trim(),
        shouldCreateUser: shouldCreateUser,
      );

  Future<User> verifyEmailOtp({
    required String email,
    required String token,
  }) async {
    final response = await _client.auth.verifyOTP(
      email: email.trim(),
      token: token.trim(),
      type: OtpType.email,
    );
    final user = response.user;
    if (user == null) throw const AuthException('Unable to verify this code.');
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
        .maybeSingle();
    return row != null;
  }

  Future<AdminMfaChallenge> prepareAdminMfa() async {
    if (currentUser == null) {
      throw const AuthException('Sign in again before setting up MFA.');
    }

    final factors = await _client.auth.mfa.listFactors();
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
      await _client.auth.mfa.unenroll(factor.id);
    }

    final response = await _client.auth.mfa.enroll(
      factorType: FactorType.totp,
      issuer: 'Koya Stores Admin',
      friendlyName: 'Koya Stores staff authenticator',
    );
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
    await _client.auth.mfa.challengeAndVerify(
      factorId: factorId,
      code: code.trim(),
    );
    if (!hasAal2Session) {
      throw const AuthException('Authenticator verification was incomplete.');
    }
  }

  Future<void> signOut() => _client.auth.signOut();
}
