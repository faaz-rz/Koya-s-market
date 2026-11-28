import '../../../core/services/network_status.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/config/app_environment.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/koyas_button.dart';
import '../../../core/widgets/koyas_logo.dart';
import '../../store/data/supabase_store_repository.dart';
import '../../store/providers/store_provider.dart';

class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen> {
  String? _error;
  bool _routing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _route());
  }

  Future<void> _route() async {
    if (!mounted || _routing) return;
    setState(() {
      _error = null;
      _routing = true;
    });
    try {
      if (AppEnvironment.hasSupabaseConfig) {
        final user = Supabase.instance.client.auth.currentUser;
        if (user == null) {
          context.go('/login');
          return;
        }
        final bundle = await SupabaseStoreRepository().loadStore();
        if (!mounted) return;
        final currentId = Supabase.instance.client.auth.currentUser?.id;
        if (currentId == null) {
          context.go('/login');
          return;
        }
        if (currentId != bundle.profile.id) {
          setState(() => _error = 'Your sign-in changed. Please try again.');
          return;
        }
        ref.read(storeProvider.notifier).hydrateRemoteBundle(bundle);
        if (mounted) context.go('/home');
        return;
      }
      final isAuthenticated = ref.read(storeProvider).isAuthenticated;
      context.go(isAuthenticated ? '/home' : '/login');
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = connectionFailureMessage(
            error,
            'We could not connect to Koya Stores. Please try again.',
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _routing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final text = Theme.of(context).textTheme;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: colors.isDark
          ? SystemUiOverlayStyle.light
          : SystemUiOverlayStyle.dark,
      child: Scaffold(
        backgroundColor: colors.marketCream,
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(AppSpacing.xxl),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 320),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(AppRadii.xl),
                      child: Image.asset(
                        KoyasLogo.symbolAsset,
                        width: 72,
                        height: 72,
                        excludeFromSemantics: true,
                        cacheWidth: 216,
                        cacheHeight: 216,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xl),
                    Text(
                      'Koya Stores',
                      key: const Key('launch-store-name'),
                      textAlign: TextAlign.center,
                      style: text.headlineMedium?.copyWith(
                        color: colors.ink,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xxl),
                    if (_error case final error?) ...[
                      Semantics(
                        liveRegion: true,
                        child: Text(error, textAlign: TextAlign.center),
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      KoyasButton(
                        label: 'Try again',
                        expand: false,
                        onPressed: _route,
                      ),
                    ] else
                      SizedBox(
                        width: 72,
                        child: LinearProgressIndicator(
                          semanticsLabel: 'Opening Koya Stores',
                          minHeight: 4,
                          value: MediaQuery.disableAnimationsOf(context)
                              ? 0.5
                              : null,
                          borderRadius: BorderRadius.circular(AppRadii.full),
                          backgroundColor: colors.brandSoft,
                          color: colors.brand600,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
