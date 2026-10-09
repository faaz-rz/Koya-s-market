import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/config/app_environment.dart';
import '../../../core/services/network_status.dart';
import '../../../core/utils/transaction_request.dart';
import '../../../core/widgets/koyas_button.dart';
import '../../auth/data/auth_repository.dart';
import '../../notifications/widgets/customer_order_alerts.dart';
import '../../store/data/supabase_store_repository.dart';
import '../../store/providers/store_provider.dart';
import '../models/checkout_models.dart';
import '../widgets/address_editor_form.dart';

final firstAddressSaverProvider =
    Provider<Future<CustomerAddress> Function(CustomerAddress)>(
      (ref) => AppEnvironment.hasSupabaseConfig
          ? SupabaseStoreRepository().addAddress
          : (address) async => address,
    );

class AddressSetupScreen extends ConsumerStatefulWidget {
  const AddressSetupScreen({super.key});
  @override
  ConsumerState<AddressSetupScreen> createState() => _AddressSetupScreenState();
}

class _AddressSetupScreenState extends ConsumerState<AddressSetupScreen> {
  bool _saving = false;
  bool _locating = false;
  final _form = GlobalKey<AddressEditorFormState>();
  String? _error;
  Future<void> _save(CustomerAddress address) async {
    if (_saving) return;
    final user = ref.read(storeProvider).profile?.id;
    if (user == null) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final saved = await ref.read(firstAddressSaverProvider)(
        address.copyWith(isDefault: true),
      );
      if (!mounted ||
          !ref.read(storeProvider).isAuthenticated ||
          ref.read(storeProvider).profile?.id != user) {
        return;
      }
      ref.read(storeProvider.notifier).addAddress(saved);
      context.go('/home');
    } catch (error) {
      if (mounted && ref.read(storeProvider).profile?.id == user) {
        setState(
          () => _error = connectionFailureMessage(
            error,
            transactionFailureMessage(
              error,
              'Your address could not be saved. Please try again.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _signOut() async {
    if (_saving) return;
    try {
      if (AppEnvironment.hasSupabaseConfig) await AuthRepository().signOut();
      if (mounted) ref.read(storeProvider.notifier).logout();
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = connectionFailureMessage(
            error,
            'Sign out could not finish. Please try again.',
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final textScale = MediaQuery.textScalerOf(context).scale(20) / 20;
    final compactActions =
        MediaQuery.sizeOf(context).width < 360 || textScale > 1.5;
    return PopScope(
      canPop: false,
      child: Scaffold(
        appBar: AppBar(
          automaticallyImplyLeading: false,
          toolbarHeight:
              kToolbarHeight + (textScale > 1 ? 20 * (textScale - 1) : 0),
          title: const Text(
            'Your address',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          actions: [
            if (compactActions)
              IconButton(
                tooltip: 'Sign out',
                onPressed: _saving ? null : _signOut,
                icon: const Icon(Icons.logout_rounded),
              )
            else
              TextButton(
                onPressed: _saving ? null : _signOut,
                child: const Text('Sign out'),
              ),
          ],
        ),
        body: SafeArea(
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 600),
              child: SingleChildScrollView(
                key: const Key('address-setup-scroll'),
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Icon(Icons.location_on_outlined, size: 44),
                    const SizedBox(height: 12),
                    Text(
                      'Where should we deliver?',
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Save your address to get started. You can choose home delivery or store pickup at checkout.',
                    ),
                    const SizedBox(height: 24),
                    AddressEditorForm(
                      key: _form,
                      showSaveButton: false,
                      onLocatingChanged: (busy) =>
                          setState(() => _locating = busy),
                      onSave: _save,
                      saving: _saving,
                      makeDefault: true,
                      saveLabel: 'Save address and continue',
                    ),
                    const SizedBox(height: 24),
                    Text(
                      'Order notifications',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const CustomerAlertSettings(),
                  ],
                ),
              ),
            ),
          ),
        ),
        bottomNavigationBar: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Semantics(
                      liveRegion: true,
                      child: Text(
                        _error!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ),
                  ),
                KoyasButton(
                  key: const Key('save-address'),
                  label: 'Save address and continue',
                  loading: _saving,
                  onPressed: _locating
                      ? null
                      : () => _form.currentState?.save(),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
