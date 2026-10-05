import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:koyas_supermarket/core/theme/app_theme.dart';
import 'package:koyas_supermarket/features/auth/data/auth_repository.dart';
import 'package:koyas_supermarket/features/profile/widgets/delete_account_dialog.dart';

import 'store_repository_sync_test.dart' show clientFor;

const challengeId = '12345678-1234-4123-8123-123456789012';
final epoch = DateTime.utc(2026, 9, 23, 12);
AccountDeletionChallenge challenge([DateTime? now]) => AccountDeletionChallenge(
  id: challengeId,
  expiresAt: (now ?? epoch).add(const Duration(minutes: 10)),
  emailHint: 'a***@example.test',
);
http.Response response(Object data, [int status = 200]) => http.Response(
  jsonEncode(data),
  status,
  headers: {'content-type': 'application/json'},
);

Future<void> openDialog(
  WidgetTester tester, {
  Future<AccountDeletionChallenge> Function()? request,
  Future<void> Function(AccountDeletionChallenge, String)? confirm,
  DateTime Function()? now,
  double scale = 1,
  double keyboard = 0,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: TextScaler.linear(scale),
          viewInsets: EdgeInsets.only(bottom: keyboard),
        ),
        child: child!,
      ),
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            child: const Text('Open'),
            onPressed: () => showDialog<bool>(
              context: context,
              barrierDismissible: false,
              builder: (_) => DeleteAccountDialog(
                requestCode: request ?? () async => challenge(),
                confirmDeletion: confirm ?? (_, _) async {},
                now: now ?? () => epoch,
                onOpenRequestPage: () {},
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();
}

Future<void> tap(WidgetTester tester, String key) async {
  final target = find.byKey(Key(key));
  await tester.ensureVisible(target);
  await tester.pump(const Duration(milliseconds: 300));
  await tester.tap(target);
  await tester.pump();
}

Future<void> requestCode(WidgetTester tester) async {
  await tester.enterText(
    find.byKey(const Key('delete-account-confirmation')),
    'DELETE',
  );
  await tester.pump();
  await tap(tester, 'delete-account-send-code');
  await tester.pumpAndSettle();
}

void main() {
  test(
    'both OTP actions fail safely against the old one-step deletion endpoint',
    () async {
      var legacyDeletions = 0;
      final client = await clientFor((request) async {
        final body = jsonDecode(request.body) as Map;
        // This reproduces the old deployed endpoint's entire confirmation gate.
        if (body['confirmation'] == 'DELETE') {
          legacyDeletions++;
          return response({'deleted': true});
        }
        return response({'error': 'Deletion confirmation is required'}, 400);
      });
      addTearDown(client.dispose);
      final repository = AuthRepository(client: client);
      await expectLater(
        repository.requestAccountDeletionOtp(),
        throwsA(isA<AccountDeletionException>()),
      );
      await expectLater(
        repository.deleteAccount(challengeId: challengeId, otp: '123456'),
        throwsA(isA<AccountDeletionException>()),
      );
      expect(legacyDeletions, 0);
      expect(client.auth.currentUser, isNotNull);
    },
  );

  test(
    'repository sends two explicit actions, never deletes while requesting a code',
    () async {
      final requests = <Map>[];
      final client = await clientFor((request) async {
        if (request.url.path == '/auth/v1/logout') return response({});
        expect(request.url.path, '/functions/v1/delete-account');
        final body = jsonDecode(request.body) as Map;
        requests.add(body);
        if (body['action'] == 'request_otp') {
          return response({
            'sent': true,
            'challenge_id': challengeId,
            'expires_at': epoch
                .add(const Duration(minutes: 10))
                .toIso8601String(),
            'email_hint': 'a***@example.test',
            'retry_after': 60,
          });
        }
        return response({'deleted': true});
      });
      addTearDown(client.dispose);
      final repo = AuthRepository(client: client);
      final code = await repo.requestAccountDeletionOtp();
      expect(repo.currentUser, isNotNull);
      expect(code.id, challengeId);
      await expectLater(
        repo.deleteAccount(challengeId: code.id, otp: '12'),
        throwsA(isA<AccountDeletionException>()),
      );
      expect(requests, hasLength(1));
      await repo.deleteAccount(challengeId: code.id, otp: '123456');
      expect(requests.last, {
        'confirmation': 'DELETE_WITH_OTP',
        'action': 'confirm_delete',
        'challenge_id': challengeId,
        'otp': '123456',
      });
      expect(repo.currentUser, isNull);
      expect(AuthRepository.takeAccountDeleted(client), isTrue);
      expect(AuthRepository.takeAccountDeleted(client), isFalse);
    },
  );

  test(
    'backend rejection preserves the session and exposes expiry/rate-limit instructions',
    () async {
      for (final code in [
        'invalid_code',
        'otp_expired',
        'attempts_exhausted',
        'active_orders',
        'rate_limited',
      ]) {
        final client = await clientFor(
          (_) async => response({
            'code': code,
            'retry_after': 60,
          }, code == 'rate_limited' ? 429 : 400),
        );
        try {
          await expectLater(
            AuthRepository(
              client: client,
            ).deleteAccount(challengeId: challengeId, otp: '123456'),
            throwsA(
              isA<AccountDeletionException>()
                  .having((e) => e.code, 'code', code)
                  .having(
                    (e) => e.retryAfter,
                    'retry',
                    const Duration(seconds: 60),
                  ),
            ),
          );
          expect(client.auth.currentUser, isNotNull);
          expect(AuthRepository.takeAccountDeleted(client), isFalse);
        } finally {
          await client.dispose();
        }
      }
    },
  );

  test(
    'a logout network failure cannot turn committed deletion into a failure',
    () async {
      final client = await clientFor(
        (request) async => request.url.path == '/auth/v1/logout'
            ? response({'msg': 'temporarily unavailable'}, 503)
            : response({'deleted': true}),
      );
      addTearDown(client.dispose);
      await AuthRepository(
        client: client,
      ).deleteAccount(challengeId: challengeId, otp: '123456');
      expect(client.auth.currentUser, isNull);
      expect(AuthRepository.takeAccountDeleted(client), isTrue);
    },
  );

  testWidgets(
    'typed confirmation alone cannot delete; invalid OTP stays open and valid OTP completes',
    (tester) async {
      var deletions = 0;
      await openDialog(
        tester,
        confirm: (proof, code) async {
          expect(proof.id, challengeId);
          deletions++;
          if (code != '123456') {
            throw const AccountDeletionException(
              'Wrong code',
              code: 'invalid_code',
            );
          }
        },
      );
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('delete-account-final')))
            .onPressed,
        isNull,
      );
      await requestCode(tester);
      expect(find.textContaining('a***@example.test'), findsOneWidget);
      expect(find.byKey(const Key('delete-account-demo-code')), findsNothing);
      await tester.enterText(
        find.byKey(const Key('delete-account-otp')),
        '000000',
      );
      await tester.pump();
      await tap(tester, 'delete-account-final');
      await tester.pumpAndSettle();
      expect(find.text('Wrong code'), findsOneWidget);
      expect(find.byType(DeleteAccountDialog), findsOneWidget);
      await tester.enterText(
        find.byKey(const Key('delete-account-otp')),
        '123456',
      );
      await tester.pump();
      await tap(tester, 'delete-account-final');
      await tester.pumpAndSettle();
      expect(deletions, 2);
      expect(find.byType(DeleteAccountDialog), findsNothing);
    },
  );

  testWidgets('sending and deleting block duplicate taps and back navigation', (
    tester,
  ) async {
    final sending = Completer<AccountDeletionChallenge>(),
        deleting = Completer<void>();
    var sends = 0, deletions = 0;
    await openDialog(
      tester,
      request: () {
        sends++;
        return sending.future;
      },
      confirm: (_, _) {
        deletions++;
        return deleting.future;
      },
    );
    await tester.enterText(
      find.byKey(const Key('delete-account-confirmation')),
      'DELETE',
    );
    await tester.pump();
    await tap(tester, 'delete-account-send-code');
    await tap(tester, 'delete-account-send-code');
    expect(sends, 1);
    await tester.binding.handlePopRoute();
    await tester.pump();
    expect(find.byType(DeleteAccountDialog), findsOneWidget);
    sending.complete(challenge());
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('delete-account-otp')),
      '123456',
    );
    await tester.pump();
    await tap(tester, 'delete-account-final');
    await tap(tester, 'delete-account-final');
    await tester.binding.handlePopRoute();
    await tester.pump();
    expect(deletions, 1);
    expect(find.byType(DeleteAccountDialog), findsOneWidget);
    deleting.complete();
    await tester.pumpAndSettle();
    expect(find.byType(DeleteAccountDialog), findsNothing);
  });

  testWidgets('expiry disables deletion and resend clears the previous code', (
    tester,
  ) async {
    var time = epoch, sends = 0;
    await openDialog(
      tester,
      now: () => time,
      request: () async {
        sends++;
        return challenge(time);
      },
    );
    await requestCode(tester);
    expect(
      tester
          .widget<OutlinedButton>(
            find.byKey(const Key('delete-account-send-code')),
          )
          .onPressed,
      isNull,
    );
    await tester.enterText(
      find.byKey(const Key('delete-account-otp')),
      '123456',
    );
    time = time.add(const Duration(minutes: 10));
    await tester.pump(const Duration(seconds: 1));
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('delete-account-final')))
          .onPressed,
      isNull,
    );
    expect(find.text('Code expired. Request a new code.'), findsOneWidget);
    await tap(tester, 'delete-account-send-code');
    await tester.pumpAndSettle();
    expect(sends, 2);
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('delete-account-otp')))
          .controller!
          .text,
      isEmpty,
    );
    await tester.tap(find.text('Keep account'));
    await tester.pumpAndSettle();
  });

  testWidgets(
    'exhausted attempts discard the challenge and respect server resend cooldown',
    (tester) async {
      var time = epoch;
      await openDialog(
        tester,
        now: () => time,
        confirm: (_, _) async {
          throw const AccountDeletionException(
            'Request a fresh code',
            code: 'attempts_exhausted',
            retryAfter: Duration(seconds: 120),
          );
        },
      );
      await requestCode(tester);
      await tester.enterText(
        find.byKey(const Key('delete-account-otp')),
        '123456',
      );
      await tester.pump();
      await tap(tester, 'delete-account-final');
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('delete-account-otp')), findsNothing);
      expect(
        tester
            .widget<OutlinedButton>(
              find.byKey(const Key('delete-account-send-code')),
            )
            .onPressed,
        isNull,
      );
      time = time.add(const Duration(seconds: 120));
      await tester.pump(const Duration(seconds: 1));
      expect(
        tester
            .widget<OutlinedButton>(
              find.byKey(const Key('delete-account-send-code')),
            )
            .onPressed,
        isNotNull,
      );
      await tester.tap(find.text('Keep account'));
      await tester.pumpAndSettle();
    },
  );

  for (final width in [320.0, 360.0, 390.0, 430.0]) {
    testWidgets(
      'OTP dialog fits ${width.toInt()}px phone with large text and keyboard',
      (tester) async {
        tester.view.physicalSize = Size(width, 800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await openDialog(tester, scale: 1.5, keyboard: 240);
        await tester.ensureVisible(
          find.byKey(const Key('delete-account-confirmation')),
        );
        await requestCode(tester);
        await tester.ensureVisible(find.byKey(const Key('delete-account-otp')));
        await tester.enterText(
          find.byKey(const Key('delete-account-otp')),
          '123456',
        );
        await tester.pump();
        expect(tester.takeException(), isNull);
        await tester.tap(find.text('Keep account'));
        await tester.pumpAndSettle();
      },
    );
  }
}
