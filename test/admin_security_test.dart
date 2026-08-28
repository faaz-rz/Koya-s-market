import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:koyas_supermarket/admin/widgets/admin_session_guard.dart';
import 'package:koyas_supermarket/features/store/providers/store_provider.dart';

void main() {
  test('admin database privileges require active staff and MFA AAL2', () {
    final migration = File(
      'supabase/migrations/202608220002_admin_mfa_security.sql',
    ).readAsStringSync();

    expect(migration, contains("auth.jwt() ->> 'aal'"));
    expect(migration, contains("= 'aal2'"));
    expect(migration, contains('active = true'));
    expect(migration, contains('where user_id = auth.uid()'));
    expect(
      migration,
      contains(
        'grant execute on function public.is_admin() to anon, authenticated',
      ),
    );
  });

  test('admin product writes are validated, audited, and RPC-only', () {
    final migration = File(
      'supabase/migrations/202608230001_admin_security_hardening.sql',
    ).readAsStringSync();
    final catalogueMigration = File(
      'supabase/migrations/202608270001_admin_catalogue_management.sql',
    ).readAsStringSync();
    final repository = File(
      'lib/features/store/data/supabase_store_repository.dart',
    ).readAsStringSync();
    expect(migration, contains('drop policy if exists products_admin_write'));
    expect(migration, contains('function public.admin_save_product'));
    expect(migration, contains('if not public.is_admin()'));
    expect(migration, contains("'create_product'"));
    expect(migration, contains("'update_product'"));
    expect(migration, contains('Product image was not uploaded by this admin'));
    expect(migration, contains('drop policy if exists categories_admin_write'));
    expect(migration, contains('using (user_id = auth.uid())'));
    expect(
      catalogueMigration,
      contains('function public.admin_save_product_v2'),
    );
    expect(catalogueMigration, contains("'archive_product'"));
    expect(catalogueMigration, contains("'restore_product'"));
    expect(catalogueMigration, contains('remove_product_image'));
    expect(catalogueMigration, contains('if not public.is_admin()'));
    expect(
      repository,
      contains("_client.rpc(\n        'admin_save_product_v2'"),
    );
    expect(repository, isNot(contains("from('products').insert")));
    expect(repository, isNot(contains("from('products').update")));
  });

  test('order pricing is MFA-admin-only, validated, and audited', () {
    final offerMigration = File(
      'supabase/migrations/202608240001_admin_delivery_and_offers.sql',
    ).readAsStringSync();
    final migration = File(
      'supabase/migrations/202608260002_admin_minimum_order.sql',
    ).readAsStringSync();
    final repository = File(
      'lib/features/store/data/supabase_store_repository.dart',
    ).readAsStringSync();
    final realtime = File(
      'lib/features/store/widgets/store_realtime_sync.dart',
    ).readAsStringSync();

    expect(migration, contains('function public.admin_update_order_pricing'));
    expect(migration, contains('if not public.is_admin()'));
    expect(migration, contains("'update_order_pricing'"));
    expect(migration, contains('to_jsonb(previous), to_jsonb(updated)'));
    expect(
      migration,
      contains(
        'revoke all on function public.admin_update_order_pricing(integer, integer, integer)',
      ),
    );
    expect(offerMigration, contains('set discount_price_paise = null'));
    expect(repository, contains("'admin_update_order_pricing'"));
    expect(repository, isNot(contains("from('store_settings').update")));
    expect(realtime, contains("table: 'store_settings'"));
  });

  test('manual payments and fulfilment contacts are secured and audited', () {
    final migration = File(
      'supabase/migrations/202608280001_admin_order_operations.sql',
    ).readAsStringSync();
    final repository = File(
      'lib/features/store/data/supabase_store_repository.dart',
    ).readAsStringSync();

    expect(migration, contains('customer_name_snapshot'));
    expect(migration, contains('delivery_recipient_name_snapshot'));
    expect(migration, contains('function public.snapshot_order_contacts'));
    expect(migration, contains('function public.set_order_paid_at'));
    expect(
      migration,
      contains('function public.require_payment_before_order_completion'),
    );
    expect(migration, contains('Record payment before completing this order'));
    expect(migration, contains('function public.admin_mark_order_paid'));
    expect(migration, contains('if not public.is_admin()'));
    expect(migration, contains("'mark_order_paid'"));
    expect(migration, contains('insert into public.admin_audit_logs'));
    expect(
      migration,
      contains('revoke all on function public.admin_mark_order_paid(uuid)'),
    );
    expect(repository, contains("'admin_mark_order_paid'"));
    expect(repository, contains("row['paid_at']"));
    expect(repository, contains("row['delivery_recipient_phone_snapshot']"));
  });

  test('production login does not expose demo identity or raw auth errors', () {
    final screen = File(
      'lib/features/auth/screens/login_screen.dart',
    ).readAsStringSync();

    expect(
      screen,
      contains("AppEnvironment.hasSupabaseConfig ? '' : 'ezlin@example.com'"),
    );
    expect(screen, isNot(contains(r'Could not sign in. $error')));
  });

  test('privileged functions and image storage use deny-by-default access', () {
    final migration = File(
      'supabase/migrations/202608230001_admin_security_hardening.sql',
    ).readAsStringSync();

    expect(migration, contains("security definer\nset search_path = ''"));
    expect(
      migration,
      contains(
        'revoke execute on all functions in schema public from public, anon, authenticated',
      ),
    );
    expect(
      migration,
      contains('(storage.foldername(name))[2] = auth.uid()::text'),
    );
    expect(migration, contains('owner_id = auth.uid()::text'));
    expect(
      migration,
      isNot(contains('create policy product_images_admin_update')),
    );
  });

  test('store admin state comes from the MFA-aware database function', () {
    final repository = File(
      'lib/features/store/data/supabase_store_repository.dart',
    ).readAsStringSync();

    expect(repository, contains("_client.rpc('is_admin')"));
    expect(repository, isNot(contains(".from('admins')")));
  });

  test(
    'payment callbacks preserve captured status and validate exact totals',
    () {
      final verifier = File(
        'supabase/functions/verify-razorpay-payment/index.ts',
      ).readAsStringSync();
      final webhook = File(
        'supabase/functions/razorpay-webhook/index.ts',
      ).readAsStringSync();
      final confirmation = File(
        'lib/features/orders/screens/order_confirmation_screen.dart',
      ).readAsStringSync();

      expect(
        verifier,
        contains('providerPayment.amount !== order.total_paise'),
      );
      expect(verifier, contains('providerPayment.status === "captured"'));
      expect(webhook, contains('paymentMatches'));
      expect(webhook, contains('.neq("payment_status", "paid")'));
      expect(webhook, isNot(contains('payload: event.payload')));
      expect(confirmation, contains('Payment confirmation pending'));
    },
  );

  test('notification workers claim queue rows atomically', () {
    final migration = File(
      'supabase/migrations/202608230002_notification_claims.sql',
    ).readAsStringSync();
    final function = File(
      'supabase/functions/send-order-notifications/index.ts',
    ).readAsStringSync();

    expect(migration, contains('for update skip locked'));
    expect(
      migration,
      contains("queue.locked_at < now() - interval '5 minutes'"),
    );
    expect(migration, contains('to service_role'));
    expect(function, contains('"claim_notification_batch"'));
    expect(function, contains('timingSafeEqual'));
  });

  test('Vercel admin deployment includes browser security controls', () {
    final config =
        jsonDecode(File('vercel.json').readAsStringSync())
            as Map<String, dynamic>;
    final groups = config['headers'] as List<dynamic>;
    final securityHeaders = <String, String>{};
    for (final header
        in (groups.first as Map<String, dynamic>)['headers'] as List<dynamic>) {
      final values = header as Map<String, dynamic>;
      securityHeaders[values['key'] as String] = values['value'] as String;
    }

    expect(
      securityHeaders['Content-Security-Policy'],
      contains("object-src 'none'"),
    );
    expect(
      securityHeaders['Content-Security-Policy'],
      contains("frame-ancestors 'none'"),
    );
    expect(securityHeaders['X-Frame-Options'], 'DENY');
    expect(securityHeaders['X-Content-Type-Options'], 'nosniff');
    expect(securityHeaders['Cross-Origin-Resource-Policy'], 'same-origin');
    expect(securityHeaders['X-Robots-Tag'], contains('noindex'));
    expect(config['rewrites'], isNotEmpty);

    final noStoreSources = groups
        .cast<Map<String, dynamic>>()
        .where(
          (group) => (group['headers'] as List<dynamic>).any(
            (header) =>
                (header as Map<String, dynamic>)['key'] == 'Cache-Control' &&
                header['value'] == 'no-store, max-age=0',
          ),
        )
        .map((group) => group['source'])
        .toSet();
    expect(noStoreSources, contains('/main.dart.js'));
    expect(noStoreSources, contains('/flutter_bootstrap.js'));
  });

  testWidgets('admin inactivity lock clears the store and returns to login', (
    tester,
  ) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container
        .read(storeProvider.notifier)
        .loginDemo(email: 'staff@koyas.in', isAdmin: true);

    final router = GoRouter(
      initialLocation: '/dashboard',
      routes: [
        GoRoute(
          path: '/dashboard',
          builder: (_, _) => const AdminSessionGuard(
            idleTimeout: Duration(milliseconds: 50),
            child: Scaffold(body: Text('Protected dashboard')),
          ),
        ),
        GoRoute(
          path: '/login',
          builder: (_, state) => Scaffold(
            body: Text(state.uri.queryParameters['reason'] ?? 'login'),
          ),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    expect(find.text('Protected dashboard'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 80));
    await tester.pumpAndSettle();

    expect(find.text('expired'), findsOneWidget);
    expect(container.read(storeProvider).isAuthenticated, isFalse);
    expect(container.read(storeProvider).isAdminAccount, isFalse);
  });
}
