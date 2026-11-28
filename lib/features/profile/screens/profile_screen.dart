import '../../notifications/widgets/customer_order_alerts.dart';
import '../../checkout/widgets/address_editor_dialog.dart';
import '../../cart/providers/cart_persistence.dart';
import '../../../core/services/network_status.dart';
import '../../../core/utils/transaction_request.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/config/app_environment.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_motion.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/koyas_surface.dart';
import '../../../core/widgets/appearance_selector.dart';
import '../../checkout/models/checkout_models.dart';
import '../models/customer_profile.dart';
import '../../store/data/supabase_store_repository.dart';
import '../../store/providers/store_provider.dart';
import '../../auth/data/auth_repository.dart';
import '../../orders/models/order.dart';
import '../widgets/delete_account_dialog.dart';

class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({this.addressesOnly = false, super.key});

  final bool addressesOnly;

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
    final profile = ref.read(storeProvider).profile;
    final edited = await showDialog<CustomerAddress>(
      context: context,
      animationStyle: AppMotion.dialogStyle(context),
      builder: (context) => AddressEditorDialog(
        address: current,
        initialName: profile?.name ?? '',
        initialPhone: profile?.phone ?? '',
      ),
    );
    if (edited == null ||
        !mounted ||
        ref.read(storeProvider).profile?.id != profile?.id) {
      return;
    }
    final repository = AppEnvironment.hasSupabaseConfig
        ? SupabaseStoreRepository()
        : null;
    try {
      final saved = repository != null
          ? current == null
                ? await repository.addAddress(edited)
                : await repository.updateAddress(edited)
          : edited;
      if (!mounted || ref.read(storeProvider).profile?.id != profile?.id) {
        return;
      }
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

  Future<void> _showSupport() => showDialog<void>(
    context: context,
    animationStyle: AppMotion.dialogStyle(context),
    builder: (context) => AlertDialog(
      icon: const Icon(Icons.support_agent_rounded),
      title: const Text('Help and support'),
      content: const Text(
        'For help with an order, call Koya Stores at +91 95029 26383. '
        'Have your order number handy.',
      ),
      actions: [
        TextButton(
          onPressed: () async {
            await Clipboard.setData(
              const ClipboardData(text: '+91 95029 26383'),
            );
            if (!context.mounted) return;
            Navigator.of(context).pop();
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Store number copied.')),
            );
          },
          child: const Text('Copy number'),
        ),
        FilledButton.icon(
          onPressed: () async {
            final uri = Uri(scheme: 'tel', path: '+919502926383');
            try {
              if (await launchUrl(uri, mode: LaunchMode.externalApplication)) {
                return;
              }
            } catch (_) {
              // Devices without a dialer can still copy the number.
            }
            if (!context.mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Could not open the phone app.')),
            );
          },
          icon: const Icon(Icons.call_outlined),
          label: const Text('Call store'),
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final store = ref.watch(storeProvider);
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    final addressesOnly = widget.addressesOnly;
    return Scaffold(
      appBar: AppBar(
        centerTitle: false,
        automaticallyImplyLeading: addressesOnly,
        title: Text(addressesOnly ? 'Saved addresses' : 'Profile'),
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
            constraints: const BoxConstraints(maxWidth: 640),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: addressesOnly
                  ? [
                      FilledButton.icon(
                        key: const Key('profile-add-address'),
                        onPressed: _saveAddress,
                        icon: const Icon(Icons.add_location_alt_outlined),
                        label: const Text('Add an address'),
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      if (store.addresses.isEmpty)
                        const KoyasSurface(
                          child: Text(
                            'Add a delivery address to use it at checkout.',
                          ),
                        )
                      else
                        for (final address in store.addresses)
                          Padding(
                            padding: const EdgeInsets.only(
                              bottom: AppSpacing.sm,
                            ),
                            child: _SavedAddress(
                              address: address,
                              issue: store.deliveryAddressIssue(address),
                              onEdit: () => _saveAddress(address),
                              onMakeDefault: () => _setDefault(address),
                              onDelete: () => _deleteAddress(address),
                            ),
                          ),
                    ]
                  : [
                      _AccountHeader(
                        profile: store.profile,
                        onEdit: _editProfile,
                      ),
                      const SizedBox(height: AppSpacing.md),
                      LayoutBuilder(
                        builder: (context, constraints) {
                          final narrow =
                              constraints.maxWidth < 280 ||
                              MediaQuery.textScalerOf(context).scale(14) > 19;
                          final orders = _ProfileShortcut(
                            key: const Key('profile-your-orders'),
                            icon: Icons.receipt_long_outlined,
                            title: 'Your orders',
                            onTap: () => context.go('/orders'),
                          );
                          final addresses = _ProfileShortcut(
                            key: const Key('profile-saved-addresses'),
                            icon: Icons.location_on_outlined,
                            title: 'Saved addresses',
                            onTap: () => context.push('/profile/addresses'),
                          );
                          return narrow
                              ? Column(
                                  children: [
                                    orders,
                                    const SizedBox(height: AppSpacing.sm),
                                    addresses,
                                  ],
                                )
                              : IntrinsicHeight(
                                  child: Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      Expanded(child: orders),
                                      const SizedBox(width: AppSpacing.sm),
                                      Expanded(child: addresses),
                                    ],
                                  ),
                                );
                        },
                      ),
                      const _ProfileSection(
                        title: 'Preferences',
                        children: [
                          AppearanceSetting(),
                          Divider(height: 1),
                          OrderAlertSettingsTile(),
                        ],
                      ),
                      _ProfileSection(
                        title: 'Help and privacy',
                        children: [
                          ListTile(
                            leading: const Icon(Icons.support_agent_rounded),
                            title: const Text('Help and support'),
                            subtitle: const Text('Contact Koya Stores'),
                            trailing: const Icon(Icons.chevron_right_rounded),
                            onTap: _showSupport,
                          ),
                          const Divider(height: 1),
                          ListTile(
                            key: const Key('profile-privacy-policy'),
                            leading: const Icon(Icons.privacy_tip_outlined),
                            title: const Text('Privacy policy'),
                            trailing: const Icon(
                              Icons.open_in_new_rounded,
                              size: 18,
                            ),
                            onTap: () => _openExternal(
                              AppEnvironment.privacyPolicyUrl,
                              'Privacy policy',
                            ),
                          ),
                        ],
                      ),
                      _ProfileSection(
                        title: 'Account',
                        children: [
                          ListTile(
                            leading: const Icon(Icons.logout_rounded),
                            title: const Text('Log out'),
                            trailing: const Icon(Icons.chevron_right_rounded),
                            onTap: _logout,
                          ),
                          const Divider(height: 1),
                          ListTile(
                            key: const Key('profile-delete-account'),
                            enabled: !_deletingAccount,
                            leading: Icon(
                              Icons.delete_outline_rounded,
                              color: colors.error,
                            ),
                            title: Text(
                              'Delete account',
                              style: theme.textTheme.titleSmall?.copyWith(
                                color: colors.error,
                              ),
                            ),
                            trailing: const Icon(Icons.chevron_right_rounded),
                            onTap: _deletingAccount ? null : _deleteAccount,
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.xxl),
                      const Center(child: _AppVersionLabel()),
                    ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AccountHeader extends StatelessWidget {
  const _AccountHeader({required this.profile, required this.onEdit});

  final CustomerProfile? profile;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final name = profile?.name.trim() ?? '';
    final initials = name
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .take(2)
        .map((part) => part.characters.first.toUpperCase())
        .join();
    final text = Theme.of(context).textTheme;
    final colors = AppColors.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.brand700,
        borderRadius: BorderRadius.circular(AppRadii.xxl),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                ExcludeSemantics(
                  child: Container(
                    width: 52,
                    height: 52,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: colors.onBrand.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(AppRadii.lg),
                    ),
                    child: initials.isEmpty
                        ? Icon(
                            Icons.person_outline_rounded,
                            color: colors.onBrand,
                          )
                        : Padding(
                            padding: const EdgeInsets.all(AppSpacing.sm),
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text(
                                initials,
                                style: text.titleLarge?.copyWith(
                                  color: colors.onBrand,
                                ),
                              ),
                            ),
                          ),
                  ),
                ),
                if (profile != null) ...[
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Align(
                      alignment: AlignmentDirectional.centerEnd,
                      child: Tooltip(
                        message: 'Edit profile',
                        child: OutlinedButton.icon(
                          onPressed: onEdit,
                          icon: const Icon(Icons.edit_outlined, size: 16),
                          label: const Text('Edit'),
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size(48, 48),
                            foregroundColor: colors.onBrand,
                            side: BorderSide(
                              color: colors.onBrand.withValues(alpha: 0.42),
                            ),
                            padding: const EdgeInsets.symmetric(
                              horizontal: AppSpacing.md,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              name.isEmpty ? 'Your account' : name,
              style: text.headlineMedium?.copyWith(color: colors.onBrand),
            ),
            for (final detail in [profile?.email, profile?.phone])
              if (detail != null && detail.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.xs),
                  child: Text(
                    detail,
                    style: text.bodyMedium?.copyWith(
                      color: colors.onBrand.withValues(alpha: 0.9),
                    ),
                  ),
                ),
          ],
        ),
      ),
    );
  }
}

class _ProfileShortcut extends StatelessWidget {
  const _ProfileShortcut({
    required this.icon,
    required this.title,
    required this.onTap,
    super.key,
  });

  final IconData icon;
  final String title;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return KoyasSurface(
      onTap: onTap,
      radius: AppRadii.lg,
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: colors.brandSoft,
              borderRadius: BorderRadius.circular(AppRadii.md),
            ),
            child: Icon(icon, color: colors.brand700, size: 20),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(title, style: Theme.of(context).textTheme.labelLarge),
          ),
          Icon(
            Icons.chevron_right_rounded,
            color: colors.inkSecondary,
            size: 18,
          ),
        ],
      ),
    );
  }
}

class _ProfileSection extends StatelessWidget {
  const _ProfileSection({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.xxl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            title,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: AppSpacing.sm),
          KoyasSurface(
            radius: AppRadii.lg,
            padding: EdgeInsets.zero,
            child: ListTileTheme(
              iconColor: colors.brand700,
              child: Column(children: children),
            ),
          ),
        ],
      ),
    );
  }
}

enum _AddressAction { edit, makeDefault, delete }

class _SavedAddress extends StatelessWidget {
  const _SavedAddress({
    required this.address,
    required this.issue,
    required this.onEdit,
    required this.onMakeDefault,
    required this.onDelete,
  });

  final CustomerAddress address;
  final String? issue;
  final VoidCallback onEdit;
  final VoidCallback onMakeDefault;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final text = Theme.of(context).textTheme;
    return KoyasSurface(
      radius: AppRadii.lg,
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.xs,
        AppSpacing.xs,
        AppSpacing.md,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.md),
            child: Icon(Icons.location_on_outlined, color: colors.brand700),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: AppSpacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: AppSpacing.sm,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(address.label, style: text.titleMedium),
                      if (address.isDefault)
                        Text(
                          'Default',
                          style: text.labelMedium?.copyWith(
                            color: colors.brand700,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(address.formatted, style: text.bodyMedium),
                  if (issue != null) ...[
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      issue!,
                      style: text.bodySmall?.copyWith(color: colors.error),
                    ),
                  ],
                ],
              ),
            ),
          ),
          PopupMenuButton<_AddressAction>(
            tooltip: 'Address options',
            onSelected: (action) => switch (action) {
              _AddressAction.edit => onEdit(),
              _AddressAction.makeDefault => onMakeDefault(),
              _AddressAction.delete => onDelete(),
            },
            itemBuilder: (_) => [
              const PopupMenuItem(
                value: _AddressAction.edit,
                child: Text('Edit'),
              ),
              if (!address.isDefault)
                const PopupMenuItem(
                  value: _AddressAction.makeDefault,
                  child: Text('Make default'),
                ),
              const PopupMenuItem(
                value: _AddressAction.delete,
                child: Text('Delete'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _AppVersionLabel extends StatefulWidget {
  const _AppVersionLabel();

  @override
  State<_AppVersionLabel> createState() => _AppVersionLabelState();
}

class _AppVersionLabelState extends State<_AppVersionLabel> {
  late final Future<String> _version = PackageInfo.fromPlatform()
      .then((info) => info.version)
      .onError((_, _) => '');

  @override
  Widget build(BuildContext context) => FutureBuilder<String>(
    future: _version,
    builder: (context, snapshot) {
      final version = snapshot.data ?? '';
      return Text(
        version.isEmpty ? 'Koya Stores' : 'Koya Stores · Version $version',
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
          color: AppColors.of(context).inkTertiary,
        ),
      );
    },
  );
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
      scrollable: true,
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
