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
  bool _refreshing = false;
  bool _foreground = true;
  bool _refreshAgain = false;
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
      _foreground &&
      (widget.client != null || AppEnvironment.hasSupabaseConfig) &&
      _client.auth.currentUser != null;

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
    final channel = client.channel('store-live-${identityHashCode(this)}');
    _channel = channel;
    _channelUserId = userId;
    _channelAdmin = admin;
    channel
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'products',
          callback: (_) => _scheduleRefresh(),
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
          callback: (_) => _scheduleRefresh(),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'store_settings',
          callback: (_) => _scheduleRefresh(),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'offers',
          callback: (_) => _scheduleRefresh(),
        )
        .subscribe((status, error) {
          if (!_connected || !identical(_channel, channel)) return;
          _live = status == RealtimeSubscribeStatus.subscribed;
          _schedulePoll();
          // Refresh after joining/rejoining to cover the subscription gap.
          if (_live) _scheduleRefresh();
        });
  }

  void _schedulePoll() {
    _poll?.cancel();
    if (!_connected) return;
    final store = ref.read(storeProvider);
    final activeOrder = _hasActiveOrder(store);
    _poll = Timer(
      UsagePolicy.pollDelay(
        admin: store.isAdminAccount,
        activeOrder: activeOrder,
        failures: _failures,
        live: _live,
        jitterSeconds: _random.nextInt(8),
      ),
      _refresh,
    );
  }

  void _scheduleRefresh() {
    if (!_connected || _debounce?.isActive == true || _failures > 0) return;
    final elapsed = _lastRefresh == null
        ? UsagePolicy.minimumRefreshGap
        : DateTime.now().difference(_lastRefresh!);
    final delay = max(
      UsagePolicy.realtimeDebounce.inMilliseconds,
      UsagePolicy.minimumRefreshGap.inMilliseconds - elapsed.inMilliseconds,
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
        _start();
      }
    } catch (_) {
      _failures++;
    } finally {
      _refreshing = false;
      _lastRefresh = DateTime.now();
      _schedulePoll();
      if (_refreshAgain) {
        _refreshAgain = false;
        _scheduleRefresh();
      }
    }
  }

  void _closeChannel() {
    final channel = _channel;
    _channel = null;
    _channelUserId = null;
    _channelAdmin = null;
    _live = false;
    if (channel != null) {
      unawaited(_client.removeChannel(channel));
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (_foreground) {
      _start();
      _scheduleRefresh();
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
