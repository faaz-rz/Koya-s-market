import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:koyas_supermarket/features/store/providers/store_provider.dart';
import 'package:koyas_supermarket/features/store/data/supabase_store_repository.dart';
import 'package:koyas_supermarket/features/store/widgets/store_realtime_sync.dart';
import 'package:koyas_supermarket/features/store/providers/store_sync_health.dart';

import 'store_repository_sync_test.dart' as fixtures;
import 'store_sync_cache_test.dart' as cache;

// Exercise the real Supabase channel protocol without a hosted account/token.
class _Socket extends Fake implements WebSocketChannel {
  _Socket({this.root});
  final _Socket? root;
  final replacements = <_Socket>[];
  final incoming = StreamController<dynamic>();
  late final _Sink output = _Sink(this);
  Map<String, dynamic>? join;
  List<dynamic>? _joinFrame;
  int leaves = 0;
  bool _rejectJoins = false;
  bool get rejectJoins => root?.rejectJoins ?? _rejectJoins;
  set rejectJoins(bool value) => _rejectJoins = value;
  int joins = 0;
  int get totalJoins =>
      joins +
      replacements.fold<int>(0, (total, socket) => total + socket.joins);

  @override
  Stream<dynamic> get stream => incoming.stream;
  @override
  WebSocketSink get sink => output;
  @override
  Future<void> get ready => Future.value();
  @override
  int? get closeCode => null;
  @override
  String? get closeReason => null;

  void send(Object raw) {
    final frame = jsonDecode(raw as String) as List;
    final payload = frame[4] as Map;
    if (frame[3] == 'phx_join') {
      joins++;
      _joinFrame = frame;
      join = Map<String, dynamic>.from(payload);
      final changes = (payload['config'] as Map)['postgres_changes'] as List;
      incoming.add(
        jsonEncode([
          frame[0],
          frame[1],
          frame[2],
          'phx_reply',
          {
            'status': rejectJoins ? 'error' : 'ok',
            'response': {
              if (rejectJoins) 'reason': 'test join rejected',
              'postgres_changes': [
                for (var i = 0; i < changes.length; i++)
                  {...changes[i] as Map, 'id': i + 1},
              ],
            },
          },
        ]),
      );
    } else if (frame[3] == 'heartbeat' || frame[3] == 'phx_leave') {
      if (frame[3] == 'phx_leave') leaves++;
      incoming.add(
        jsonEncode([
          frame[0],
          frame[1],
          frame[2],
          'phx_reply',
          {'status': 'ok', 'response': {}},
        ]),
      );
    }
  }

  void stockChanged() {
    final frame = _joinFrame!;
    incoming.add(
      jsonEncode([
        frame[0],
        null,
        frame[2],
        'postgres_changes',
        {
          'ids': [1],
          'data': {
            'schema': 'public',
            'table': 'products',
            'type': 'UPDATE',
            'commit_timestamp': '2026-10-06T00:00:00Z',
            'columns': [],
            'record': {'id': 'product', 'stock_quantity': 11},
            'old_record': {},
          },
        },
      ]),
    );
  }

  void orderPlaced() {
    final frame = _joinFrame!;
    incoming.add(
      jsonEncode([
        frame[0],
        null,
        frame[2],
        'postgres_changes',
        {
          'ids': [2],
          'data': {
            'schema': 'public',
            'table': 'orders',
            'type': 'INSERT',
            'commit_timestamp': '2026-10-06T00:00:00Z',
            'columns': [],
            'record': {'id': 'new-order'},
            'old_record': {},
          },
        },
      ]),
    );
  }

  void failReplication() {
    final frame = _joinFrame!;
    incoming.add(
      jsonEncode([
        frame[0],
        null,
        frame[2],
        'system',
        {'status': 'error', 'message': 'test replication unavailable'},
      ]),
    );
  }
}

class _Sink extends Fake implements WebSocketSink {
  _Sink(this.socket);
  final _Socket socket;
  @override
  void add(dynamic data) => socket.send(data as Object);
  @override
  Future<void> close([int? closeCode, String? closeReason]) async {
    if (!socket.incoming.isClosed) await socket.incoming.close();
  }
}

Future<SupabaseClient> _client(
  _Socket socket,
  Future<dynamic> Function() snapshot,
) async {
  final client = SupabaseClient(
    'https://store.test',
    'test-public',
    authOptions: const AuthClientOptions(autoRefreshToken: false),
    realtimeClientOptions: RealtimeClientOptions(
      transport: (_, _) {
        if (!socket.incoming.isClosed) return socket;
        final replacement = _Socket(root: socket);
        socket.replacements.add(replacement);
        return replacement;
      },
      disconnectOnEmptyChannelsAfter: const Duration(seconds: 60),
    ),
    httpClient: MockClient((request) async {
      final response = fixtures.response(
        await snapshot() as Map<String, dynamic>,
      );
      return http.Response.bytes(
        response.bodyBytes,
        response.statusCode,
        request: request,
        headers: response.headers,
      );
    }),
  );
  final payload = base64Url.encode(
    utf8.encode(jsonEncode({'exp': 4102444800, 'sub': 'alice'})),
  );
  await client.auth.setInitialSession(
    jsonEncode({
      'access_token': 'test.$payload.test',
      'token_type': 'bearer',
      'user': {
        'id': 'alice',
        'email': 'alice@example.test',
        'aud': 'authenticated',
        'created_at': '2026-09-19T00:00:00Z',
      },
    }),
  );
  // Warm the real repository in the real async zone before widget timers run.
  await SupabaseStoreRepository(client: client).loadStore();
  return client;
}

Future<void> _settleUntil(WidgetTester tester, bool Function() complete) async {
  // HTTP response streams run in a real async zone. Observe their completion
  // instead of assuming a busy CI runner finishes within twenty milliseconds.
  // Pumping with no duration keeps the tested poll deadline unchanged.
  for (var attempt = 0; attempt < 200 && !complete(); attempt++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump();
  }
  expect(
    complete(),
    isTrue,
    reason: 'The mocked sync did not finish at the existing polling deadline.',
  );
}

void main() {
  testWidgets(
    'repeated rejected live joins cannot postpone staff backup reads',
    (tester) async {
      final socket = _Socket();
      var reads = 0;
      final client = (await tester.runAsync(
        () => _client(socket, () async {
          reads++;
          return {...fixtures.cold(), 'is_admin': true};
        }),
      ))!;
      final container = ProviderContainer();
      addTearDown(container.dispose);
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox());
        await tester.pump();
        await tester.runAsync(client.dispose);
      });
      final initial = await tester.runAsync(
        () => SupabaseStoreRepository(client: client).loadStore(),
      );
      container.read(storeProvider.notifier).hydrateRemoteBundle(initial!);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: StoreRealtimeSync(
            client: client,
            now: tester.binding.clock.now,
            child: const SizedBox(),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      await _settleUntil(
        tester,
        () => container.read(storeSyncHealthProvider).lastSync != null,
      );
      socket.rejectJoins = true;
      socket.failReplication();
      await tester.pump();
      final before = reads;
      final beforeSync = container.read(storeSyncHealthProvider).lastSync;
      await tester.pump(const Duration(seconds: 7));
      await _settleUntil(
        tester,
        () =>
            reads > before &&
            container.read(storeSyncHealthProvider).lastSync != beforeSync,
      );
      expect(socket.totalJoins, greaterThan(1));
      expect(reads, before + 1);
      socket.rejectJoins = false;
      await tester.pump(const Duration(seconds: 10));
      await _settleUntil(
        tester,
        () =>
            reads > before + 1 && container.read(storeSyncHealthProvider).live,
      );
      expect(client.getChannels(), hasLength(1));
      expect(reads, greaterThan(before + 1));
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      await tester.runAsync(() => client.realtime.disconnect());
    },
  );
  testWidgets(
    'staff order events preempt catalogue debounce, remain live while hidden, and use a five-second backup',
    (tester) async {
      final socket = _Socket();
      var reads = 0;
      final client = (await tester.runAsync(
        () => _client(socket, () async {
          reads++;
          return {...fixtures.cold(), 'is_admin': true};
        }),
      ))!;
      final container = ProviderContainer();
      addTearDown(container.dispose);
      addTearDown(() async {
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await tester.pumpWidget(const SizedBox());
        await tester.pump();
        await tester.runAsync(client.dispose);
      });
      final initial = await tester.runAsync(
        () => SupabaseStoreRepository(client: client).loadStore(),
      );
      container.read(storeProvider.notifier).hydrateRemoteBundle(initial!);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: StoreRealtimeSync(
            client: client,
            now: tester.binding.clock.now,
            child: const SizedBox(),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
      final changes =
          (socket.join!['config'] as Map)['postgres_changes'] as List;
      expect(
        changes
            .firstWhere((dynamic c) => c['table'] == 'orders')
            .containsKey('filter'),
        false,
      );
      await tester.pump(const Duration(seconds: 1));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
      final before = reads;
      socket.stockChanged();
      await tester.pump();
      socket.orderPlaced();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
      expect(
        reads,
        before + 1,
      ); // Does not wait for the 2-second inventory timer.
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      expect(socket.leaves, 0);
      final hidden = reads;
      socket.orderPlaced();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
      expect(reads, hidden + 1);
      socket.failReplication();
      await tester.pump();
      final disconnected = reads;
      await tester.pump(const Duration(seconds: 7));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
      expect(reads, disconnected + 1);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      await tester.runAsync(() => client.realtime.disconnect());
    },
  );

  testWidgets(
    'customer stock events coalesce into a fresh snapshot and hidden apps unsubscribe',
    (tester) async {
      final socket = _Socket();
      var reads = 0;
      var stock = 5;
      final client = (await tester.runAsync(
        () => _client(socket, () async {
          reads++;
          return {
            ...fixtures.cold(),
            'catalogue': [
              for (var i = 0; i < 64; i++)
                cache.bucket(
                  i,
                  i == 0 ? [cache.product(stock: stock)] : [],
                  fingerprint: stock == 5 ? cache.hash : cache.nextHash,
                ),
            ],
          };
        }),
      ))!;
      final container = ProviderContainer();
      addTearDown(container.dispose);
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox());
        await tester.pump();
        await tester.runAsync(client.dispose);
      });
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: StoreRealtimeSync(
            client: client,
            now: tester.binding.clock.now,
            child: const SizedBox(),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
      final changes =
          (socket.join!['config'] as Map)['postgres_changes'] as List;
      expect(changes.first['table'], 'products');
      expect(
        changes.firstWhere((dynamic c) => c['table'] == 'orders')['filter'],
        'user_id=eq.alice',
      );
      expect(client.getChannels(), hasLength(1));
      await tester.pump(const Duration(seconds: 3));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
      expect(reads, 2);
      expect(
        container.read(storeProvider).products.map((p) => p.id),
        contains('product'),
      );
      expect(
        container.read(storeProvider).productById('product')!.stockQuantity,
        5,
      );
      final before = reads;
      stock = 11;
      for (var i = 0; i < 3; i++) {
        socket.stockChanged();
      }
      await tester.pump();
      await tester.pump(const Duration(seconds: 3));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
      expect(reads, before + 1);
      expect(
        container.read(storeProvider).productById('product')!.stockQuantity,
        11,
      );
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      await tester.pump();
      expect(socket.leaves, 1);
      final stopped = reads;
      await tester.pump(const Duration(minutes: 3));
      expect(reads, stopped);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      await tester.pump();
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      await tester.runAsync(() => client.realtime.disconnect());
    },
  );

  testWidgets(
    'replication failure uses the 30-second customer polling fallback',
    (tester) async {
      final socket = _Socket();
      var reads = 0;
      final client = (await tester.runAsync(
        () => _client(socket, () async {
          reads++;
          return fixtures.cold();
        }),
      ))!;
      final container = ProviderContainer();
      addTearDown(container.dispose);
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox());
        await tester.pump();
        await tester.runAsync(client.dispose);
      });
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: StoreRealtimeSync(
            client: client,
            now: tester.binding.clock.now,
            child: const SizedBox(),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(seconds: 3));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
      final before = reads;
      socket.failReplication();
      await tester.pump();
      await tester.pump(const Duration(seconds: 38));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
      expect(reads, before + 1);
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      await tester.runAsync(() => client.realtime.disconnect());
    },
  );
}
