import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:koyas_supermarket/core/services/network_status.dart';
import 'package:koyas_supermarket/core/widgets/four_dot_loader.dart';
import 'package:koyas_supermarket/core/widgets/koyas_button.dart';
import 'package:koyas_supermarket/core/widgets/network_status_banner.dart';

void main() {
  test(
    'failed network requests report offline and any HTTP response restores reachability',
    () async {
      var fail = true;
      final status = NetworkStatus();
      final client = NetworkAwareClient(
        MockClient((_) async {
          if (fail) throw http.ClientException('Failed host lookup');
          return http.Response('unavailable', 503);
        }),
        status: status,
      );
      addTearDown(client.close);
      addTearDown(status.dispose);
      await expectLater(
        client.get(Uri.parse('https://store.test')),
        throwsA(isA<NoInternetException>()),
      );
      expect(status.value, true);
      fail = false;
      expect(
        (await client.get(Uri.parse('https://store.test'))).statusCode,
        503,
      );
      expect(status.value, false);
    },
  );
  test(
    'an older failed request cannot overwrite a newer successful connection',
    () async {
      final old = Completer<http.Response>(), reached = Completer<void>();
      var calls = 0;
      final status = NetworkStatus();
      final client = NetworkAwareClient(
        MockClient((_) async {
          if (++calls == 1) {
            reached.complete();
            return old.future;
          }
          return http.Response('ok', 200);
        }),
        status: status,
      );
      addTearDown(client.close);
      addTearDown(status.dispose);
      final first = client.get(Uri.parse('https://store.test'));
      final rejected = expectLater(first, throwsA(isA<NoInternetException>()));
      await reached.future;
      await client.get(Uri.parse('https://store.test'));
      old.completeError(http.ClientException('connection dropped'));
      await rejected;
      expect(status.value, false);
    },
  );
  test(
    'a slow server has a bounded wait and is not falsely called offline',
    () async {
      final pending = Completer<http.Response>();
      final status = NetworkStatus();
      final client = NetworkAwareClient(
        MockClient((_) => pending.future),
        status: status,
        timeout: const Duration(milliseconds: 5),
      );
      addTearDown(client.close);
      addTearDown(status.dispose);
      await expectLater(
        client.get(Uri.parse('https://store.test')),
        throwsA(isA<TimeoutException>()),
      );
      expect(status.value, false);
      pending.complete(http.Response('ok', 200));
    },
  );
  testWidgets(
    'offline notice is visible, accessible, and disappears after recovery',
    (tester) async {
      NetworkStatus.instance.value = false;
      addTearDown(() => NetworkStatus.instance.value = false);
      await tester.pumpWidget(
        const MaterialApp(
          home: NetworkStatusBanner(child: Scaffold(body: Text('Saved cart'))),
        ),
      );
      NetworkStatus.instance.value = true;
      await tester.pump();
      expect(find.text(noInternetMessage), findsOneWidget);
      expect(find.text('Saved cart'), findsOneWidget);
      NetworkStatus.instance.value = false;
      await tester.pump();
      expect(find.text(noInternetMessage), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'loading uses four dots, disables resubmission and preserves button geometry',
    (tester) async {
      Widget button(bool loading) => MaterialApp(
        home: Scaffold(
          body: Center(
            child: KoyasButton(
              label: 'Send email code',
              loading: loading,
              expand: false,
              onPressed: () {},
            ),
          ),
        ),
      );
      await tester.pumpWidget(button(false));
      final bounds = tester.getSize(find.byType(FilledButton));
      await tester.pumpWidget(button(true));
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.byType(FourDotLoader), findsOneWidget);
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull,
      );
      expect(tester.getSize(find.byType(FilledButton)), bounds);
      expect(tester.binding.hasScheduledFrame, true);
      await tester.pumpWidget(button(false));
      await tester.pumpAndSettle();
    },
  );
  testWidgets('reduced-motion loading stays visible without rotating frames', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: const Center(child: FourDotLoader()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(FourDotLoader), findsOneWidget);
    expect(tester.binding.hasScheduledFrame, false);
    expect(tester.takeException(), isNull);
  });
}
