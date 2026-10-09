import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class ConfigurationErrorApp extends StatelessWidget {
  const ConfigurationErrorApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: ThemeMode.system,
      home: const Scaffold(
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
