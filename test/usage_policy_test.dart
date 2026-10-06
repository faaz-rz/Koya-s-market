import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:koyas_supermarket/core/config/usage_policy.dart';
import 'package:koyas_supermarket/features/auth/data/otp_send_limiter.dart';

void main() {
  test(
    'OTP double taps share one normalized request and observe cooldown',
    () async {
      var now = DateTime.utc(2026, 9, 19), sent = 0;
      final limiter = OtpSendLimiter(now: () => now),
          pending = Completer<void>();
      final first = limiter.send(' Alice@example.com ', () {
        sent++;
        return pending.future;
      });
      final second = limiter.send('alice@example.com', () async {
        sent++;
      });
      expect(identical(first, second), true);
      pending.complete();
      await first;
      await expectLater(
        limiter.send('ALICE@example.com', () async {
          sent++;
        }),
        throwsA(isA<OtpCooldownException>()),
      );
      expect(sent, 1);
      now = now.add(const Duration(seconds: 60));
      await limiter.send('alice@example.com', () async {
        sent++;
      });
      expect(sent, 2);
    },
  );

  test(
    'lost email response retains cooldown instead of retrying automatically',
    () async {
      final limiter = OtpSendLimiter();
      await expectLater(
        limiter.send('a@b.test', () async => throw StateError('lost')),
        throwsStateError,
      );
      expect(limiter.remainingSeconds('a@b.test'), greaterThan(0));
      await expectLater(
        limiter.send('a@b.test', () async {}),
        throwsA(isA<OtpCooldownException>()),
      );
    },
  );

  test(
    'hourly send budget also applies across different email addresses',
    () async {
      var now = DateTime.utc(2026, 9, 19);
      final limiter = OtpSendLimiter(now: () => now);
      for (var i = 0; i < UsagePolicy.otpAttemptsPerDeviceHour; i++) {
        await limiter.send('$i@example.test', () async {});
      }
      await expectLater(
        limiter.send('next@example.test', () async {}),
        throwsA(isA<OtpCooldownException>()),
      );
      now = now.add(const Duration(hours: 1));
      await limiter.send('next@example.test', () async {});
    },
  );

  test(
    'poll policy is bounded with faster active-order/admin refresh and jitter',
    () {
      Duration delay({
        bool admin = false,
        bool active = false,
        int failures = 0,
        int jitter = 0,
        bool live = true,
      }) => UsagePolicy.pollDelay(
        admin: admin,
        activeOrder: active,
        failures: failures,
        jitterSeconds: jitter,
        live: live,
      );
      expect(delay(), const Duration(seconds: 120));
      expect(delay(admin: true), const Duration(seconds: 60));
      expect(delay(admin: true, live: false), const Duration(seconds: 5));
      expect(delay(admin: true, failures: 1), const Duration(seconds: 10));
      expect(
        delay(admin: true, live: false, jitter: 7),
        const Duration(seconds: 6),
      );
      expect(
        delay(admin: true, live: false, failures: 100),
        const Duration(seconds: 30),
      );
      expect(delay(active: true), const Duration(seconds: 30));
      expect(delay(live: false), const Duration(seconds: 30));
      expect(delay(live: false, failures: 1), const Duration(seconds: 60));
      expect(delay(failures: 1), const Duration(seconds: 240));
      expect(delay(jitter: 7), const Duration(seconds: 127));
      expect(delay(failures: 1000, jitter: 999), const Duration(minutes: 10));
      expect(delay(failures: -1, jitter: -3), const Duration(seconds: 120));
    },
  );
}
