import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:koyas_supermarket/admin/screens/admin_login_screen.dart';
import 'package:koyas_supermarket/core/theme/app_theme.dart';
import 'package:koyas_supermarket/features/auth/data/auth_repository.dart';
import 'package:koyas_supermarket/features/auth/data/otp_send_limiter.dart';
import 'package:koyas_supermarket/features/store/data/supabase_store_repository.dart';
import 'package:koyas_supermarket/features/store/providers/store_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'production_login_test.dart'
    show LoginFixture, fixtureFor, reply, signedIn;
import 'store_repository_sync_test.dart' show cold;

// Email verification uses the real SDK with mocked HTTP. MFA is injected here
// to exercise UI transitions; database tests independently enforce AAL2.
class StaffAuth extends AuthRepository {
  StaffAuth(LoginFixture fixture, {this.approved = true})
    : super(
        client: fixture.client,
        sendLimiter: OtpSendLimiter(now: () => fixture.now),
      );
  final bool approved;
  bool aal2 = false;
  int mfaVerifications = 0;
  int preparations = 0;
  @override
  bool get hasAal2Session => aal2;
  @override
  Future<bool> isApprovedAdmin() async => approved && currentUser != null;
  @override
  Future<AdminMfaChallenge> prepareAdminMfa() async {
    preparations++;
    return const AdminMfaChallenge(factorId: 'staff-factor');
  }

  @override
  Future<void> verifyAdminMfa({
    required String factorId,
    required String code,
  }) async {
    mfaVerifications++;
    if (code != '123456') throw const AuthException('Invalid authenticator');
    aal2 = true;
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

Future<LoginFixture> staffFixture(WidgetTester tester) => fixtureFor(
  tester,
  handler: (request) async {
    if (request.url.path == '/auth/v1/verify') return reply(signedIn());
    if (request.url.path == '/rest/v1/rpc/sync_store') {
      return reply({...cold(), 'is_admin': true});
    }
    return reply({});
  },
);

void main() {
  testWidgets('unapproved email cannot reach MFA or the dashboard', (
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
    expect(auth.preparations, 0);
    expect(fixture.calls('/rest/v1/rpc/sync_store'), 0);
    expect(container.read(storeProvider).isAuthenticated, isFalse);
  });

  testWidgets(
    'staff must pass MFA and a failed dashboard load retries without replaying codes',
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
      expect(find.byKey(const Key('admin-mfa-code')), findsOneWidget);
      expect(container.read(storeProvider).isAuthenticated, isFalse);
      expect(loads, 0);
      await tester.enterText(find.byKey(const Key('admin-mfa-code')), '000000');
      await tap(tester, 'admin-login');
      await tester.pumpAndSettle();
      expect(loads, 0);
      expect(
        find.textContaining('authenticator code was not accepted'),
        findsOneWidget,
      );
      await tester.enterText(find.byKey(const Key('admin-mfa-code')), '123456');
      await tap(tester, 'admin-login');
      await tester.pumpAndSettle();
      expect(loads, 1);
      await tap(tester, 'admin-login');
      await tester.pumpAndSettle();
      expect(find.text('Protected dashboard opened'), findsOneWidget);
      expect(fixture.calls('/auth/v1/verify'), 1);
      expect(
        auth.mfaVerifications,
        2,
      ); // One rejected attempt, one successful one.
      expect(container.read(storeProvider).isAdminAccount, isTrue);
    },
  );

  testWidgets('restored staff session fills its email and completes MFA', (
    tester,
  ) async {
    final fixture = await staffFixture(tester);
    await tester.runAsync(
      () => fixture.auth.verifyEmailOtp(
        email: 'alice@example.test',
        token: '123456',
      ),
    );
    final auth = StaffAuth(fixture);
    await openStaff(tester, fixture, auth);
    expect(
      tester
          .widget<TextFormField>(find.byKey(const Key('admin-email')))
          .controller!
          .text,
      'alice@example.test',
    );
    expect(find.byKey(const Key('admin-mfa-code')), findsOneWidget);
    await tester.enterText(find.byKey(const Key('admin-mfa-code')), '123456');
    await tap(tester, 'admin-login');
    await tester.pumpAndSettle();
    expect(find.text('Protected dashboard opened'), findsOneWidget);
    expect(fixture.calls('/auth/v1/otp'), 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('staff login and MFA fit 320px with large text', (tester) async {
    final fixture = await staffFixture(tester);
    await openStaff(tester, fixture, StaffAuth(fixture), width: 320, scale: 2);
    await verifyEmail(tester);
    expect(find.byKey(const Key('admin-mfa-code')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
