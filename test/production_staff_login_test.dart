import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:koyas_supermarket/admin/screens/admin_login_screen.dart';
import 'package:koyas_supermarket/admin/widgets/admin_session_guard.dart';
import 'package:koyas_supermarket/core/theme/app_theme.dart';
import 'package:koyas_supermarket/features/auth/data/auth_repository.dart';
import 'package:koyas_supermarket/features/auth/data/otp_send_limiter.dart';
import 'package:koyas_supermarket/features/store/data/supabase_store_repository.dart';
import 'package:koyas_supermarket/features/store/providers/store_provider.dart';
import 'production_login_test.dart'
    show LoginFixture, fixtureFor, reply, signedIn;
import 'store_repository_sync_test.dart' show cold;

// Email verification exercises the real SDK with mocked HTTP. Staff access
// remains server-approved; no authenticator endpoint is part of this flow.
class StaffAuth extends AuthRepository {
  StaffAuth(LoginFixture fixture, {this.approved = true})
    : super(
        client: fixture.client,
        sendLimiter: OtpSendLimiter(now: () => fixture.now),
      );
  bool approved;
  bool offline = false;
  @override
  Future<bool> isApprovedAdmin() async {
    if (offline) throw Exception('Temporary network failure');
    return approved && currentUser != null;
  }
}

Future<ProviderContainer> openStaff(
  WidgetTester tester,
  LoginFixture fixture,
  StaffAuth auth, {
  Future<RemoteStoreBundle> Function()? loadStore,
  double width = 390,
  double scale = 1,
}) async {
  tester.view.physicalSize = Size(width, 844);
  tester.view.devicePixelRatio = 1;
  tester.platformDispatcher.textScaleFactorTestValue = scale;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  addTearDown(() => tester.runAsync(fixture.client.dispose));
  final container = ProviderContainer();
  addTearDown(container.dispose);
  final router = GoRouter(
    initialLocation: '/login',
    routes: [
      GoRoute(
        path: '/login',
        builder: (_, _) => AdminLoginScreen(
          authRepository: auth,
          loadStore:
              loadStore ??
              SupabaseStoreRepository(client: fixture.client).loadStore,
        ),
      ),
      GoRoute(
        path: '/dashboard',
        builder: (_, _) =>
            const Scaffold(body: Text('Protected dashboard opened')),
      ),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(theme: AppTheme.light, routerConfig: router),
    ),
  );
  addTearDown(() async => tester.pumpWidget(const SizedBox.shrink()));
  await tester.pumpAndSettle();
  return container;
}

Future<void> verifyEmail(WidgetTester tester) async {
  await tester.enterText(
    find.byKey(const Key('admin-email')),
    'alice@example.test',
  );
  await tap(tester, 'admin-login');
  await tester.pumpAndSettle();
  await tester.enterText(find.byKey(const Key('admin-otp')), '123456');
  await tap(tester, 'admin-login');
  await tester.pumpAndSettle();
}

Future<void> tap(WidgetTester tester, String key) async {
  FocusManager.instance.primaryFocus?.unfocus();
  await tester.pumpAndSettle();
  final target = find.byKey(Key(key));
  await Scrollable.ensureVisible(tester.element(target), alignment: 0.5);
  await tester.pumpAndSettle();
  await tester.tap(target);
  await tester.pump();
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 30)),
  );
}

Future<LoginFixture> staffFixture(WidgetTester tester, {bool isAdmin = true}) =>
    fixtureFor(
      tester,
      handler: (request) async {
        if (request.url.path == '/auth/v1/verify') return reply(signedIn());
        if (request.url.path == '/rest/v1/rpc/sync_store') {
          return reply({...cold(), 'is_admin': isAdmin});
        }
        return reply({});
      },
    );

void main() {
  testWidgets(
    'staff guard ignores inactivity and network failures but revocation clears access',
    (tester) async {
      final fixture = await staffFixture(tester);
      addTearDown(() => tester.runAsync(fixture.client.dispose));
      await tester.runAsync(
        () => fixture.auth.verifyEmailOtp(
          email: 'alice@example.test',
          token: '123456',
        ),
      );
      final auth = StaffAuth(fixture);
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container
          .read(storeProvider.notifier)
          .loginDemo(email: 'alice@example.test', isAdmin: true);
      final router = GoRouter(
        initialLocation: '/dashboard',
        routes: [
          GoRoute(
            path: '/dashboard',
            builder: (_, _) => AdminSessionGuard(
              authRepository: auth,
              child: const Scaffold(body: Text('Protected dashboard')),
            ),
          ),
          GoRoute(
            path: '/login',
            builder: (_, _) => const Scaffold(body: Text('Staff sign in')),
          ),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp.router(
            theme: AppTheme.light,
            routerConfig: router,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.pump(const Duration(minutes: 30));
      await tester.pumpAndSettle();
      expect(find.text('Protected dashboard'), findsOneWidget);
      expect(container.read(storeProvider).isAdminAccount, true);
      auth.offline = true;
      await tester.pump(const Duration(minutes: 5));
      await tester.pumpAndSettle();
      expect(find.text('Protected dashboard'), findsOneWidget);
      auth.offline = false;
      auth.approved = false;
      await tester.pump(const Duration(minutes: 5));
      await tester.pumpAndSettle();
      expect(find.text('Staff sign in'), findsOneWidget);
      expect(container.read(storeProvider).isAuthenticated, false);
      expect(container.read(storeProvider).isAdminAccount, false);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('unapproved email cannot reach the staff dashboard', (
    tester,
  ) async {
    final fixture = await staffFixture(tester);
    final auth = StaffAuth(fixture, approved: false);
    final container = await openStaff(tester, fixture, auth);
    await verifyEmail(tester);
    expect(
      find.text('This account is not approved for staff access.'),
      findsOneWidget,
    );
    expect(auth.currentUser, isNull);
    expect(fixture.calls('/auth/v1/factors'), 0);
    expect(fixture.calls('/rest/v1/rpc/sync_store'), 0);
    expect(container.read(storeProvider).isAuthenticated, isFalse);
  });

  testWidgets(
    'server-denied staff role cannot be bypassed by a stale client approval',
    (tester) async {
      final fixture = await staffFixture(tester, isAdmin: false);
      final auth = StaffAuth(fixture);
      final container = await openStaff(tester, fixture, auth);
      await verifyEmail(tester);
      expect(find.text('Protected dashboard opened'), findsNothing);
      expect(container.read(storeProvider).isAuthenticated, isFalse);
      expect(auth.currentUser, isNull);
      expect(
        find.text('This account is not approved for staff access.'),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'email-only staff sign-in retries a failed dashboard load without replaying the code',
    (tester) async {
      final fixture = await staffFixture(tester);
      final auth = StaffAuth(fixture);
      var loads = 0;
      final container = await openStaff(
        tester,
        fixture,
        auth,
        loadStore: () {
          if (++loads == 1) throw Exception('Temporary dashboard failure');
          return SupabaseStoreRepository(client: fixture.client).loadStore();
        },
      );
      await verifyEmail(tester);
      expect(find.byKey(const Key('admin-mfa-code')), findsNothing);
      expect(container.read(storeProvider).isAuthenticated, isFalse);
      expect(loads, 1);
      await tap(tester, 'admin-login');
      await tester.pumpAndSettle();
      expect(find.text('Protected dashboard opened'), findsOneWidget);
      expect(fixture.calls('/auth/v1/verify'), 1);
      expect(fixture.calls('/auth/v1/factors'), 0);
      expect(container.read(storeProvider).isAdminAccount, isTrue);
    },
  );

  testWidgets(
    'restored email-verified staff session opens without another code',
    (tester) async {
      final fixture = await staffFixture(tester);
      await tester.runAsync(
        () => fixture.auth.verifyEmailOtp(
          email: 'alice@example.test',
          token: '123456',
        ),
      );
      final auth = StaffAuth(fixture);
      await openStaff(tester, fixture, auth);
      expect(auth.currentUser?.email, 'alice@example.test');
      expect(find.byKey(const Key('admin-mfa-code')), findsNothing);
      expect(find.text('Protected dashboard opened'), findsOneWidget);
      expect(fixture.calls('/auth/v1/otp'), 0);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('staff email login fits 320px with large text', (tester) async {
    final fixture = await staffFixture(tester);
    await openStaff(tester, fixture, StaffAuth(fixture), width: 320, scale: 2);
    await tester.enterText(
      find.byKey(const Key('admin-email')),
      'alice@example.test',
    );
    await tap(tester, 'admin-login');
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('admin-otp')), findsOneWidget);
    expect(find.byKey(const Key('admin-mfa-code')), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
