import '../../../core/config/usage_policy.dart';

class OtpCooldownException implements Exception {
  const OtpCooldownException(this.seconds);
  final int seconds;
  String get message =>
      'Please wait $seconds seconds before requesting another code.';
}

/// UX/bandwidth guard only. Supabase server rate limits + SMTP provider caps
/// are still mandatory; a modified client can bypass a local limiter.
class OtpSendLimiter {
  OtpSendLimiter({DateTime Function()? now}) : _now = now ?? DateTime.now;
  final DateTime Function() _now;
  final _lastSent = <String, DateTime>{};
  final _attempts = <DateTime>[];
  final _running = <String, Future<void>>{};

  int remainingSeconds(String email) {
    final now = _now();
    _attempts.removeWhere(
      (time) => now.difference(time) >= const Duration(hours: 1),
    );
    final previous = _lastSent[email.trim().toLowerCase()];
    var wait = previous == null
        ? 0
        : UsagePolicy.otpCooldown.inSeconds -
              now.difference(previous).inSeconds;
    if (_attempts.length >= UsagePolicy.otpAttemptsPerDeviceHour) {
      final hourlyWait = 3600 - now.difference(_attempts.first).inSeconds;
      if (hourlyWait > wait) wait = hourlyWait;
    }
    return wait > 0 ? wait : 0;
  }

  Future<void> send(String email, Future<void> Function() request) {
    final key = email.trim().toLowerCase();
    final running = _running[key];
    if (running != null) return running;
    final wait = remainingSeconds(key);
    if (wait > 0) return Future.error(OtpCooldownException(wait));
    final now = _now();
    _lastSent[key] = now;
    _attempts.add(now);
    // Retain cooldown even after a lost response: the email may have been sent.
    return _running[key] = Future<void>.sync(request).whenComplete(() {
      _running.remove(key);
    });
  }
}
