import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/config/app_environment.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/koyas_button.dart';
import '../../store/data/supabase_store_repository.dart';
import '../../store/providers/store_provider.dart';
import '../../notifications/services/push_notification_service.dart';

class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen> {
  String? _error;

  @override
  void initState() {
    super.initState();
    _route();
  }

  Future<void> _route() async {
    if (mounted) setState(() => _error = null);
    await Future<void>.delayed(const Duration(milliseconds: 700));
    if (!mounted) return;
    try {
      if (AppEnvironment.hasSupabaseConfig) {
        final user = Supabase.instance.client.auth.currentUser;
        if (user == null) {
          context.go('/login');
          return;
        }
        final bundle = await SupabaseStoreRepository().loadStore();
        ref.read(storeProvider.notifier).hydrateRemoteBundle(bundle);
        try {
          await PushNotificationService.instance.registerForCurrentUser();
        } catch (_) {
          // The storefront remains usable if notification setup fails.
        }
        if (mounted) context.go('/home');
        return;
      }
      final isAuthenticated = ref.read(storeProvider).isAuthenticated;
      context.go(isAuthenticated ? '/home' : '/login');
    } catch (_) {
      if (mounted) {
        setState(
          () => _error =
              'We could not connect to Koyas. Check your connection and try again.',
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.brand600,
      body: SafeArea(
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 104,
                height: 104,
                decoration: const BoxDecoration(
                  color: AppColors.surface,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.eco_rounded,
                  color: AppColors.brand600,
                  size: 58,
                ),
              ),
              const SizedBox(height: AppSpacing.xxl),
              Text(
                'Koyas',
                style: Theme.of(context).textTheme.displayLarge?.copyWith(
                  color: AppColors.surface,
                  fontSize: 40,
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: AppSpacing.xxl),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 320),
                  child: Text(
                    _error!,
                    textAlign: TextAlign.center,
                    style: Theme.of(
                      context,
                    ).textTheme.bodyMedium?.copyWith(color: AppColors.surface),
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
                KoyasButton(
                  label: 'Try again',
                  expand: false,
                  onPressed: _route,
                ),
              ],
              const SizedBox(height: AppSpacing.sm),
              Text(
                'Fresh. Local. Convenient.',
                style: Theme.of(
                  context,
                ).textTheme.bodyLarge?.copyWith(color: AppColors.brandSoft),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
