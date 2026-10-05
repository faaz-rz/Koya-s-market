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

/// Staff keep one debounced live channel. Customers use conditional snapshots
/// instead of permanent connections. Reads pause when hidden and back off on
/// failures. Checkout still validates prices/stock in its own transaction.
class StoreRealtimeSync extends ConsumerStatefulWidget {
  const StoreRealtimeSync({required this.child, super.key});
  final Widget child;
  @override
  ConsumerState<StoreRealtimeSync> createState() => _StoreRealtimeSyncState();
}

class _StoreRealtimeSyncState extends ConsumerState<StoreRealtimeSync>
    with WidgetsBindingObserver {
  RealtimeChannel? _channel;
  Timer? _debounce;
  Timer? _poll;
  bool _refreshing = false;
  bool _foreground = true;
  bool _refreshAgain = false;
  int _failures = 0;
  DateTime? _lastRefresh;
  final _random = Random();

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
      AppEnvironment.hasSupabaseConfig &&
      Supabase.instance.client.auth.currentUser != null;

  void _start() {
    if (!_connected) {
      _poll?.cancel();
      _debounce?.cancel();
      _closeChannel();
      return;
    }
    if (ref.read(storeProvider).isAdminAccount) {
      _subscribe();
    } else {
      _closeChannel();
    }
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
    if (!_connected ||
        _channel != null ||
        !ref.read(storeProvider).isAdminAccount) {
      return;
    }
    final client = Supabase.instance.client;
    final channel = client.channel('store-live-${identityHashCode(this)}');
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
        .subscribe();
    _channel = channel;
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
    final userId = Supabase.instance.client.auth.currentUser!.id;
    try {
      final bundle = await SupabaseStoreRepository().loadStore().timeout(
        const Duration(seconds: 20),
      );
      if (_connected &&
          Supabase.instance.client.auth.currentUser?.id == userId) {
        ref.read(storeProvider.notifier).hydrateRemoteBundle(bundle);
        _failures = 0;
        if (!bundle.isAdmin) {
          _closeChannel();
        } else {
          _subscribe();
        }
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
    if (channel != null) {
      unawaited(Supabase.instance.client.removeChannel(channel));
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
