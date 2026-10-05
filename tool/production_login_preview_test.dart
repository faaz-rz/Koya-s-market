// Render the production email/OTP UI with mocked HTTP, without sending emails.
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../test/production_login_test.dart' show fixtureFor, requestCode;

void main() {
  for (final width in [320.0, 390.0]) {
    testWidgets('production email sign-in at ${width.toInt()}px', (
      tester,
    ) async {
      await tester.runAsync(() async {
        final font = FontLoader('Manrope')
          ..addFont(rootBundle.load('assets/fonts/Manrope-Variable.ttf'));
        final icons = FontLoader('MaterialIcons')
          ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
        await Future.wait([font.load(), icons.load()]);
      });
      final fixture = await fixtureFor(tester);
      await fixture.open(tester, width: width, scale: width == 320 ? 2 : 1);
      final app = tester.widget<UncontrolledProviderScope>(
        find.byType(UncontrolledProviderScope),
      );
      const capture = Key('production-login-capture');
      await tester.pumpWidget(RepaintBoundary(key: capture, child: app));
      await tester.pumpAndSettle();
      await _capture(tester, capture, 'email-${width.toInt()}');
      await requestCode(tester);
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      await _capture(tester, capture, 'otp-${width.toInt()}');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}

Future<void> _capture(WidgetTester tester, Key key, String name) async {
  await tester.runAsync(() async {
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(key),
    );
    final image = await boundary.toImage(pixelRatio: 2);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    final file = File('outputs/deployment/$name.png');
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  });
}
