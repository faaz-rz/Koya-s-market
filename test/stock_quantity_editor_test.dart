import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koyas_supermarket/features/admin/widgets/stock_quantity_editor.dart';
import 'package:koyas_supermarket/features/products/models/product.dart';

const product = Product(
  id: 'test-stock',
  categoryId: 'category',
  name: 'Rice',
  description: '',
  unit: '1 kg',
  pricePaise: 10000,
  stockQuantity: 20,
  visualKey: 'rice',
  revision: 3,
);

void main() {
  testWidgets('rapid taps stay local and save one combined atomic adjustment', (
    tester,
  ) async {
    var calls = 0;
    final pending = Completer<bool>();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StockQuantityEditor(
            product: product,
            busy: false,
            onSetStock: (_, _) async => throw StateError('Expected delta'),
            onAdjustStock: (snapshot, delta) {
              expect(snapshot.revision, 3);
              expect(delta, 5);
              calls++;
              return pending.future;
            },
          ),
        ),
      ),
    );
    for (var i = 0; i < 5; i++) {
      await tester.tap(
        find.byKey(const Key('admin-stock-increase-test-stock')),
      );
      await tester.pump();
    }
    expect(calls, 0);
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      '25',
    );
    await tester.tap(find.text('Save'));
    await tester.pump();
    await tester.tap(find.byKey(const Key('admin-stock-save-test-stock')));
    expect(calls, 1);
    expect(tester.widget<TextField>(find.byType(TextField)).enabled, false);
    pending.complete(true);
    await tester.pumpAndSettle();
    expect(calls, 1);
  });

  testWidgets('typing a large count saves once and keeps a failed draft', (
    tester,
  ) async {
    var calls = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StockQuantityEditor(
            product: product,
            busy: false,
            onSetStock: (snapshot, quantity) async {
              expect(snapshot.revision, 3);
              expect(quantity, 15000);
              calls++;
              return false;
            },
            onAdjustStock: (_, _) async =>
                throw StateError('Expected physical count'),
          ),
        ),
      ),
    );
    await tester.enterText(find.byType(TextField), '15000');
    await tester.pump();
    expect(calls, 0);
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(calls, 1);
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      '15000',
    );
    expect(
      find.text('Not saved. Check stock before retrying.'),
      findsOneWidget,
    );
    await tester.tap(find.text('Reset'));
    await tester.pump();
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      '20',
    );
  });

  testWidgets(
    'a live update cannot silently overwrite an edited physical count',
    (tester) async {
      var current = product;
      var calls = 0;
      Widget page() => MaterialApp(
        home: Scaffold(
          body: StockQuantityEditor(
            product: current,
            busy: false,
            onSetStock: (_, _) async {
              calls++;
              return true;
            },
            onAdjustStock: (_, _) async {
              calls++;
              return true;
            },
          ),
        ),
      );
      await tester.pumpWidget(page());
      await tester.enterText(find.byType(TextField), '500');
      current = product.copyWith(stockQuantity: 19, revision: 4);
      await tester.pumpWidget(page());
      expect(
        find.text('Stock changed. Reset to the latest count.'),
        findsOneWidget,
      );
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull,
      );
      expect(calls, 0);
      await tester.tap(find.text('Reset'));
      await tester.pump();
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        '19',
      );
    },
  );

  testWidgets('button drafts rebase on live stock and cannot go below zero', (
    tester,
  ) async {
    var current = product;
    int? savedDelta;
    Widget page() => MaterialApp(
      home: Scaffold(
        body: StockQuantityEditor(
          product: current,
          busy: false,
          onSetStock: (_, _) async => throw StateError('Expected delta'),
          onAdjustStock: (_, delta) async {
            savedDelta = delta;
            return true;
          },
        ),
      ),
    );
    await tester.pumpWidget(page());
    await tester.tap(find.byKey(const Key('admin-stock-increase-test-stock')));
    await tester.pump();
    current = product.copyWith(stockQuantity: 3, revision: 4);
    await tester.pumpWidget(page());
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      '4',
    );
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(savedDelta, 1);
    current = current.copyWith(stockQuantity: 0, revision: 5);
    await tester.pumpWidget(page());
    expect(
      tester
          .widget<IconButton>(
            find.byKey(const Key('admin-stock-decrease-test-stock')),
          )
          .onPressed,
      isNull,
    );
  });

  testWidgets('stock controls wrap on a narrow phone at large text size', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(2)),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: StockQuantityEditor(
                product: product,
                busy: false,
                onSetStock: (_, _) async => true,
                onAdjustStock: (_, _) async => true,
              ),
            ),
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
  });
}
