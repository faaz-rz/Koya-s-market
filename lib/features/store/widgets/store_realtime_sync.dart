import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/config/app_environment.dart';
import '../data/supabase_store_repository.dart';
import '../providers/store_provider.dart';

/// Keeps products and orders current while an authenticated customer or admin
/// is using the app. Database events are debounced into one authoritative
/// reload so related order/item writes arrive as a consistent bundle.
class StoreRealtimeSync extends ConsumerStatefulWidget {
  const StoreRealtimeSync({required this.child, super.key});

  final Widget child;

  @override
  ConsumerState<StoreRealtimeSync> createState() => _StoreRealtimeSyncState();
}

class _StoreRealtimeSyncState extends ConsumerState<StoreRealtimeSync> {
  RealtimeChannel? _channel;
  Timer? _debounce;
  bool _refreshing = false;
  bool _refreshAgain = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _subscribe());
  }

  void _subscribe() {
    if (!mounted ||
        !AppEnvironment.hasSupabaseConfig ||
        Supabase.instance.client.auth.currentUser == null) {
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
        .subscribe();
    _channel = channel;
  }

  void _scheduleRefresh() {
    if (!mounted) return;
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), _refresh);
  }

  Future<void> _refresh() async {
    if (_refreshing) {
      _refreshAgain = true;
      return;
    }
    _refreshing = true;
    try {
      final bundle = await SupabaseStoreRepository().loadStore();
      if (mounted) {
        ref.read(storeProvider.notifier).hydrateRemoteBundle(bundle);
      }
    } catch (_) {
      // The current screen remains usable; the next database event or manual
      // refresh retries synchronization.
    } finally {
      _refreshing = false;
      if (_refreshAgain && mounted) {
        _refreshAgain = false;
        _scheduleRefresh();
      }
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    final channel = _channel;
    if (channel != null && AppEnvironment.hasSupabaseConfig) {
      unawaited(Supabase.instance.client.removeChannel(channel));
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
