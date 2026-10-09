import '../../../core/services/network_status.dart';
import '../../../core/widgets/four_dot_loader.dart';
import 'package:flutter/material.dart';
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
        if (!mounted ||
            Supabase.instance.client.auth.currentUser?.id !=
                bundle.profile.id) {
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
              if (_error != null) ...[
                const SizedBox(height: AppSpacing.xxl),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 320),
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
              if (_routing)
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
