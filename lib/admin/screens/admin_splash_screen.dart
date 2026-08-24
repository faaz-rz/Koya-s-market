import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/config/app_environment.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/widgets/koyas_button.dart';
import '../../features/auth/data/auth_repository.dart';
import '../../features/store/data/supabase_store_repository.dart';
import '../../features/store/providers/store_provider.dart';

class AdminSplashScreen extends ConsumerStatefulWidget {
  const AdminSplashScreen({super.key});

  @override
  ConsumerState<AdminSplashScreen> createState() => _AdminSplashScreenState();
}

class _AdminSplashScreenState extends ConsumerState<AdminSplashScreen> {
  String? _error;

  @override
  void initState() {
    super.initState();
    _route();
  }

  Future<void> _route() async {
    if (mounted) setState(() => _error = null);
    await Future<void>.delayed(const Duration(milliseconds: 450));
    if (!mounted) return;
    try {
      if (!AppEnvironment.hasSupabaseConfig) {
        context.go('/login');
        return;
      }
      if (Supabase.instance.client.auth.currentUser == null) {
        context.go('/login');
        return;
      }
      final auth = AuthRepository();
      if (!await auth.isApprovedAdmin()) {
        await auth.signOut();
        if (mounted) context.go('/login?reason=unauthorized');
        return;
      }
      if (!auth.hasAal2Session) {
        if (mounted) context.go('/login?reason=mfa');
        return;
      }
      final bundle = await SupabaseStoreRepository().loadStore();
      if (!bundle.isAdmin) {
        await auth.signOut();
        if (mounted) context.go('/login?reason=unauthorized');
        return;
      }
      ref.read(storeProvider.notifier).hydrateRemoteBundle(bundle);
      if (mounted) context.go('/dashboard');
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = 'The staff dashboard could not connect. Please try again.';
        });
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
                width: 96,
                height: 96,
                decoration: const BoxDecoration(
                  color: AppColors.surface,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.admin_panel_settings_rounded,
                  color: AppColors.brand600,
                  size: 52,
                ),
              ),
              const SizedBox(height: AppSpacing.xxl),
              Text(
                'Koyas Admin',
                style: Theme.of(context).textTheme.displayLarge?.copyWith(
                  color: AppColors.surface,
                  fontSize: 40,
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                'Store operations',
                style: Theme.of(
                  context,
                ).textTheme.bodyLarge?.copyWith(color: AppColors.brandSoft),
              ),
              if (_error != null) ...[
                const SizedBox(height: AppSpacing.xxl),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 340),
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
            ],
          ),
        ),
      ),
    );
  }
}
