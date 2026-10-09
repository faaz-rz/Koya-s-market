import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koyas_supermarket/app/app.dart';
import 'package:koyas_supermarket/app/router/app_router.dart';
import 'package:koyas_supermarket/features/store/providers/store_provider.dart';
import 'package:koyas_supermarket/features/admin/printing/order_bill.dart';

void main() {
  testWidgets(
    'customer screens show their own number; global reference and staff bill remain unchanged',
    (tester) async {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      c.read(storeProvider.notifier).loginDemo();
      final order = c.read(storeProvider).orders.first;
      expect(order.customerDisplayNumber, '4');
      expect(order.copyWith(status: order.status).customerOrderNumber, 4);
      final router = c.read(appRouterProvider)..go('/order/${order.id}');
      await tester.pumpWidget(
        UncontrolledProviderScope(container: c, child: const KoyasApp()),
      );
      await tester.pumpAndSettle();
      expect(find.text('Order #4'), findsOneWidget);
      expect(find.text('Order #34621'), findsNothing);
      router.go('/orders');
      await tester.pumpAndSettle();
      expect(find.text('Order #4'), findsOneWidget);
      expect(order.displayReference, 'KOY34621');
      expect(buildOrderBillHtml(order), contains('KOY34621'));
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
