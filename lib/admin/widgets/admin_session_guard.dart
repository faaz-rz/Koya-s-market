import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/config/app_environment.dart';
import '../../features/auth/data/auth_repository.dart';
import '../../features/store/providers/store_provider.dart';

class AdminSessionGuard extends ConsumerStatefulWidget {
  const AdminSessionGuard({
    required this.child,
    this.authRepository,
    super.key,
  });

  final Widget child;
  final AuthRepository? authRepository;

  @override
  ConsumerState<AdminSessionGuard> createState() => _AdminSessionGuardState();
}

class _AdminSessionGuardState extends ConsumerState<AdminSessionGuard>
    with WidgetsBindingObserver {
  Timer? _validationTimer;
  StreamSubscription<AuthState>? _authSubscription;
  bool _locking = false;
  bool _validating = false;
  bool get _hasBackend =>
      widget.authRepository != null || AppEnvironment.hasSupabaseConfig;
  AuthRepository get _auth => widget.authRepository ?? AuthRepository();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    if (_hasBackend) {
      if (AppEnvironment.hasSupabaseConfig) {
        _authSubscription = Supabase.instance.client.auth.onAuthStateChange
            .listen((state) {
              if (state.session == null) {
                unawaited(_lock('expired'));
              } else {
                unawaited(_validateAuthorization());
              }
            });
      }
      _validationTimer = Timer.periodic(
        const Duration(minutes: 5),
        (_) => unawaited(_validateAuthorization()),
      );
      unawaited(_validateAuthorization());
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      if (_hasBackend) {
        unawaited(_validateAuthorization());
      }
    }
  }

  Future<void> _validateAuthorization() async {
    if (_locking || _validating || !mounted) return;
    _validating = true;
    try {
      final auth = _auth;
      if (auth.currentUser == null || !await auth.isApprovedAdmin()) {
        await _lock('unauthorized');
      }
    } catch (_) {
      // A temporary network failure should not destroy the current session.
      // Server-side RLS still blocks every privileged request independently.
    } finally {
      _validating = false;
    }
  }

  Future<void> _lock(String reason) async {
    if (_locking || !mounted) return;
    _locking = true;
    _validationTimer?.cancel();
    final shouldSignOut = _hasBackend && _auth.currentUser != null;
    // Remove sensitive store and order data from the rendered app immediately;
    // remote sign-out may still be waiting on a slow or unavailable network.
    ref.read(storeProvider.notifier).logout();
    if (mounted) context.go('/login?reason=$reason');
    try {
      if (shouldSignOut) {
        await _auth.signOut();
      }
    } catch (_) {
      // Local state was already cleared even if remote sign-out cannot complete.
    }
  }

  @override
  void dispose() {
    _validationTimer?.cancel();
    _authSubscription?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return KeyedSubtree(
      key: const Key('admin-session-guard'),
      child: widget.child,
    );
  }
}
