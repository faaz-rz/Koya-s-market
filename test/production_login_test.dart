import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:koyas_supermarket/core/services/network_status.dart';
import 'package:koyas_supermarket/core/theme/app_colors.dart';
import 'package:koyas_supermarket/core/theme/app_theme.dart';
import 'package:koyas_supermarket/core/widgets/four_dot_loader.dart';
import 'package:koyas_supermarket/core/widgets/customer_backdrop.dart';
import 'package:koyas_supermarket/features/auth/data/auth_repository.dart';
import 'package:koyas_supermarket/features/auth/data/otp_send_limiter.dart';
import 'package:koyas_supermarket/features/auth/screens/login_screen.dart';
import 'package:koyas_supermarket/features/store/data/supabase_store_repository.dart';
import 'package:koyas_supermarket/features/store/providers/store_provider.dart';

import 'store_repository_sync_test.dart' show cold;

http.Response reply(Object data, [int status = 200]) => http.Response(
  jsonEncode(data),
  status,
  headers: {'content-type': 'application/json'},
);

Map<String, dynamic> signedIn() {
  final claims = base64Url.encode(
    utf8.encode(
      jsonEncode({
        'exp': 4102444800,
        'sub': 'alice',
        'session_id': 'test-session',
      }),
    ),
  );
  return {
    'access_token': 'test.$claims.test',
    'refresh_token': 'test-refresh',
    'token_type': 'bearer',
    'expires_in': 3600,
    'user': {
      'id': 'alice',
      'email': 'alice@example.test',
      'aud': 'authenticated',
      'created_at': '2026-10-05T00:00:00Z',
    },
  };
}

class LoginFixture {
  LoginFixture({Future<http.Response> Function(http.Request)? handler}) {
    client = SupabaseClient(
      'https://store.test',
      'test-public',
      httpClient: MockClient((request) async {
        requests.add(request);
        final response = handler != null
            ? await handler(request)
            : request.url.path == '/auth/v1/verify'
            ? reply(signedIn())
            : request.url.path == '/rest/v1/rpc/sync_store'
            ? reply(cold())
            : reply({});
        return http.Response.bytes(
          response.bodyBytes,
          response.statusCode,
          headers: response.headers,
          request: request,
        );
      }),
      authOptions: AuthClientOptions(
        autoRefreshToken: false,
        pkceAsyncStorage: _MemoryPkceStorage(),
      ),
    );
    auth = AuthRepository(
      client: client,
      sendLimiter: OtpSendLimiter(now: () => now),
    );
  }
  late final SupabaseClient client;
  late final AuthRepository auth;
  final requests = <http.Request>[];
  DateTime now = DateTime.utc(2026, 10, 5);
  int calls(String path) => requests.where((r) => r.url.path == path).length;

  Future<ProviderContainer> open(
    WidgetTester tester, {
    Future<RemoteStoreBundle> Function()? loadStore,
    double width = 390,
    double scale = 1,
    double keyboard = 0,
  }) async {
    tester.view.physicalSize = Size(width, 844);
    tester.view.devicePixelRatio = 1;
    tester.view.viewInsets = FakeViewPadding(bottom: keyboard);
    tester.platformDispatcher.textScaleFactorTestValue = scale;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetViewInsets);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    addTearDown(() => tester.runAsync(client.dispose));
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final router = GoRouter(
      initialLocation: '/login',
      routes: [
        GoRoute(
          path: '/login',
          builder: (_, _) => LoginScreen(
            authRepository: auth,
            loadStore:
                loadStore ?? SupabaseStoreRepository(client: client).loadStore,
          ),
        ),
        GoRoute(
          path: '/home',
          builder: (_, _) => const Scaffold(body: Text('Store opened')),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(
          debugShowCheckedModeBanner: false,
          theme: AppTheme.customer,
          builder: (_, child) => CustomerBackdrop(child: child!),
          routerConfig: router,
        ),
      ),
    );
    addTearDown(() async => tester.pumpWidget(const SizedBox.shrink()));
    await tester.pumpAndSettle();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 30)),
    );
    return container;
  }
}

class _MemoryPkceStorage implements GotrueAsyncStorage {
  final _values = <String, String>{};
  @override
  Future<String?> getItem({required String key}) async => _values[key];
  @override
  Future<void> setItem({required String key, required String value}) async {
    _values[key] = value;
  }

  @override
  Future<void> removeItem({required String key}) async {
    _values.remove(key);
  }
}

Future<LoginFixture> fixtureFor(
  WidgetTester tester, {
  Future<http.Response> Function(http.Request)? handler,
}) async {
  // Initialize the SDK's JSON worker in a real async zone, as in the app.
  return (await tester.runAsync(() async {
    final fixture = LoginFixture(handler: handler);
    await Future<void>.delayed(const Duration(milliseconds: 30));
    return fixture;
  }))!;
}

Future<void> tap(WidgetTester tester, String key) async {
  final target = find.byKey(Key(key));
  await tester.ensureVisible(target);
  await tester.pump();
  await tester.tap(target);
  await tester.pump();
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 30)),
  );
}

Future<void> requestCode(WidgetTester tester) async {
  await tester.enterText(
    find.byKey(const Key('login-email')),
    ' Alice@Example.Test ',
  );
  await tap(tester, 'customer-login');
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'production login starts blank and validates email before sending',
    (tester) async {
      final fixture = await fixtureFor(tester);
      await fixture.open(tester);
      expect(
        tester
            .widget<TextFormField>(find.byKey(const Key('login-email')))
            .controller!
            .text,
        isEmpty,
      );
      expect(find.textContaining('local demo'), findsNothing);
      await tester.enterText(
        find.byKey(const Key('login-email')),
        'bad@@example.com',
      );
      await tap(tester, 'customer-login');
      await tester.pumpAndSettle();
      expect(find.text('Enter a valid email address'), findsOneWidget);
      expect(fixture.requests, isEmpty);
      await requestCode(tester);
      final sent = jsonDecode(fixture.requests.single.body) as Map;
      expect(sent['email'], 'alice@example.test');
      expect(sent['create_user'], isTrue);
      expect(sent.containsKey('phone'), isFalse);
      expect(find.byKey(const Key('login-otp')), findsOneWidget);
      expect(
        tester
            .widget<TextButton>(find.byKey(const Key('login-resend-code')))
            .onPressed,
        isNull,
      );
    },
  );

  testWidgets('duplicate taps send one email and show the four-dot loader', (
    tester,
  ) async {
    final pending = Completer<http.Response>();
    final fixture = await fixtureFor(tester, handler: (_) => pending.future);
    await fixture.open(tester);
    await tester.enterText(
      find.byKey(const Key('login-email')),
      'alice@example.test',
    );
    await tap(tester, 'customer-login');
    await tester.tap(find.byKey(const Key('customer-login')));
    await tester.pump(const Duration(milliseconds: 100));
    expect(fixture.calls('/auth/v1/otp'), 1);
    expect(find.byType(FourDotLoader), findsOneWidget);
    pending.complete(reply({}));
    await tester.pumpAndSettle();
    expect(find.byType(FourDotLoader), findsNothing);
  });

  testWidgets('resending stays on the OTP step and respects the countdown', (
    tester,
  ) async {
    final fixture = await fixtureFor(tester);
    await fixture.open(tester);
    await requestCode(tester);
    await tester.enterText(find.byKey(const Key('login-otp')), '123456');
    fixture.now = fixture.now.add(const Duration(seconds: 60));
    await tester.pump(const Duration(seconds: 1));
    await tap(tester, 'login-resend-code');
    await tester.pumpAndSettle();
    expect(fixture.calls('/auth/v1/otp'), 2);
    expect(find.textContaining('latest code'), findsOneWidget);
    expect(
      tester
          .widget<TextFormField>(find.byKey(const Key('login-otp')))
          .controller!
          .text,
      '123456',
    );
    expect(
      tester
          .widget<TextButton>(find.byKey(const Key('login-resend-code')))
          .onPressed,
      isNull,
    );
  });

  testWidgets(
    'invalid codes remain editable and errors have the error colour',
    (tester) async {
      final fixture = await fixtureFor(
        tester,
        handler: (request) async => request.url.path == '/auth/v1/verify'
            ? reply({
                'msg': 'Token has expired or is invalid',
                'code': 'otp_expired',
              }, 403)
            : reply({}),
      );
      await fixture.open(tester);
      await requestCode(tester);
      await tester.enterText(find.byKey(const Key('login-otp')), '12ab 3456');
      expect(
        tester
            .widget<TextFormField>(find.byKey(const Key('login-otp')))
            .controller!
            .text,
        '123456',
      );
      await tap(tester, 'customer-login');
      await tester.pumpAndSettle();
      expect(find.textContaining('code was not accepted'), findsOneWidget);
      expect(
        tester
            .widget<Text>(find.byKey(const Key('login-message')))
            .style!
            .color,
        AppColors.error,
      );
      expect(fixture.client.auth.currentUser, isNull);
    },
  );

  testWidgets('successful OTP hydrates the real store before routing home', (
    tester,
  ) async {
    final fixture = await fixtureFor(tester);
    final container = await fixture.open(tester);
    await requestCode(tester);
    await tester.enterText(find.byKey(const Key('login-otp')), '123456');
    await tap(tester, 'customer-login');
    await tester.pumpAndSettle();
    expect(find.text('Store opened'), findsOneWidget);
    expect(container.read(storeProvider).profile!.id, 'alice');
    expect(container.read(storeProvider).isAuthenticated, isTrue);
    expect(fixture.calls('/auth/v1/verify'), 1);
    expect(fixture.calls('/rest/v1/rpc/sync_store'), 1);
  });

  testWidgets(
    'store-load failure retries the signed-in session without reusing the OTP',
    (tester) async {
      final fixture = await fixtureFor(tester);
      var loads = 0;
      await fixture.open(
        tester,
        loadStore: () async {
          if (++loads == 1) throw const NoInternetException();
          return SupabaseStoreRepository(client: fixture.client).loadStore();
        },
      );
      await requestCode(tester);
      await tester.enterText(find.byKey(const Key('login-otp')), '123456');
      await tap(tester, 'customer-login');
      await tester.pumpAndSettle();
      expect(find.text(noInternetMessage), findsOneWidget);
      expect(find.text('Retry opening store'), findsOneWidget);
      expect(find.byKey(const Key('login-otp')), findsNothing);
      await tap(tester, 'customer-login');
      await tester.pumpAndSettle();
      expect(find.text('Store opened'), findsOneWidget);
      expect(fixture.calls('/auth/v1/verify'), 1);
      expect(loads, 2);
    },
  );

  testWidgets('logout during a store load cannot restore private data', (
    tester,
  ) async {
    final pending = Completer<RemoteStoreBundle>();
    final fixture = await fixtureFor(tester);
    final container = await fixture.open(
      tester,
      loadStore: () => pending.future,
    );
    await requestCode(tester);
    await tester.enterText(find.byKey(const Key('login-otp')), '123456');
    await tap(tester, 'customer-login');
    await tester.pump(const Duration(milliseconds: 100));
    final bundle = await tester.runAsync(
      () => SupabaseStoreRepository(client: fixture.client).loadStore(),
    );
    await fixture.auth.signOut();
    pending.complete(bundle!);
    await tester.pumpAndSettle();
    expect(find.text('Store opened'), findsNothing);
    expect(container.read(storeProvider).isAuthenticated, isFalse);
    expect(find.textContaining('session expired'), findsOneWidget);
  });

  for (final viewport in [
    (width: 320.0, scale: 2.0),
    (width: 390.0, scale: 1.0),
  ]) {
    testWidgets(
      'production email and OTP pages fit ${viewport.width}px with a keyboard',
      (tester) async {
        final fixture = await fixtureFor(tester);
        await fixture.open(
          tester,
          width: viewport.width,
          scale: viewport.scale,
          keyboard: 300,
        );
        expect(tester.takeException(), isNull);
        await requestCode(tester);
        expect(tester.takeException(), isNull);
        await tester.ensureVisible(find.byKey(const Key('login-otp')));
        expect(tester.takeException(), isNull);
      },
    );
  }
}
