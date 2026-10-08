// Operator-only QA entry point. Never used by customer or staff builds.
// Generates an emulator token; no Supabase account, order or registration.
import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:koyas_supermarket/features/notifications/services/push_gateway.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await FirebasePushGateway.initialize();
  final directory = await getApplicationSupportDirectory();
  await directory.create(recursive: true);
  final tokenFile = File('${directory.path}/qa-fcm-token');
  final done = File('${directory.path}/qa-delivery-done');
  final cleaned = File('${directory.path}/qa-delivery-cleaned');
  final gateway = FirebasePushGateway();
  if (await done.exists()) {
    await gateway.deleteToken();
    if (await tokenFile.exists()) await tokenFile.delete();
    await cleaned.writeAsString('cleaned');
  } else {
    if (await cleaned.exists()) await cleaned.delete();
    final token = await gateway.token();
    if (token == null) throw StateError('QA token unavailable');
    await tokenFile.writeAsString(token);
  }
  runApp(
    const MaterialApp(
      home: Scaffold(
        body: Center(child: Text('Koya Stores notification delivery QA')),
      ),
    ),
  );
  Timer.periodic(const Duration(seconds: 1), (timer) async {
    if (await done.exists() && !await cleaned.exists()) {
      timer.cancel();
      await gateway.deleteToken();
      if (await tokenFile.exists()) await tokenFile.delete();
      await cleaned.writeAsString('cleaned');
    }
  });
}
