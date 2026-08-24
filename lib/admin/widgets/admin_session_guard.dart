import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/config/app_environment.dart';
import '../../features/auth/data/auth_repository.dart';
import '../../features/store/providers/store_provider.dart';

class AdminSessionGuard extends ConsumerStatefulWidget {
  const AdminSessionGuard({required this.child, this.idleTimeout, super.key});

  final Widget child;
  final Duration? idleTimeout;

  @override
  ConsumerState<AdminSessionGuard> createState() => _AdminSessionGuardState();
}

class _AdminSessionGuardState extends ConsumerState<AdminSessionGuard>
    with WidgetsBindingObserver {
  Timer? _idleTimer;
  Timer? _validationTimer;
  StreamSubscription<AuthState>? _authSubscription;
  bool _locking = false;
  bool _validating = false;

  Duration get _idleTimeout =>
      widget.idleTimeout ?? AppEnvironment.adminIdleTimeout;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    HardwareKeyboard.instance.addHandler(_handleKeyEvent);
    _resetIdleTimer();

    if (AppEnvironment.hasSupabaseConfig) {
      _authSubscription = Supabase.instance.client.auth.onAuthStateChange
          .listen((state) {
            if (state.session == null) {
              unawaited(_lock('expired'));
            } else {
              unawaited(_validateAuthorization());
            }
          });
      _validationTimer = Timer.periodic(
        const Duration(minutes: 5),
        (_) => unawaited(_validateAuthorization()),
      );
      unawaited(_validateAuthorization());
    }
  }

  @override
  void didUpdateWidget(covariant AdminSessionGuard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.idleTimeout != widget.idleTimeout) _resetIdleTimer();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _recordActivity();
      if (AppEnvironment.hasSupabaseConfig) {
        unawaited(_validateAuthorization());
      }
    }
  }

  bool _handleKeyEvent(KeyEvent event) {
    if (event is KeyDownEvent) _recordActivity();
    return false;
  }

  void _recordActivity() {
    if (!_locking) _resetIdleTimer();
  }

  void _resetIdleTimer() {
    _idleTimer?.cancel();
    _idleTimer = Timer(_idleTimeout, () => unawaited(_lock('expired')));
  }

  Future<void> _validateAuthorization() async {
    if (_locking || _validating || !mounted) return;
    _validating = true;
    try {
      final auth = AuthRepository();
      if (auth.currentUser == null ||
          !auth.hasAal2Session ||
          !await auth.isApprovedAdmin()) {
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
    _idleTimer?.cancel();
    _validationTimer?.cancel();
    final shouldSignOut =
        AppEnvironment.hasSupabaseConfig &&
        AuthRepository().currentUser != null;
    // Remove sensitive store and order data from the rendered app immediately;
    // remote sign-out may still be waiting on a slow or unavailable network.
    ref.read(storeProvider.notifier).logout();
    if (mounted) context.go('/login?reason=$reason');
    try {
      if (shouldSignOut) {
        await AuthRepository().signOut();
      }
    } catch (_) {
      // Local state was already cleared even if remote sign-out cannot complete.
    }
  }

  @override
  void dispose() {
    _idleTimer?.cancel();
    _validationTimer?.cancel();
    _authSubscription?.cancel();
    HardwareKeyboard.instance.removeHandler(_handleKeyEvent);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      key: const Key('admin-session-guard'),
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => _recordActivity(),
      child: widget.child,
    );
  }
}
