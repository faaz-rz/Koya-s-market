// Optional visual QA: flutter test --no-pub tool/account_deletion_preview_test.dart
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koyas_supermarket/core/theme/app_theme.dart';
import 'package:koyas_supermarket/core/widgets/customer_backdrop.dart';
import 'package:koyas_supermarket/features/auth/data/auth_repository.dart';
import 'package:koyas_supermarket/features/profile/widgets/delete_account_dialog.dart';

void main() {
  for (final brightness in [Brightness.light, Brightness.dark]) {
    for (final width in [320.0, 390.0]) {
      testWidgets('render deletion OTP at ${width.toInt()}px', (tester) async {
        await tester.runAsync(() async {
          final font = FontLoader('Manrope')
            ..addFont(rootBundle.load('assets/fonts/Manrope-Variable.ttf'));
          final icons = FontLoader('MaterialIcons')
            ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
          await Future.wait([font.load(), icons.load()]);
        });
        tester.view.physicalSize = Size(width, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        const capture = Key('capture');
        final now = DateTime.utc(2026, 9, 23, 12);
        await tester.pumpWidget(
          MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: AppTheme.customer,
            darkTheme: AppTheme.customerDark,
            themeMode: brightness == Brightness.dark
                ? ThemeMode.dark
                : ThemeMode.light,
            builder: (context, child) => RepaintBoundary(
              key: capture,
              child: MediaQuery(
                data: MediaQuery.of(context).copyWith(
                  textScaler: TextScaler.linear(width == 320 ? 1.5 : 1),
                ),
                child: CustomerBackdrop(child: child!),
              ),
            ),
            home: Builder(
              builder: (context) => Scaffold(
                appBar: AppBar(title: const Text('Profile')),
                body: Center(
                  child: TextButton(
                    child: const Text('Delete account'),
                    onPressed: () => showDialog<bool>(
                      context: context,
                      barrierDismissible: false,
                      builder: (_) => DeleteAccountDialog(
                        now: () => now,
                        onOpenRequestPage: () {},
                        requestCode: () async => AccountDeletionChallenge(
                          id: 'preview',
                          expiresAt: now.add(const Duration(minutes: 10)),
                          emailHint: 'a***@example.test',
                        ),
                        confirmDeletion: (_, _) async {},
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Delete account'));
        await tester.pumpAndSettle();
        await tester.runAsync(() async {
          final boundary = tester.renderObject<RenderRepaintBoundary>(
            find.byKey(capture),
          );
          final image = await boundary.toImage(pixelRatio: 2);
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          final file = File(
            'outputs/visual-build21/dialogs/delete-account-initial-${width.toInt()}-${brightness.name}.png',
          );
          await file.parent.create(recursive: true);
          await file.writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
        await tester.enterText(
          find.byKey(const Key('delete-account-confirmation')),
          'DELETE',
        );
        await tester.pump();
        final send = find.byKey(const Key('delete-account-send-code'));
        await tester.ensureVisible(send);
        await tester.tap(send);
        await tester.pumpAndSettle();
        final otp = find.byKey(const Key('delete-account-otp'));
        await tester.ensureVisible(otp);
        await tester.enterText(otp, '123456');
        FocusManager.instance.primaryFocus?.unfocus();
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.runAsync(() async {
          final boundary = tester.renderObject<RenderRepaintBoundary>(
            find.byKey(capture),
          );
          final image = await boundary.toImage(pixelRatio: 2);
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          final file = File(
            'outputs/visual-build21/dialogs/delete-account-email-${width.toInt()}-${brightness.name}.png',
          );
          await file.parent.create(recursive: true);
          await file.writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
        await tester.tap(find.text('Keep account'));
        await tester.pumpAndSettle();
      });
    }
  }
}
