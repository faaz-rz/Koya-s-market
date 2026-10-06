import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../orders/models/order.dart';
import '../../orders/widgets/order_status_ui.dart';
import '../../store/providers/store_provider.dart';
import '../services/customer_alert_platform.dart';
import 'push_session.dart';

/// Initial history is silent; a status is announced once per signed-in session.
class CustomerStatusTracker {
  bool _primed = false;
  final _seen = <String>{};
  List<CustomerOrder> observe(List<CustomerOrder> orders) {
    final updates = <CustomerOrder>[];
    for (final order in orders) {
      final fresh = _seen.add('${order.id}:${order.status.name}');
      if (_primed &&
          fresh &&
          {
            OrderStatus.readyForPickup,
            OrderStatus.outForDelivery,
            OrderStatus.delivered,
            OrderStatus.collected,
            OrderStatus.cancelled,
            OrderStatus.rejected,
          }.contains(order.status)) {
        updates.add(order);
      }
    }
    _primed = true;
    return updates;
  }
}

class CustomerAlertState {
  const CustomerAlertState({
    this.updates = const [],
    this.enabled = false,
    this.enabling = false,
    this.sound = true,
    this.note,
  });
  final List<CustomerOrder> updates;
  final bool enabled, enabling, sound;
  final String? note;
}

final customerOrderAlertsProvider =
    NotifierProvider<CustomerOrderAlerts, CustomerAlertState>(
      CustomerOrderAlerts.new,
    );

class CustomerOrderAlerts extends Notifier<CustomerAlertState> {
  CustomerStatusTracker _tracker = CustomerStatusTracker();
  CustomerAlertPlatform? _platform;
  String? _user;
  int _generation = 0;
  Timer? _batch;
  final _queued = <String, CustomerOrder>{};
  void Function(String)? onOpenOrder;
  @override
  CustomerAlertState build() {
    ref.onDispose(() {
      _batch?.cancel();
      _platform?.dispose();
    });
    return const CustomerAlertState();
  }

  void observe(StoreState store) {
    final user = store.isAuthenticated && !store.isAdminAccount
        ? store.profile?.id
        : null;
    if (user != _user) {
      _generation++;
      _batch?.cancel();
      _batch = null;
      _queued.clear();
      _platform?.dispose();
      _platform = null;
      _tracker = CustomerStatusTracker();
      _user = user;
      state = const CustomerAlertState();
    }
    if (user == null) return;
    final updates = _tracker.observe(store.orders);
    final active = state.updates
        .where(
          (old) =>
              store.orders.any((o) => o.id == old.id && o.status == old.status),
        )
        .toList();
    final pending = <String, CustomerOrder>{
      for (final order in active) order.id: order,
      for (final order in updates) order.id: order,
    };
    state = CustomerAlertState(
      updates: pending.values.toList(),
      enabled: state.enabled,
      enabling: state.enabling,
      sound: state.sound,
      note: state.note,
    );
    if (updates.isEmpty || !state.enabled) return;
    for (final order in updates) {
      _queued[order.id] = order;
    }
    // A burst of replicated changes produces one notification and one sound.
    _batch ??= Timer(const Duration(milliseconds: 250), () {
      _batch = null;
      final current = ref.read(storeProvider);
      final batch = _queued.values
          .where(
            (old) => current.orders.any(
              (o) => o.id == old.id && o.status == old.status,
            ),
          )
          .toList();
      _queued.clear();
      if (batch.isNotEmpty && current.profile?.id == _user && state.enabled) {
        unawaited(_notify(batch));
      }
    });
  }

  Future<void> _notify(List<CustomerOrder> batch) async {
    final generation = _generation;
    final order = batch.last;
    final platform = _platform;
    if (platform == null) return;
    final shown = await platform
        .show(
          title: batch.length == 1
              ? 'Koya Stores · ${order.customerStatusLabel}'
              : 'Koya Stores · ${batch.length} order updates',
          body: batch.length == 1
              ? order.customerStatusMessage
              : 'Open your orders to see pickup and delivery updates.',
          sound: state.sound,
          onOpen: () {
            if (generation == _generation &&
                _user != null &&
                ref.read(storeProvider).orders.any((o) => o.id == order.id)) {
              onOpenOrder?.call(order.id);
            }
          },
        )
        .catchError((Object _) => false);
    if (!shown && generation == _generation) {
      state = CustomerAlertState(
        updates: state.updates,
        enabled: state.enabled,
        sound: state.sound,
        note:
            'Device alerts are unavailable. Order updates remain visible here.',
      );
    }
  }

  Future<void> enable() async {
    if (_user == null || state.enabling) return;
    final generation = _generation;
    final platform = _platform ??= ref.read(
      customerAlertPlatformFactoryProvider,
    )();
    state = CustomerAlertState(
      updates: state.updates,
      enabling: true,
      sound: state.sound,
    );
    final enabled = await platform.enable().catchError((Object _) => false);
    final background = enabled
        ? await ref.read(pushSessionProvider).enable()
        : false;
    if (!ref.mounted || generation != _generation) return;
    state = CustomerAlertState(
      updates: state.updates,
      enabled: enabled,
      sound: state.sound,
      note: enabled
          ? background
                ? 'Order alerts enabled.'
                : 'Device alerts enabled while the app is open.'
          : 'Device alerts are blocked or unavailable. Order updates remain visible here.',
    );
  }

  void mute(bool muted) {
    unawaited(ref.read(pushSessionProvider).sound(!muted));
    state = CustomerAlertState(
      updates: state.updates,
      enabled: state.enabled,
      enabling: state.enabling,
      sound: !muted,
      note: state.note,
    );
  }

  void dismiss() => state = CustomerAlertState(
    enabled: state.enabled,
    enabling: state.enabling,
    sound: state.sound,
    note: state.note,
  );
}
