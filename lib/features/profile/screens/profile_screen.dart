import '../../notifications/widgets/customer_order_alerts.dart';
import '../../checkout/widgets/address_editor_dialog.dart';
import '../../cart/providers/cart_persistence.dart';
import '../../../core/services/network_status.dart';
import '../../../core/utils/transaction_request.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/config/app_environment.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_motion.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/koyas_surface.dart';
import '../../checkout/models/checkout_models.dart';
import '../models/customer_profile.dart';
import '../../store/data/supabase_store_repository.dart';
import '../../store/providers/store_provider.dart';
import '../../auth/data/auth_repository.dart';
import '../../orders/models/order.dart';
import '../widgets/delete_account_dialog.dart';

class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  bool _deletingAccount = false;

  Future<void> _refreshSavedCustomer(SupabaseStoreRepository repository) async {
    try {
      final bundle = await repository.loadStore();
      if (mounted && ref.read(storeProvider).profile?.id == bundle.profile.id) {
        ref.read(storeProvider.notifier).hydrateRemoteBundle(bundle);
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Change saved. Store details could not refresh; try refreshing before another edit.',
            ),
          ),
        );
      }
    }
  }

  void _customerFailure(Object error, String fallback) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          connectionFailureMessage(
            error,
            transactionFailureMessage(error, fallback),
          ),
        ),
      ),
    );
  }

  Future<void> _editProfile() async {
    final profile = ref.read(storeProvider).profile;
    if (profile == null) return;
    final updated = await showDialog<CustomerProfile>(
      context: context,
      animationStyle: AppMotion.dialogStyle(context),
      builder: (context) => _ProfileEditorDialog(profile: profile),
    );
    if (updated == null) return;
    final customerId = ref.read(storeProvider).profile?.id;
    final repository = AppEnvironment.hasSupabaseConfig
        ? SupabaseStoreRepository()
        : null;
    try {
      final saved = repository != null
          ? await repository.updateProfile(updated)
          : updated;
      if (!mounted || ref.read(storeProvider).profile?.id != customerId) return;
      ref.read(storeProvider.notifier).updateProfile(saved);
      if (repository != null) await _refreshSavedCustomer(repository);
    } catch (error) {
      _customerFailure(
        error,
        'Profile save was not confirmed. Check your profile before retrying.',
      );
    }
  }

  Future<void> _saveAddress([CustomerAddress? current]) async {
    final edited = await showDialog<CustomerAddress>(
      context: context,
      animationStyle: AppMotion.dialogStyle(context),
      builder: (context) => AddressEditorDialog(address: current),
    );
    if (edited == null) return;
    final customerId = ref.read(storeProvider).profile?.id;
    final repository = AppEnvironment.hasSupabaseConfig
        ? SupabaseStoreRepository()
        : null;
    try {
      final saved = repository != null
          ? current == null
                ? await repository.addAddress(edited)
                : await repository.updateAddress(edited)
          : edited;
      if (!mounted || ref.read(storeProvider).profile?.id != customerId) return;
      if (current == null) {
        ref.read(storeProvider.notifier).addAddress(saved);
      } else {
        ref.read(storeProvider.notifier).updateAddress(saved);
      }
      if (repository != null) await _refreshSavedCustomer(repository);
    } catch (error) {
      _customerFailure(
        error,
        'Address save was not confirmed. Check saved addresses before retrying.',
      );
    }
  }

  Future<void> _setDefault(CustomerAddress address) async {
    final customerId = ref.read(storeProvider).profile?.id;
    final repository = AppEnvironment.hasSupabaseConfig
        ? SupabaseStoreRepository()
        : null;
    try {
      final saved = repository == null
          ? address
          : await repository.setDefaultAddress(
              address.id,
              expectedRevision: address.revision,
            );
      if (!mounted || ref.read(storeProvider).profile?.id != customerId) return;
      ref.read(storeProvider.notifier).updateAddress(saved);
      ref.read(storeProvider.notifier).setDefaultAddress(address.id);
      if (repository != null) await _refreshSavedCustomer(repository);
    } catch (error) {
      _customerFailure(
        error,
        'Default address change was not confirmed. Check saved addresses before retrying.',
      );
    }
  }

  Future<void> _deleteAddress(CustomerAddress address) async {
    final confirmed = await showDialog<bool>(
      context: context,
      animationStyle: AppMotion.dialogStyle(context),
      builder: (context) => AlertDialog(
        title: const Text('Delete address?'),
        content: Text('Remove ${address.label} from your saved addresses?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Keep'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final customerId = ref.read(storeProvider).profile?.id;
    final repository = AppEnvironment.hasSupabaseConfig
        ? SupabaseStoreRepository()
        : null;
    try {
      if (repository != null) {
        await repository.deleteAddress(
          address.id,
          expectedRevision: address.revision,
        );
      }
      if (!mounted || ref.read(storeProvider).profile?.id != customerId) return;
      ref.read(storeProvider.notifier).deleteAddress(address.id);
      if (repository != null) await _refreshSavedCustomer(repository);
    } catch (error) {
      _customerFailure(
        error,
        'Address deletion was not confirmed. Check saved addresses before retrying.',
      );
    }
  }

  Future<void> _logout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      animationStyle: AppMotion.dialogStyle(context),
      builder: (context) => AlertDialog(
        title: const Text('Log out?'),
        content: const Text(
          'Your cart will be saved on this device and will return when you sign in to this account again.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Stay signed in'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Log out'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await ref.read(cartPersistenceProvider).restored;
      await ref.read(cartPersistenceProvider).flushed;
      if (AppEnvironment.hasSupabaseConfig) {
        await AuthRepository().signOut();
      }
      if (!mounted) return;
      ref.read(storeProvider.notifier).logout();
      if (mounted) context.go('/login');
    }
  }

  Future<void> _openExternal(String value, String label) async {
    final uri = Uri.tryParse(value);
    if (uri == null || !uri.isScheme('https')) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$label is not configured yet.')),
        );
      }
      return;
    }
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication) &&
        mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('$label could not be opened.')));
    }
  }

  Future<void> _deleteAccount() async {
    if (_deletingAccount) return;
    setState(() => _deletingAccount = true);
    try {
      final repository = AppEnvironment.hasSupabaseConfig
          ? AuthRepository()
          : null;
      void checkDemoAllowed() {
        if (!AppEnvironment.allowCustomerDemo) {
          throw const AccountDeletionException(
            'Account deletion is not configured. Use the web request page.',
          );
        }
        if (ref
            .read(storeProvider)
            .orders
            .any(
              (order) => !{
                OrderStatus.collected,
                OrderStatus.delivered,
                OrderStatus.cancelled,
                OrderStatus.rejected,
              }.contains(order.status),
            )) {
          throw const AccountDeletionException(
            'Complete or cancel your active orders before deleting your account.',
            code: 'active_orders',
          );
        }
      }

      final confirmed = await showDialog<bool>(
        context: context,
        animationStyle: AppMotion.dialogStyle(context),
        barrierDismissible: false,
        builder: (context) => DeleteAccountDialog(
          isDemo: AppEnvironment.allowCustomerDemo,
          requestCode: () async {
            if (repository != null) {
              return repository.requestAccountDeletionOtp();
            }
            checkDemoAllowed();
            return AccountDeletionChallenge(
              id: 'demo',
              expiresAt: DateTime.now().add(const Duration(minutes: 10)),
              emailHint: 'your demo email',
            );
          },
          confirmDeletion: (challenge, code) async {
            if (repository != null) {
              await repository.deleteAccount(
                challengeId: challenge.id,
                otp: code,
              );
              return;
            }
            checkDemoAllowed();
            if (code != '123456') {
              throw const AccountDeletionException(
                'Incorrect demo code. Use 123456.',
                code: 'invalid_code',
              );
            }
          },
          onOpenRequestPage: () => _openExternal(
            AppEnvironment.accountDeletionUrl,
            'Account deletion request page',
          ),
        ),
      );
      if (confirmed != true || !mounted) return;
      ref.read(storeProvider.notifier).logout();
      if (mounted) context.go('/login?reason=account-deleted');
    } on AccountDeletionException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.message)));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Your account could not be deleted. Please try again.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _deletingAccount = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = ref.watch(storeProvider);
    final profile = store.profile;
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: const Text('Profile'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.sm,
          AppSpacing.lg,
          AppSpacing.xxxl,
        ),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                KoyasSurface(
                  elevated: true,
                  child: Row(
                    children: [
                      Container(
                        width: 68,
                        height: 68,
                        decoration: const BoxDecoration(
                          color: AppColors.brandSoft,
                          shape: BoxShape.circle,
                        ),
                        child: Center(
                          child: Text(
                            _initials(profile?.name ?? 'Guest'),
                            style: Theme.of(context).textTheme.headlineSmall
                                ?.copyWith(color: AppColors.brand700),
                          ),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.lg),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              profile?.name ?? 'Guest shopper',
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                            const SizedBox(height: AppSpacing.xs),
                            Text(
                              profile?.email ?? 'Not signed in',
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(color: AppColors.inkSecondary),
                            ),
                            if (profile?.phone.isNotEmpty == true)
                              Text(
                                profile!.phone,
                                style: Theme.of(context).textTheme.bodySmall
                                    ?.copyWith(color: AppColors.inkSecondary),
                              ),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: 'Edit profile',
                        onPressed: _editProfile,
                        icon: const Icon(Icons.edit_outlined),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.xxxl),
                _SectionTitle(
                  title: 'Saved addresses',
                  actionLabel: 'Add',
                  onAction: _saveAddress,
                ),
                const SizedBox(height: AppSpacing.md),
                ...store.addresses.map(
                  (address) => Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.md),
                    child: KoyasSurface(
                      child: Row(
                        children: [
                          const Icon(
                            Icons.location_on_outlined,
                            color: AppColors.brand600,
                          ),
                          const SizedBox(width: AppSpacing.md),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Wrap(
                                  spacing: AppSpacing.sm,
                                  crossAxisAlignment: WrapCrossAlignment.center,
                                  children: [
                                    Text(
                                      address.label,
                                      style: Theme.of(
                                        context,
                                      ).textTheme.titleSmall,
                                    ),
                                    if (address.isDefault) ...[
                                      const Text('· Default'),
                                    ],
                                  ],
                                ),
                                const SizedBox(height: AppSpacing.xs),
                                Text(
                                  address.formatted,
                                  style: Theme.of(context).textTheme.bodySmall
                                      ?.copyWith(color: AppColors.inkSecondary),
                                ),
                              ],
                            ),
                          ),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                store.serviceablePincodes.contains(
                                      address.pincode,
                                    )
                                    ? Icons.check_circle_outline_rounded
                                    : Icons.error_outline_rounded,
                                color:
                                    store.serviceablePincodes.contains(
                                      address.pincode,
                                    )
                                    ? AppColors.success
                                    : AppColors.error,
                              ),
                              PopupMenuButton<String>(
                                tooltip: 'Address options',
                                onSelected: (value) {
                                  if (value == 'edit') _saveAddress(address);
                                  if (value == 'default') {
                                    _setDefault(address);
                                  }
                                  if (value == 'delete') {
                                    _deleteAddress(address);
                                  }
                                },
                                itemBuilder: (context) => [
                                  const PopupMenuItem(
                                    value: 'edit',
                                    child: Text('Edit'),
                                  ),
                                  if (!address.isDefault)
                                    const PopupMenuItem(
                                      value: 'default',
                                      child: Text('Make default'),
                                    ),
                                  const PopupMenuItem(
                                    value: 'delete',
                                    child: Text('Delete'),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.xl),
                Text(
                  'Preferences',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: AppSpacing.md),
                KoyasSurface(
                  padding: EdgeInsets.zero,
                  child: Column(
                    children: [
                      const Padding(
                        padding: EdgeInsets.all(16),
                        child: CustomerAlertSettings(),
                      ),
                      ListTile(
                        leading: const Icon(Icons.help_outline_rounded),
                        title: const Text('Help and support'),
                        trailing: const Icon(Icons.chevron_right_rounded),
                        onTap: () => ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                              'Call Koya Stores at +91 95029 26383.',
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.xxl),
                Text(
                  'Privacy and account',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: AppSpacing.md),
                KoyasSurface(
                  padding: EdgeInsets.zero,
                  child: Column(
                    children: [
                      ListTile(
                        key: const Key('profile-privacy-policy'),
                        leading: const Icon(Icons.privacy_tip_outlined),
                        title: const Text('Privacy policy'),
                        subtitle: const Text(
                          'How Koya Stores handles your personal information',
                        ),
                        trailing: const Icon(Icons.open_in_new_rounded),
                        onTap: () => _openExternal(
                          AppEnvironment.privacyPolicyUrl,
                          'Privacy policy',
                        ),
                      ),
                      const Divider(height: 1),
                      ListTile(
                        key: const Key('profile-delete-account'),
                        enabled: !_deletingAccount,
                        leading: const Icon(
                          Icons.delete_forever_outlined,
                          color: AppColors.error,
                        ),
                        title: const Text('Delete account'),
                        subtitle: const Text(
                          'Permanently remove your account and personal data',
                        ),
                        trailing: const Icon(Icons.chevron_right_rounded),
                        onTap: _deletingAccount ? null : _deleteAccount,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.xxl),
                OutlinedButton.icon(
                  onPressed: _logout,
                  icon: const Icon(Icons.logout_rounded),
                  label: const Text('Log out'),
                ),
                const SizedBox(height: AppSpacing.lg),
                Center(child: const _AppVersionLabel()),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _initials(String name) => name
      .trim()
      .split(RegExp(r'\s+'))
      .where((part) => part.isNotEmpty)
      .take(2)
      .map((part) => part[0].toUpperCase())
      .join();
}

class _AppVersionLabel extends StatefulWidget {
  const _AppVersionLabel();

  @override
  State<_AppVersionLabel> createState() => _AppVersionLabelState();
}

class _AppVersionLabelState extends State<_AppVersionLabel> {
  late final Future<String> _version = PackageInfo.fromPlatform()
      .then((info) => info.version)
      .onError((_, _) => '1.1.5');

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String>(
      future: _version,
      builder: (context, snapshot) => Text(
        'Koya Stores · Version ${snapshot.data ?? '…'}',
        style: Theme.of(
          context,
        ).textTheme.bodySmall?.copyWith(color: AppColors.inkTertiary),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({
    required this.title,
    required this.actionLabel,
    required this.onAction,
  });

  final String title;
  final String actionLabel;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(title, style: Theme.of(context).textTheme.titleLarge),
        ),
        TextButton(onPressed: onAction, child: Text(actionLabel)),
      ],
    );
  }
}

class _ProfileEditorDialog extends StatefulWidget {
  const _ProfileEditorDialog({required this.profile});

  final CustomerProfile profile;

  @override
  State<_ProfileEditorDialog> createState() => _ProfileEditorDialogState();
}

class _ProfileEditorDialogState extends State<_ProfileEditorDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name = TextEditingController(
    text: widget.profile.name,
  );
  late final TextEditingController _phone = TextEditingController(
    text: widget.profile.phone,
  );

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Edit profile'),
      content: SizedBox(
        width: 420,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _name,
                validator: (value) => value == null || value.trim().length < 2
                    ? 'Enter your name'
                    : null,
                decoration: const InputDecoration(labelText: 'Full name'),
              ),
              const SizedBox(height: AppSpacing.md),
              TextFormField(
                controller: _phone,
                keyboardType: TextInputType.phone,
                validator: (value) =>
                    value!.replaceAll(RegExp(r'\D'), '').length < 10
                    ? 'Enter a valid phone number'
                    : null,
                decoration: const InputDecoration(labelText: 'Phone'),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            if (!_formKey.currentState!.validate()) return;
            Navigator.of(context).pop(
              widget.profile.copyWith(
                name: _name.text.trim(),
                phone: _phone.text.trim(),
              ),
            );
          },
          child: const Text('Save'),
        ),
      ],
    );
  }
}
