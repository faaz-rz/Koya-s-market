import '../../core/services/network_status.dart';
import '../../core/widgets/four_dot_loader.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/config/app_environment.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/widgets/koyas_button.dart';
import '../../core/widgets/koyas_logo.dart';
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
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _route();
  }

  Future<void> _route() async {
    if (!mounted || _loading) return;
    setState(() {
      _error = null;
      _loading = true;
    });
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
      final bundle = await SupabaseStoreRepository().loadStore();
      if (!mounted || auth.currentUser?.id != bundle.profile.id) {
        return;
      }
      if (!bundle.isAdmin) {
        await auth.signOut();
        if (mounted) context.go('/login?reason=unauthorized');
        return;
      }
      ref.read(storeProvider.notifier).hydrateRemoteBundle(bundle);
      if (mounted) context.go('/dashboard');
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = connectionFailureMessage(
            error,
            'The staff dashboard could not connect. Please try again.',
          );
        });
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.of(context).brand500,
      body: SafeArea(
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 560),
                  child: const AspectRatio(
                    aspectRatio: 2,
                    child: Image(
                      image: AssetImage(KoyasLogo.fullAsset),
                      fit: BoxFit.cover,
                      filterQuality: FilterQuality.high,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              Text(
                'STAFF OPERATIONS',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: AppColors.of(context).heritageIvory,
                  letterSpacing: 3,
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: AppSpacing.xxl),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 340),
                  child: Text(
                    _error!,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: AppColors.of(context).surface,
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
                KoyasButton(
                  label: 'Try again',
                  expand: false,
                  onPressed: _route,
                ),
              ],
              if (_loading)
                Padding(
                  padding: EdgeInsets.all(AppSpacing.lg),
                  child: FourDotLoader(color: AppColors.of(context).surface),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
