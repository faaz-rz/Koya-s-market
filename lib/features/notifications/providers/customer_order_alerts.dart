import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../orders/models/order.dart';
import '../../orders/widgets/order_status_ui.dart';
import '../../store/providers/store_provider.dart';
import '../services/customer_alert_platform.dart';
import '../services/push_preferences.dart';
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
  int _enableAttempt = 0;
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
      if (user != null) unawaited(restore());
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

  Future<void> restore() async {
    final user = _user, generation = _generation;
    if (user == null || state.enabling) return;
    final attempt = ++_enableAttempt;
    try {
      final preference = await ref.read(pushPreferencesProvider).read(user);
      if (!ref.mounted ||
          generation != _generation ||
          attempt != _enableAttempt ||
          !preference.enabled) {
        return;
      }
      final platform = _platform ??= ref.read(
        customerAlertPlatformFactoryProvider,
      )();
      final enabled = await platform.restore();
      if (!ref.mounted ||
          generation != _generation ||
          attempt != _enableAttempt) {
        return;
      }
      state = CustomerAlertState(
        updates: state.updates,
        enabled: enabled,
        sound: preference.sound,
        note: enabled
            ? null
            : 'Allow order notifications in your phone settings.',
      );
    } catch (_) {
      // A secure-preference or platform failure never blocks shopping.
    }
  }

  Future<void> openSettings() async {
    final platform = _platform ??= ref.read(
      customerAlertPlatformFactoryProvider,
    )();
    await platform.openSettings().catchError((Object _) => false);
  }

  Future<void> promptForFirstLogin() async {
    final user = _user, generation = _generation;
    if (user == null || state.enabling) return;
    try {
      final preferences = ref.read(pushPreferencesProvider);
      final saved = await preferences
          .read(user)
          .timeout(const Duration(seconds: 5));
      if (!ref.mounted ||
          generation != _generation ||
          saved.prompted ||
          saved.enabled) {
        return;
      }
      await preferences
          .write(
            user,
            PushPreference(
              enabled: saved.enabled,
              sound: saved.sound,
              prompted: true,
            ),
          )
          .timeout(const Duration(seconds: 5));
      if (ref.mounted && generation == _generation) await enable();
    } catch (_) {}
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
              ? 'Order #${order.customerDisplayNumber}: ${order.customerStatusMessage}'
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
    ++_enableAttempt;
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
    if (!ref.mounted || generation != _generation) return;
    if (enabled &&
        !ref.read(pushSessionStatusProvider).available &&
        _user != null) {
      try {
        await ref
            .read(pushPreferencesProvider)
            .write(
              _user!,
              PushPreference(enabled: true, sound: state.sound, prompted: true),
            )
            .timeout(const Duration(seconds: 5));
      } catch (_) {}
    }
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
    final user = _user;
    if (user != null && !ref.read(pushSessionStatusProvider).available) {
      unawaited(
        ref
            .read(pushPreferencesProvider)
            .write(
              user,
              PushPreference(
                enabled: state.enabled,
                sound: !muted,
                prompted: true,
              ),
            )
            .catchError((Object _) {}),
      );
    }
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
