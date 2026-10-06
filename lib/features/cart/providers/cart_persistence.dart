import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../store/providers/store_provider.dart';
import '../data/saved_cart_storage.dart';

class SavedCartStatus {
  const SavedCartStatus({this.restoring = false, this.message});
  final bool restoring;
  final String? message;
}

class SavedCartStatusController extends Notifier<SavedCartStatus> {
  @override
  SavedCartStatus build() => const SavedCartStatus();
  void update(SavedCartStatus next) => state = next;
}

final savedCartStatusProvider =
    NotifierProvider<SavedCartStatusController, SavedCartStatus>(
      SavedCartStatusController.new,
    );

final cartPersistenceProvider = Provider<CartPersistence>((ref) {
  final persistence = CartPersistence(
    storage: ref.read(savedCartStorageProvider),
    current: () => ref.read(storeProvider),
    apply: (user, items) =>
        ref.read(storeProvider.notifier).restoreSavedCart(user, items),
    status: (status) {
      if (ref.mounted) {
        ref.read(savedCartStatusProvider.notifier).update(status);
      }
    },
  );
  ref.listen(storeProvider, (_, next) => persistence.observe(next));
  ref.onDispose(persistence.dispose);
  scheduleMicrotask(() {
    if (ref.mounted) persistence.observe(ref.read(storeProvider));
  });
  return persistence;
});

/// Writes are ordered per device; logout keeps the saved cart but removes its
/// visible contents. Late reads can never restore into another user's session.
class CartPersistence {
  CartPersistence({
    required this.storage,
    required this.current,
    required this.apply,
    required this.status,
  });
  final SavedCartStorage storage;
  final StoreState Function() current;
  final void Function(String, Map<String, int>) apply;
  final void Function(SavedCartStatus) status;
  Future<void> _writes = Future.value();
  Future<void> _restoreTask = Future.value();
  Future<void> get restored => _restoreTask;
  String? _user;
  int _generation = 0;
  bool _restoring = false, _disposed = false, _applying = false;
  Map<String, int> _previous = {};
  final _deltas = <String, int>{};
  final _removed = <String>{};
  Future<void> get flushed => _writes;

  void observe(StoreState store) {
    if (_disposed) return;
    final user = store.isAuthenticated && !store.isAdminAccount
        ? store.profile?.id
        : null;
    if (user != _user) {
      _generation++;
      _user = user;
      _previous = Map.of(store.cartQuantities);
      _deltas.clear();
      _deltas.addAll(_previous);
      _removed.clear();
      _restoring = user != null;
      status(SavedCartStatus(restoring: _restoring));
      if (user != null) {
        _restoreTask = _restore(user, _generation);
        unawaited(_restoreTask);
      }
      return;
    }
    if (user == null ||
        _applying ||
        mapEquals(_previous, store.cartQuantities)) {
      return;
    }
    if (_restoring) {
      for (final id in {..._previous.keys, ...store.cartQuantities.keys}) {
        final old = _previous[id] ?? 0, next = store.cartQuantities[id] ?? 0;
        if (old == next) continue;
        if (next == 0) {
          _removed.add(id);
          _deltas.remove(id);
        } else {
          _removed.remove(id);
          _deltas[id] = (_deltas[id] ?? 0) + next - old;
        }
      }
    } else {
      _save(user, store.cartQuantities);
    }
    _previous = Map.of(store.cartQuantities);
  }

  Future<void> _restore(String user, int generation) async {
    try {
      await _writes;
      final saved = await storage.read(user);
      if (_disposed ||
          generation != _generation ||
          current().profile?.id != user ||
          !current().isAuthenticated) {
        return;
      }
      final availableIds = current().products.map((p) => p.id).toSet();
      final quantities = <String, int>{};
      for (final id in {...saved.keys, ..._previous.keys, ..._deltas.keys}) {
        if (_removed.contains(id) || !availableIds.contains(id)) continue;
        final quantity = (saved[id] ?? 0) + (_deltas[id] ?? 0);
        if (quantity > 0) quantities[id] = quantity.clamp(1, 999999);
      }
      _restoring = false;
      _applying = true;
      try {
        apply(user, quantities);
      } finally {
        _applying = false;
      }
      _previous = Map.of(quantities);
      status(
        SavedCartStatus(
          message: saved.keys.any((id) => !availableIds.contains(id))
              ? 'Some saved items are no longer in the catalogue.'
              : null,
        ),
      );
      _save(user, quantities);
    } catch (_) {
      if (!_disposed && generation == _generation) {
        _restoring = false;
        status(
          const SavedCartStatus(
            message:
                'The saved cart could not be restored on this device. You can continue shopping.',
          ),
        );
      }
    }
  }

  void _save(String user, Map<String, int> quantities) {
    final snapshot = Map<String, int>.of(quantities);
    _writes = _writes.then((_) => storage.write(user, snapshot)).catchError((
      Object _,
    ) {
      if (!_disposed && _user == user) {
        status(
          const SavedCartStatus(
            message:
                'The cart could not be saved on this device. Keep the app open and try again.',
          ),
        );
      }
    });
  }

  Future<void> deleteForAccount(String user) async {
    if (_user == user) {
      _generation++;
      _restoring = false;
    }
    _writes = _writes.then((_) => storage.remove(user));
    await _writes;
  }

  void dispose() {
    _disposed = true;
    _generation++;
  }
}
