import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_web_plugins/url_strategy.dart';

import 'admin/admin_app.dart';
import 'core/config/app_environment.dart';
import 'core/services/backend_bootstrap.dart';
import 'core/widgets/configuration_error_app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  usePathUrlStrategy();
  if (kReleaseMode &&
      !AppEnvironment.hasProductionCustomerConfig &&
      !AppEnvironment.allowAdminDemo) {
    runApp(const ConfigurationErrorApp());
    return;
  }
  // Staff sessions live only in the current tab. Refreshing or closing the
  // browser requires a fresh email OTP and authenticator code.
  await BackendBootstrap.initialize(persistAuthSession: false);
  runApp(const ProviderScope(child: KoyasAdminApp()));
}
