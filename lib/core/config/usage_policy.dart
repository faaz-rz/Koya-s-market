/// Conservative defaults, not a guarantee of free-tier capacity.
abstract final class UsagePolicy {
  static const customerPoll = Duration(seconds: 120);
  static const activeOrderPoll = Duration(seconds: 30);
  static const adminFallbackPoll = Duration(seconds: 30);
  static const customerFallbackPoll = Duration(seconds: 30);
  static const realtimeDebounce = Duration(seconds: 2);
  static const minimumRefreshGap = Duration(seconds: 3);
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
        ? adminFallbackPoll
        : !live
        ? customerFallbackPoll
        : activeOrder
        ? activeOrderPoll
        : customerPoll;
    final seconds = (base.inSeconds * (1 << failures.clamp(0, 5))).clamp(
      0,
      maximumBackoff.inSeconds,
    );
    return Duration(
      seconds: (seconds + jitterSeconds.clamp(0, 7)).clamp(
        0,
        maximumBackoff.inSeconds,
      ),
    );
  }
}
