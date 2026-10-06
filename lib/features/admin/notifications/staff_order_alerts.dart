import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../orders/models/order.dart';
import '../../store/providers/store_provider.dart';
import 'order_alert_platform.dart';

class NewOrderTracker {
  String? _scope;
  Set<String> _seen = {};

  List<CustomerOrder> observe(String? scope, List<CustomerOrder> orders) {
    if (scope == null || scope != _scope) {
      _scope = scope;
      _seen = orders.map((o) => o.id).toSet();
      return [];
    }
    final added = orders
        .where((o) => !_seen.contains(o.id) && o.status == OrderStatus.placed)
        .toList(growable: false);
    // A checkout may start before another order yet commit later after waiting
    // for stock locks. IDs, not timestamps, distinguish newly received orders.
    // This set belongs only to the current signed-in staff session.
    _seen.addAll(orders.map((o) => o.id));
    return added;
  }
}

class StaffOrderAlertsState {
  const StaffOrderAlertsState({
    this.pending = const {},
    this.enabled = false,
    this.sound = false,
    this.notifications = BrowserAlertPermission.unavailable,
    this.enabling = false,
    this.note,
  });
  final Set<String> pending;
  final bool enabled;
  final bool sound;
  final BrowserAlertPermission notifications;
  final bool enabling;
  final String? note;
  StaffOrderAlertsState copyWith({
    Set<String>? pending,
    bool? enabled,
    bool? sound,
    BrowserAlertPermission? notifications,
    bool? enabling,
    String? note,
    bool clearNote = false,
  }) => StaffOrderAlertsState(
    pending: pending ?? this.pending,
    enabled: enabled ?? this.enabled,
    sound: sound ?? this.sound,
    notifications: notifications ?? this.notifications,
    enabling: enabling ?? this.enabling,
    note: clearNote ? null : note ?? this.note,
  );
}

final orderAlertPlatformProvider = Provider<OrderAlertPlatform>((ref) {
  final platform = createOrderAlertPlatform();
  ref.onDispose(platform.dispose);
  return platform;
});

class StaffOrderAlertsController extends Notifier<StaffOrderAlertsState> {
  final _tracker = NewOrderTracker();
  String? _userId;
  int _generation = 0;
  DateTime? _lastSound;
  void Function()? onOpenOrders;
  OrderAlertPlatform get _platform => ref.read(orderAlertPlatformProvider);

  @override
  StaffOrderAlertsState build() => const StaffOrderAlertsState();

  void observe(StoreState store) {
    final scope = store.isAuthenticated && store.isAdminAccount
        ? store.profile?.id
        : null;
    if (_userId != scope) {
      _generation++;
      _platform.dispose();
      _userId = scope;
      _lastSound = null;
      state = const StaffOrderAlertsState();
    }
    final added = _tracker.observe(scope, scope == null ? [] : store.orders);
    if (scope == null) return;
    final waiting = store.orders
        .where((o) => o.status == OrderStatus.placed)
        .map((o) => o.id)
        .toSet();
    final pending = {
      ...state.pending.where(waiting.contains),
      ...added.map((o) => o.id),
    };
    if (pending.length != state.pending.length || added.isNotEmpty) {
      state = state.copyWith(pending: pending);
      _platform.badge(pending.length);
      if (pending.isEmpty) _platform.dismiss();
    }
    if (added.isEmpty) return;
    if (state.enabled &&
        state.notifications == BrowserAlertPermission.granted) {
      final generation = _generation;
      final shown = _platform.notify(
        count: pending.length,
        onOpen: () {
          if (ref.mounted && _userId == scope && _generation == generation) {
            onOpenOrders?.call();
          }
        },
      );
      if (!shown) {
        state = state.copyWith(
          notifications: BrowserAlertPermission.unavailable,
          note:
              'Browser notifications are unavailable. In-app alerts stay available.',
        );
      }
    }
    if (state.sound &&
        (_lastSound == null ||
            DateTime.now().difference(_lastSound!) >=
                const Duration(seconds: 2))) {
      _lastSound = DateTime.now();
      unawaited(_play(_userId!));
    }
  }

  Future<void> enable() async {
    if (_userId == null || state.enabling) return;
    final userId = _userId;
    final generation = _generation;
    // Begin browser gesture-sensitive calls before the first await.
    state = state.copyWith(enabling: true, clearNote: true);
    try {
      final request = _platform.enable();
      final permission = await request;
      if (!ref.mounted || userId != _userId || generation != _generation) {
        return;
      }
      state = state.copyWith(
        enabled: true,
        sound: permission.sound,
        notifications: permission.notifications,
        enabling: false,
        note: permission.notifications == BrowserAlertPermission.denied
            ? 'Browser notifications are blocked. In-app alerts stay available.'
            : permission.notifications == BrowserAlertPermission.unavailable
            ? 'In-app alerts are available. Browser notifications are unavailable here.'
            : null,
      );
      if (permission.sound) {
        await _play(userId!);
      }
    } catch (_) {
      if (ref.mounted && userId == _userId && generation == _generation) {
        state = state.copyWith(
          enabling: false,
          note: 'Could not enable sound. In-app alerts still work.',
        );
      }
    }
  }

  Future<void> _play(String userId) async {
    final generation = _generation;
    bool played;
    try {
      played = await _platform.playChime();
    } catch (_) {
      played = false;
    }
    if (ref.mounted &&
        _userId == userId &&
        _generation == generation &&
        !played) {
      state = state.copyWith(
        sound: false,
        enabled: false,
        note: 'Sound is blocked. Enable alerts to retry.',
      );
    }
  }

  Future<void> testSound() async {
    if (_userId != null) await _play(_userId!);
  }

  void mute() => state = state.copyWith(sound: false);
  void acknowledge() {
    state = state.copyWith(pending: {});
    _platform.dismiss();
    _platform.badge(0);
  }
}

final staffOrderAlertsProvider =
    NotifierProvider<StaffOrderAlertsController, StaffOrderAlertsState>(
      StaffOrderAlertsController.new,
    );
