import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/config/app_environment.dart';
import '../../../core/config/usage_policy.dart';
import '../../orders/models/order.dart';
import '../data/supabase_store_repository.dart';
import '../providers/store_provider.dart';
import '../providers/store_sync_health.dart';

/// One foreground channel delivers catalogue changes and authorized orders.
/// Conditional snapshots remain the source of truth, with polling if the live
/// connection fails. Hidden apps unsubscribe; checkout validates stock again.
class StoreRealtimeSync extends ConsumerStatefulWidget {
  const StoreRealtimeSync({required this.child, this.client, super.key});
  final Widget child;
  final SupabaseClient? client;
  @override
  ConsumerState<StoreRealtimeSync> createState() => _StoreRealtimeSyncState();
}

class _StoreRealtimeSyncState extends ConsumerState<StoreRealtimeSync>
    with WidgetsBindingObserver {
  RealtimeChannel? _channel;
  String? _channelUserId;
  bool? _channelAdmin;
  bool _live = false;
  Timer? _debounce;
  Timer? _poll;
  Timer? _channelRetry;
  DateTime? _nextPoll;
  int _channelFailures = 0;
  int _channelGeneration = 0;
  bool _refreshing = false;
  bool _foreground = true;
  bool _refreshAgain = false;
  bool _refreshAgainUrgent = false;
  int _failures = 0;
  DateTime? _lastRefresh;
  final _random = Random();
  SupabaseClient get _client => widget.client ?? Supabase.instance.client;

  @override
  void initState() {
    super.initState();
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    _foreground = lifecycle == null || lifecycle == AppLifecycleState.resumed;
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _start());
  }

  bool get _connected =>
      mounted &&
      (widget.client != null || AppEnvironment.hasSupabaseConfig) &&
      _client.auth.currentUser != null &&
      (_foreground || ref.read(storeProvider).isAdminAccount);

  void _start() {
    if (!_connected) {
      _poll?.cancel();
      _debounce?.cancel();
      _closeChannel();
      return;
    }
    final admin = ref.read(storeProvider).isAdminAccount;
    if (_channelUserId != _client.auth.currentUser!.id ||
        _channelAdmin != admin) {
      _closeChannel();
    }
    _subscribe();
    _schedulePoll();
  }

  bool _hasActiveOrder(StoreState store) => store.orders.any(
    (order) => !{
      OrderStatus.collected,
      OrderStatus.delivered,
      OrderStatus.cancelled,
      OrderStatus.rejected,
    }.contains(order.status),
  );

  void _subscribe() {
    if (!_connected || _channel != null) return;
    final client = _client;
    final userId = client.auth.currentUser!.id;
    final admin = ref.read(storeProvider).isAdminAccount;
    final channel = client.channel(
      'store-live-${identityHashCode(this)}-${++_channelGeneration}',
    );
    _channel = channel;
    _channelUserId = userId;
    _channelAdmin = admin;
    ref.read(storeSyncHealthProvider.notifier).connection(false);
    channel
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'products',
          callback: (_) => _liveChange(),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'orders',
          filter: admin
              ? null
              : PostgresChangeFilter(
                  type: PostgresChangeFilterType.eq,
                  column: 'user_id',
                  value: userId,
                ),
          callback: (_) => _liveChange(urgent: true),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'store_settings',
          callback: (_) => _liveChange(),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'offers',
          callback: (_) => _liveChange(),
        )
        .subscribe((status, error) {
          if (!_connected || !identical(_channel, channel)) return;
          _live = status == RealtimeSubscribeStatus.subscribed;
          ref.read(storeSyncHealthProvider.notifier).connection(_live);
          if (_live) {
            _failures = 0;
            _channelRetry?.cancel();
          } else {
            _retryChannel(channel);
          }
          _schedulePoll();
          // Refresh after joining/rejoining to cover the subscription gap.
          if (_live) _scheduleRefresh(urgent: admin);
        });
  }

  void _liveChange({bool urgent = false}) {
    _channelFailures = 0;
    _scheduleRefresh(urgent: urgent);
  }

  void _retryChannel(RealtimeChannel failedChannel) {
    if (!_connected || _channelRetry?.isActive == true) return;
    final seconds = min(30, 1 << _channelFailures.clamp(0, 5));
    _channelFailures++;
    _channelRetry = Timer(Duration(seconds: seconds), () {
      if (!_connected || _live || !identical(_channel, failedChannel)) return;
      _closeChannel();
      _subscribe();
    });
  }

  void _schedulePoll({bool reset = false}) {
    if (!_connected) return;
    final store = ref.read(storeProvider);
    final activeOrder = _hasActiveOrder(store);
    final delay = UsagePolicy.pollDelay(
      admin: store.isAdminAccount,
      activeOrder: activeOrder,
      failures: _failures,
      live: _live,
      jitterSeconds: _random.nextInt(8),
    );
    final next = DateTime.now().add(delay);
    // Repeated failed joins must not keep postponing the backup read.
    if (!reset &&
        _poll?.isActive == true &&
        _nextPoll != null &&
        !_nextPoll!.isAfter(next)) {
      return;
    }
    _poll?.cancel();
    _nextPoll = next;
    _poll = Timer(delay, _refresh);
  }

  void _scheduleRefresh({bool urgent = false}) {
    if (!_connected) return;
    if (_refreshing) {
      _refreshAgain = true;
      _refreshAgainUrgent = _refreshAgainUrgent || urgent;
      return;
    }
    if (_debounce?.isActive == true && !urgent) return;
    _debounce?.cancel();
    final gap = urgent
        ? UsagePolicy.orderRefreshGap
        : UsagePolicy.minimumRefreshGap;
    final debounce = urgent
        ? UsagePolicy.orderDebounce
        : UsagePolicy.realtimeDebounce;
    final elapsed = _lastRefresh == null
        ? gap
        : DateTime.now().difference(_lastRefresh!);
    final delay = max(
      debounce.inMilliseconds,
      gap.inMilliseconds - elapsed.inMilliseconds,
    );
    _debounce = Timer(Duration(milliseconds: delay), _refresh);
  }

  Future<void> _refresh() async {
    if (!_connected) return;
    if (_refreshing) {
      _refreshAgain = true;
      return;
    }
    _refreshing = true;
    final userId = _client.auth.currentUser!.id;
    try {
      final bundle = await SupabaseStoreRepository(
        client: _client,
      ).loadStore().timeout(const Duration(seconds: 20));
      if (_connected && _client.auth.currentUser?.id == userId) {
        ref.read(storeProvider.notifier).hydrateRemoteBundle(bundle);
        _failures = 0;
        ref.read(storeSyncHealthProvider.notifier).synced();
        _start();
      }
    } catch (_) {
      _failures++;
      if (mounted) ref.read(storeSyncHealthProvider.notifier).failed(_failures);
    } finally {
      _refreshing = false;
      _lastRefresh = DateTime.now();
      _schedulePoll(reset: true);
      if (_refreshAgain) {
        _refreshAgain = false;
        final urgent = _refreshAgainUrgent;
        _refreshAgainUrgent = false;
        _scheduleRefresh(urgent: urgent);
      }
    }
  }

  void _closeChannel() {
    _channelRetry?.cancel();
    final channel = _channel;
    _channel = null;
    _channelUserId = null;
    _channelAdmin = null;
    _live = false;
    if (channel != null) {
      unawaited(_client.removeChannel(channel).catchError((_) => 'error'));
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (_foreground) {
      _start();
      _scheduleRefresh(urgent: ref.read(storeProvider).isAdminAccount);
    } else if (ref.read(storeProvider).isAdminAccount) {
      // An open staff tab remains an order terminal even when another tab has
      // focus. Browsers may suspend a tab; reconnect/resume closes that gap.
      _start();
    } else {
      _poll?.cancel();
      _debounce?.cancel();
      _closeChannel();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _debounce?.cancel();
    _poll?.cancel();
    _channelRetry?.cancel();
    _closeChannel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Switch to the faster interval as soon as checkout creates an active
    // order, rather than waiting for the previous browsing timer to expire.
    ref.listen(
      storeProvider.select(
        (store) =>
            (store.isAdminAccount, _hasActiveOrder(store), store.profile?.id),
      ),
      (_, next) => _start(),
    );
    return widget.child;
  }
}
