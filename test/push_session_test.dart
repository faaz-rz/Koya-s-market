import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:koyas_supermarket/features/notifications/data/notification_repository.dart';
import 'package:koyas_supermarket/features/notifications/providers/push_session.dart';
import 'package:koyas_supermarket/features/notifications/services/push_gateway.dart';
import 'package:koyas_supermarket/features/notifications/services/push_preferences.dart';

class TestGateway extends PushGateway {
  @override
  bool available = true;
  bool granted = true;
  int prompts = 0, deleted = 0;
  Completer<bool>? delayedPermission;
  final refresh = StreamController<String>.broadcast(sync: true);
  final taps = StreamController<Map<String, dynamic>>.broadcast(sync: true);
  final messages = StreamController<Map<String, dynamic>>.broadcast(sync: true);
  @override
  Future<bool> permission({bool request = false}) async {
    if (request) {
      prompts++;
      if (delayedPermission != null) return delayedPermission!.future;
    }
    return granted;
  }

  @override
  Future<String?> token() async => 'device-token';
  @override
  Future<void> deleteToken() async {
    deleted++;
  }

  @override
  Stream<String> get tokenChanges => refresh.stream;
  @override
  Stream<Map<String, dynamic>> get opened => taps.stream;
  @override
  Stream<Map<String, dynamic>> get received => messages.stream;
  @override
  Future<Map<String, dynamic>?> initialMessage() async => null;
}

class TestRegistry extends PushDeviceRegistry {
  bool active = true;
  Completer<bool>? pending;
  final registrations = <String>[];
  final removals = <String>[];
  final sounds = <bool>[];
  @override
  Future<bool> register(String user, String token, bool sound) async {
    registrations.add('$user:$token');
    sounds.add(sound);
    return pending?.future ?? active;
  }

  @override
  Future<void> unregister(String user, String token) async {
    removals.add('$user:$token');
  }
}

class TestPreferences extends PushPreferences {
  final values = <String, PushPreference>{};
  @override
  Future<PushPreference> read(String user) async =>
      values[user] ?? const PushPreference();
  @override
  Future<void> write(String user, PushPreference value) async {
    values[user] = value;
  }
}

void main() {
  late TestGateway gateway;
  late TestRegistry registry;
  late TestPreferences preferences;
  late PushSession session;
  final states = <PushSessionState>[];
  setUp(() {
    gateway = TestGateway();
    registry = TestRegistry();
    preferences = TestPreferences();
    states.clear();
    session = PushSession(
      gateway: gateway,
      registry: registry,
      preferences: preferences,
      status: states.add,
    );
  });
  tearDown(() async {
    session.dispose();
    await gateway.refresh.close();
    await gateway.taps.close();
    await gateway.messages.close();
  });
  test(
    'returning from phone settings rechecks permission without prompting and recovers registration',
    () async {
      preferences.values['alice'] = const PushPreference(enabled: true);
      session.bind('alice');
      await session.settled;
      gateway.granted = false;
      await session.refresh();
      expect(states.last.ready, false);
      expect(gateway.prompts, 0);
      gateway.granted = true;
      await session.refresh();
      expect(states.last.ready, true);
      expect(gateway.prompts, 0);
    },
  );
  test(
    'explicit opt-in persists, restart registers without prompting, token refresh and mute update owned registration',
    () async {
      session.bind('alice');
      await session.settled;
      expect(gateway.prompts, 0);
      expect(registry.registrations, isEmpty);
      expect(await session.enable(), true);
      expect(preferences.values['alice']!.enabled, true);
      await session.sound(false);
      expect(registry.sounds.last, false);
      gateway.refresh.add('new-token');
      await session.settled;
      expect(registry.registrations.last, 'alice:new-token');
      session.dispose();
      session = PushSession(
        gateway: gateway,
        registry: registry,
        preferences: preferences,
        status: states.add,
      );
      session.bind('alice');
      await session.settled;
      expect(states.last.ready, true);
      expect(gateway.prompts, 1);
    },
  );
  test(
    'logout waits for a pending registration then removes it; reopening is the only action that retains the token',
    () async {
      session.bind('alice');
      await session.settled;
      registry.pending = Completer();
      final enabling = session.enable();
      await Future<void>.delayed(Duration.zero);
      final logout = session.beforeSignOut();
      registry.pending!.complete(true);
      await enabling;
      await logout;
      expect(registry.removals, ['alice:device-token']);
      expect(gateway.deleted, 1);
      expect(states.last.ready, false);
    },
  );
  test(
    'late permissions, foreign notification taps and replay after logout cannot open another account order',
    () async {
      var opened = 0;
      session.onOpen = (_) => opened++;
      session.bind('alice');
      await session.settled;
      gateway.taps.add({'user_id': 'bob', 'order_id': 'order'});
      expect(opened, 0);
      gateway.taps.add({'user_id': 'alice', 'order_id': 'order'});
      expect(opened, 1);
      gateway.delayedPermission = Completer();
      final enabling = session.enable();
      await Future<void>.delayed(Duration.zero);
      final logout = session.beforeSignOut();
      gateway.delayedPermission!.complete(true);
      await enabling;
      await logout;
      expect(registry.registrations, isEmpty);
      gateway.taps.add({'user_id': 'alice', 'order_id': 'order'});
      expect(opened, 1);
    },
  );
  test(
    'denied permission, absent configuration and disabled dispatcher never claim background delivery is ready',
    () async {
      gateway.available = false;
      session.bind('alice');
      expect(await session.enable(), false);
      expect(registry.registrations, isEmpty);
      session.bind(null);
      gateway.available = true;
      gateway.granted = false;
      session.bind('alice');
      await session.settled;
      expect(await session.enable(), false);
      gateway.granted = true;
      registry.active = false;
      expect(await session.enable(), false);
      expect(states.last.ready, false);
      expect(states.last.message, contains('being set up'));
    },
  );
}
