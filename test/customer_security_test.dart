import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:koyas_supermarket/core/config/app_environment.dart';

void main() {
  test('customer demo is limited to non-release builds without a backend', () {
    expect(AppEnvironment.allowCustomerDemo, isTrue);

    final environment = File(
      'lib/core/config/app_environment.dart',
    ).readAsStringSync();
    final entrypoint = File('lib/main.dart').readAsStringSync();
    final gradle = File('android/app/build.gradle.kts').readAsStringSync();

    expect(environment, contains('!kReleaseMode && !hasSupabaseConfig'));
    expect(
      entrypoint,
      contains('kReleaseMode && !AppEnvironment.hasProductionCustomerConfig'),
    );
    expect(gradle, contains('Release signing is required'));
    expect(gradle, contains('SUPABASE_URL'));
    expect(gradle, contains('SUPABASE_ANON_KEY'));
  });

  test(
    'native customer sessions use protected storage and clear on expiry',
    () {
      final bootstrap = File(
        'lib/core/services/backend_bootstrap.dart',
      ).readAsStringSync();
      final storage = File(
        'lib/core/services/secure_auth_storage.dart',
      ).readAsStringSync();
      final app = File('lib/app/app.dart').readAsStringSync();
      final manifest = File(
        'android/app/src/main/AndroidManifest.xml',
      ).readAsStringSync();

      expect(bootstrap, contains('const SecureAuthStorage()'));
      expect(bootstrap, contains('pkceAsyncStorage'));
      expect(
        storage,
        contains('KeychainAccessibility.first_unlock_this_device'),
      );
      expect(storage, contains("storageNamespace: 'koyas_auth'"));
      expect(storage, contains('useSessionStorage: true'));
      expect(app, contains('auth.onAuthStateChange'));
      expect(app, contains('state.session != null'));
      expect(app, contains('storeProvider.notifier).logout()'));
      expect(manifest, contains('android:allowBackup="false"'));
      expect(manifest, contains('android:usesCleartextTraffic="false"'));
    },
  );

  test('database enforces order bounds, rate limits, and stock expiry', () {
    final migration = File(
      'supabase/migrations/202608270002_customer_security_hardening.sql',
    ).readAsStringSync();

    expect(migration, contains('rename to place_order_internal'));
    expect(migration, contains('pg_advisory_xact_lock'));
    expect(
      migration,
      contains('pg_catalog.jsonb_array_length(requested_items) > 50'),
    );
    expect(migration, contains('active_order_count >= 3'));
    expect(migration, contains('recent_order_count >= 10'));
    expect(migration, contains("interval '1 hour'"));
    expect(migration, contains("interval '20 minutes'"));
    expect(migration, contains('for update skip locked'));
    expect(migration, contains('stock_quantity + restored.quantity'));
    expect(
      migration,
      contains('to service_role;'),
      reason: 'Only a trusted scheduler may release expired reservations.',
    );
  });

  test('device tokens are bounded, transferable, and RPC-only', () {
    final migration = File(
      'supabase/migrations/202608270002_customer_security_hardening.sql',
    ).readAsStringSync();
    final repository = File(
      'lib/features/notifications/data/notification_repository.dart',
    ).readAsStringSync();
    final worker = File(
      'supabase/functions/send-order-notifications/index.ts',
    ).readAsStringSync();

    expect(migration, contains('drop policy if exists device_tokens_own_all'));
    expect(migration, contains('function public.register_device_token'));
    expect(migration, contains('limit 5'));
    expect(repository, contains("'register_device_token'"));
    expect(repository, contains("'unregister_device_token'"));
    expect(repository, isNot(contains("from('device_tokens')")));
    expect(worker, contains("errorCode==='UNREGISTERED'"));
    expect(worker, contains(".from('device_tokens').delete()"));
  });

  test('production catalogue avoids third-party and cleartext images', () {
    final repository = File(
      'lib/features/store/data/supabase_store_repository.dart',
    ).readAsStringSync();
    final visual = File(
      'lib/features/products/widgets/product_visual.dart',
    ).readAsStringSync();

    expect(repository, isNot(contains("row['external_image_url']")));
    expect(repository, contains(".from('product-images')"));
    expect(visual, contains("imageUri.scheme == 'https'"));
  });

  test('online payment creation rejects expired or closed orders', () {
    final function = File(
      'supabase/functions/create-razorpay-order/index.ts',
    ).readAsStringSync();

    expect(function, contains('order.order_status !== "placed"'));
    expect(function, contains('payment_expires_at'));
    expect(function, contains('Payment window expired'));
  });
}
