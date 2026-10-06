/// Conservative defaults, not a guarantee of free-tier capacity.
abstract final class UsagePolicy {
  static const customerPoll = Duration(seconds: 120);
  static const activeOrderPoll = Duration(seconds: 30);
  static const adminFallbackPoll = Duration(seconds: 5);
  static const adminSafetyPoll = Duration(seconds: 60);
  static const adminMaximumBackoff = Duration(seconds: 30);
  static const customerFallbackPoll = Duration(seconds: 30);
  static const realtimeDebounce = Duration(seconds: 2);
  static const minimumRefreshGap = Duration(seconds: 3);
  static const orderDebounce = Duration(milliseconds: 100);
  static const orderRefreshGap = Duration(milliseconds: 500);
  static const maximumBackoff = Duration(minutes: 10);
  static const otpCooldown = Duration(seconds: 60);
  static const otpAttemptsPerDeviceHour = 8;
  static const imageDecodePixels = 512;
  static const imageCacheObjects = 350;
  static const optimizedImageMaxBytes = 150 * 1024;

  static Duration pollDelay({
    required bool admin,
    required bool activeOrder,
    required int failures,
    bool live = true,
    int jitterSeconds = 0,
  }) {
    final base = admin
        ? (live && failures == 0 ? adminSafetyPoll : adminFallbackPoll)
        : !live
        ? customerFallbackPoll
        : activeOrder
        ? activeOrderPoll
        : customerPoll;
    final maximum = admin && failures > 0
        ? adminMaximumBackoff
        : maximumBackoff;
    final seconds = (base.inSeconds * (1 << failures.clamp(0, 5))).clamp(
      0,
      maximum.inSeconds,
    );
    return Duration(
      seconds: (seconds + jitterSeconds.clamp(0, admin ? 1 : 7)).clamp(
        0,
        maximum.inSeconds,
      ),
    );
  }
}
