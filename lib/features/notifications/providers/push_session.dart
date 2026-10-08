import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../store/providers/store_provider.dart';
import '../data/notification_repository.dart';
import '../services/push_gateway.dart';
import '../services/push_preferences.dart';

class PushSessionState {
  const PushSessionState({
    this.ready = false,
    this.available = false,
    this.message,
  });
  final bool ready, available;
  final String? message;
}

class PushStatusController extends Notifier<PushSessionState> {
  @override
  PushSessionState build() => const PushSessionState();
  void update(PushSessionState next) => state = next;
}

final pushSessionStatusProvider =
    NotifierProvider<PushStatusController, PushSessionState>(
      PushStatusController.new,
    );

final pushSessionProvider = Provider<PushSession>((ref) {
  final session = PushSession(
    gateway: ref.read(pushGatewayProvider),
    registry: ref.read(pushDeviceRegistryProvider),
    preferences: ref.read(pushPreferencesProvider),
    status: (state) {
      if (ref.mounted) {
        ref.read(pushSessionStatusProvider.notifier).update(state);
      }
    },
  );
  String? user(StoreState store) =>
      store.isAuthenticated && !store.isAdminAccount ? store.profile?.id : null;
  ref.listen(storeProvider.select(user), (_, next) => session.bind(next));
  ref.onDispose(session.dispose);
  scheduleMicrotask(() {
    if (ref.mounted) session.bind(user(ref.read(storeProvider)));
  });
  return session;
});

class PushSession {
  PushSession({
    required this.gateway,
    required this.registry,
    required this.preferences,
    required this.status,
  });
  final PushGateway gateway;
  final PushDeviceRegistry registry;
  final PushPreferences preferences;
  final void Function(PushSessionState) status;
  Future<void> _operations = Future.value();
  final _subscriptions = <StreamSubscription>[];
  String? _user, _token;
  int _generation = 0;
  bool _disposed = false;
  PushPreference _preference = const PushPreference();
  void Function(Map<String, dynamic>)? onOpen, onMessage;
  bool _current(String user, int generation) =>
      !_disposed && _user == user && generation == _generation;
  Future<void> get settled => _operations;

  void bind(String? user) {
    if (_disposed || _user == user) return;
    final oldUser = _user, oldToken = _token;
    _user = user;
    _token = null;
    final generation = ++_generation;
    _cancelStreams();
    status(PushSessionState(available: gateway.available));
    if (!gateway.available) return;
    _operations = _operations
        .then((_) async {
          if (oldUser != null && oldToken != null) {
            try {
              await registry.unregister(oldUser, oldToken);
            } catch (_) {}
            try {
              await gateway.deleteToken();
            } catch (_) {}
          }
          if (user == null || !_current(user, generation)) return;
          _preference = await preferences.read(user);
          if (!_current(user, generation)) return;
          final initial = await gateway.initialMessage();
          if (!_current(user, generation)) return;
          if (_current(user, generation) && initial != null) {
            _handle(initial, user, generation, open: true);
          }
          _subscriptions.add(
            gateway.opened.listen(
              (data) => _handle(data, user, generation, open: true),
            ),
          );
          _subscriptions.add(
            gateway.received.listen(
              (data) => _handle(data, user, generation, open: false),
            ),
          );
          _subscriptions.add(
            gateway.tokenChanges.listen((token) {
              if (_current(user, generation) && _preference.enabled) {
                _operations = _operations
                    .then((_) async {
                      await _register(user, generation, token);
                    })
                    .catchError((Object _) {
                      if (_current(user, generation)) _unavailable();
                    });
              }
            }),
          );
          if (_preference.enabled &&
              await gateway.permission() &&
              _current(user, generation)) {
            final token = await gateway.token();
            if (token != null && _current(user, generation)) {
              await _register(user, generation, token);
            }
          }
        })
        .catchError((Object _) {
          if (!_disposed && generation == _generation) _unavailable();
        });
  }

  void _handle(
    Map<String, dynamic> data,
    String user,
    int generation, {
    required bool open,
  }) {
    if (!_current(user, generation) ||
        data['user_id'] != user ||
        data['order_id'] is! String) {
      return;
    }
    if (open) {
      onOpen?.call(data);
    } else {
      onMessage?.call(data);
    }
  }

  Future<bool> _register(String user, int generation, String token) async {
    if (!_current(user, generation)) return false;
    _token = token;
    final ready = await registry.register(user, token, _preference.sound);
    if (_current(user, generation)) {
      status(
        PushSessionState(
          ready: ready,
          available: true,
          message: ready
              ? 'Background order alerts are enabled.'
              : 'Background delivery is still being set up. Updates appear in the app.',
        ),
      );
    }
    return ready && _current(user, generation);
  }

  Future<bool> enable() {
    final user = _user, generation = _generation;
    if (user == null || !gateway.available) return Future.value(false);
    final attempt = _operations.then((_) => _enable(user, generation));
    _operations = attempt.then<void>((_) {});
    return attempt;
  }

  /// Re-check after returning from phone settings or recovering connectivity.
  Future<void> refresh() {
    final user = _user, generation = _generation;
    if (user == null || !gateway.available) return Future.value();
    _operations = _operations
        .then((_) async {
          if (!_current(user, generation)) return;
          _preference = await preferences.read(user);
          if (!_current(user, generation) || !_preference.enabled) return;
          if (!await gateway.permission()) {
            if (_current(user, generation)) {
              status(
                const PushSessionState(
                  available: true,
                  message: 'Allow order notifications in your phone settings.',
                ),
              );
            }
            return;
          }
          final token = await gateway.token();
          if (token != null && _current(user, generation)) {
            await _register(user, generation, token);
          }
        })
        .catchError((Object _) {
          if (_current(user, generation)) _unavailable();
        });
    return _operations;
  }

  Future<bool> _enable(String user, int generation) async {
    try {
      if (!_current(user, generation) ||
          !await gateway.permission(request: true) ||
          !_current(user, generation)) {
        return false;
      }
      _preference = PushPreference(
        enabled: true,
        sound: _preference.sound,
        prompted: true,
      );
      await preferences.write(user, _preference);
      final token = await gateway.token();
      if (!_current(user, generation) || token == null) {
        if (_current(user, generation)) _unavailable();
        return false;
      }
      return await _register(user, generation, token);
    } catch (_) {
      if (_current(user, generation)) _unavailable();
      return false;
    }
  }

  Future<void> sound(bool enabled) {
    final user = _user, generation = _generation;
    if (user == null || !gateway.available) return Future.value();
    _operations = _operations.then((_) => _sound(user, generation, enabled));
    return _operations;
  }

  Future<void> _sound(String user, int generation, bool enabled) async {
    if (!_current(user, generation)) return;
    _preference = PushPreference(
      enabled: _preference.enabled,
      sound: enabled,
      prompted: _preference.prompted,
    );
    try {
      await preferences.write(user, _preference);
      final token = _token;
      if (token != null && _current(user, generation)) {
        await _register(user, generation, token);
      }
    } catch (_) {
      if (_current(user, generation)) _unavailable();
    }
  }

  Future<void> beforeSignOut() async {
    final user = _user;
    if (user == null) return;
    _generation++;
    _cancelStreams();
    await _operations;
    final token = _token;
    if (token != null) {
      try {
        await registry.unregister(user, token);
      } catch (_) {}
    }
    if (gateway.available) {
      try {
        await gateway.deleteToken().timeout(const Duration(seconds: 5));
      } catch (_) {}
    }
    _token = null;
    _user = null;
    if (!_disposed) status(PushSessionState(available: gateway.available));
  }

  void _unavailable() => status(
    const PushSessionState(
      available: true,
      message:
          'Background alerts could not connect. Order updates remain available in the app.',
    ),
  );
  void _cancelStreams() {
    for (final subscription in _subscriptions) {
      unawaited(subscription.cancel());
    }
    _subscriptions.clear();
  }

  // Closing the app retains its registration, allowing OS push delivery.
  void dispose() {
    _disposed = true;
    _generation++;
    _cancelStreams();
    onOpen = null;
    onMessage = null;
  }
}
