import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app.dart';
import 'core/config/app_environment.dart';
import 'core/services/backend_bootstrap.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (kReleaseMode && !AppEnvironment.hasProductionCustomerConfig) {
    runApp(const ConfigurationErrorApp());
    return;
  }
  await BackendBootstrap.initialize();
  runApp(const ProviderScope(child: KoyasApp()));
}

class ConfigurationErrorApp extends StatelessWidget {
  const ConfigurationErrorApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: EdgeInsets.all(32),
              child: Text(
                'Koya Stores is temporarily unavailable. Please install the '
                'latest official version or try again later.',
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
