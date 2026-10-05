import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koyas_supermarket/features/admin/widgets/resource_usage_button.dart';

void main() {
  for (final scale in [1.0, 2.0]) {
    testWidgets(
      'hosting usage dialog is on-demand and fits 320px at text scale $scale',
      (tester) async {
        tester.view.physicalSize = const Size(320, 740);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        var requests = 0;
        await tester.pumpWidget(
          MaterialApp(
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(scale)),
              child: child!,
            ),
            home: Scaffold(
              body: ResourceUsageButton(
                loadUsage: () async {
                  requests++;
                  return {
                    'database_bytes': 400000000,
                    'storage_bytes': 120000000,
                    'product_count': 3200,
                    'order_count': 100,
                    'inventory_receipt_count': 200,
                  };
                },
              ),
            ),
          ),
        );
        expect(requests, 0);
        await tester.tap(find.text('Check hosting usage'));
        await tester.pumpAndSettle();
        expect(requests, 1);
        expect(find.textContaining('Above 75%'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.tap(find.text('Close'));
        await tester.pumpAndSettle();
      },
    );
  }
  testWidgets(
    'usage query failure is explained without disclosing backend errors',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ResourceUsageButton(
              loadUsage: () async => throw StateError('private backend detail'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Check hosting usage'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Could not check usage'), findsOneWidget);
      expect(find.textContaining('private backend detail'), findsNothing);
    },
  );
}
