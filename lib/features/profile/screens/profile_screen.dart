import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/config/app_environment.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/koyas_surface.dart';
import '../../checkout/models/checkout_models.dart';
import '../models/customer_profile.dart';
import '../../store/data/supabase_store_repository.dart';
import '../../store/providers/store_provider.dart';
import '../../auth/data/auth_repository.dart';

class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  bool _deletingAccount = false;

  Future<void> _editProfile() async {
    final profile = ref.read(storeProvider).profile;
    if (profile == null) return;
    final updated = await showDialog<CustomerProfile>(
      context: context,
      builder: (context) => _ProfileEditorDialog(profile: profile),
    );
    if (updated == null) return;
    try {
      final saved = AppEnvironment.hasSupabaseConfig
          ? await SupabaseStoreRepository().updateProfile(updated)
          : updated;
      ref.read(storeProvider.notifier).updateProfile(saved);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Profile could not be updated.')),
        );
      }
    }
  }

  Future<void> _saveAddress([CustomerAddress? current]) async {
    final edited = await showDialog<CustomerAddress>(
      context: context,
      builder: (context) => _AddressEditorDialog(address: current),
    );
    if (edited == null) return;
    try {
      final saved = AppEnvironment.hasSupabaseConfig
          ? current == null
                ? await SupabaseStoreRepository().addAddress(edited)
                : await SupabaseStoreRepository().updateAddress(edited)
          : edited;
      if (current == null) {
        ref.read(storeProvider.notifier).addAddress(saved);
      } else {
        ref.read(storeProvider.notifier).updateAddress(saved);
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Address could not be saved.')),
        );
      }
    }
  }

  Future<void> _setDefault(CustomerAddress address) async {
    try {
      if (AppEnvironment.hasSupabaseConfig) {
        await SupabaseStoreRepository().setDefaultAddress(address.id);
      }
      ref.read(storeProvider.notifier).setDefaultAddress(address.id);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Default address could not be changed.'),
          ),
        );
      }
    }
  }

  Future<void> _deleteAddress(CustomerAddress address) async {
    final confirmed = await showDialog<bool>(
      context: context,
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
    if (confirmed != true) return;
    try {
      if (AppEnvironment.hasSupabaseConfig) {
        await SupabaseStoreRepository().deleteAddress(address.id);
      }
      ref.read(storeProvider.notifier).deleteAddress(address.id);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Address could not be deleted.')),
        );
      }
    }
  }

  Future<void> _logout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Log out?'),
        content: const Text('Your cart on this device will be cleared.'),
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
      if (AppEnvironment.hasSupabaseConfig) {
        await AuthRepository().signOut();
      }
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
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => _DeleteAccountDialog(
        onOpenRequestPage: () => _openExternal(
          AppEnvironment.accountDeletionUrl,
          'Account deletion request page',
        ),
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _deletingAccount = true);
    try {
      if (AppEnvironment.hasSupabaseConfig) {
        await AuthRepository().deleteAccount();
      }
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
                                Row(
                                  children: [
                                    Text(
                                      address.label,
                                      style: Theme.of(
                                        context,
                                      ).textTheme.titleSmall,
                                    ),
                                    if (address.isDefault) ...[
                                      const SizedBox(width: AppSpacing.sm),
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
                        trailing: _deletingAccount
                            ? const SizedBox.square(
                                dimension: 22,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.chevron_right_rounded),
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

class _DeleteAccountDialog extends StatefulWidget {
  const _DeleteAccountDialog({required this.onOpenRequestPage});

  final VoidCallback onOpenRequestPage;

  @override
  State<_DeleteAccountDialog> createState() => _DeleteAccountDialogState();
}

class _DeleteAccountDialogState extends State<_DeleteAccountDialog> {
  final _confirmation = TextEditingController();

  @override
  void dispose() {
    _confirmation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final confirmed = _confirmation.text.trim().toUpperCase() == 'DELETE';
    return AlertDialog(
      title: const Text('Permanently delete account?'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Your sign-in, profile, saved addresses and notification tokens will be removed. Completed transaction records are retained only in anonymized form for accounting and legal obligations.',
            ),
            const SizedBox(height: AppSpacing.md),
            const Text(
              'Active pickup or delivery orders must be completed or cancelled first. This action cannot be undone.',
            ),
            const SizedBox(height: AppSpacing.lg),
            TextField(
              key: const Key('delete-account-confirmation'),
              controller: _confirmation,
              textCapitalization: TextCapitalization.characters,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                labelText: 'Type DELETE to confirm',
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            TextButton.icon(
              key: const Key('delete-account-request-page'),
              onPressed: widget.onOpenRequestPage,
              icon: const Icon(Icons.open_in_new_rounded),
              label: const Text('Use the web deletion request page'),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Keep account'),
        ),
        FilledButton(
          key: const Key('delete-account-final'),
          onPressed: confirmed ? () => Navigator.of(context).pop(true) : null,
          style: FilledButton.styleFrom(backgroundColor: AppColors.error),
          child: const Text('Delete permanently'),
        ),
      ],
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

class _AddressEditorDialog extends StatefulWidget {
  const _AddressEditorDialog({this.address});

  final CustomerAddress? address;

  @override
  State<_AddressEditorDialog> createState() => _AddressEditorDialogState();
}

class _AddressEditorDialogState extends State<_AddressEditorDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _label;
  late final TextEditingController _name;
  late final TextEditingController _phone;
  late final TextEditingController _line;
  late final TextEditingController _city;
  late final TextEditingController _pincode;
  late final TextEditingController _instructions;

  @override
  void initState() {
    super.initState();
    final address = widget.address;
    _label = TextEditingController(text: address?.label ?? 'Home');
    _name = TextEditingController(text: address?.recipientName ?? '');
    _phone = TextEditingController(text: address?.phone ?? '');
    _line = TextEditingController(text: address?.line1 ?? '');
    _city = TextEditingController(text: address?.city ?? 'Hyderabad');
    _pincode = TextEditingController(text: address?.pincode ?? '');
    _instructions = TextEditingController(text: address?.instructions ?? '');
  }

  @override
  void dispose() {
    _label.dispose();
    _name.dispose();
    _phone.dispose();
    _line.dispose();
    _city.dispose();
    _pincode.dispose();
    _instructions.dispose();
    super.dispose();
  }

  String? _required(String? value) =>
      value == null || value.trim().isEmpty ? 'This field is required' : null;

  void _save() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.of(context).pop(
      CustomerAddress(
        id:
            widget.address?.id ??
            'address-${DateTime.now().millisecondsSinceEpoch}',
        label: _label.text.trim(),
        recipientName: _name.text.trim(),
        phone: _phone.text.trim(),
        line1: _line.text.trim(),
        city: _city.text.trim(),
        pincode: _pincode.text.trim(),
        instructions: _instructions.text.trim(),
        isDefault: widget.address?.isDefault ?? false,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.address == null ? 'Add address' : 'Edit address'),
      content: SizedBox(
        width: 480,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: _label,
                  validator: _required,
                  decoration: const InputDecoration(labelText: 'Label'),
                ),
                const SizedBox(height: AppSpacing.md),
                TextFormField(
                  controller: _name,
                  validator: _required,
                  decoration: const InputDecoration(
                    labelText: 'Recipient name',
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                TextFormField(
                  controller: _phone,
                  validator: (value) {
                    if (_required(value) != null) return _required(value);
                    return value!.replaceAll(RegExp(r'\D'), '').length < 10
                        ? 'Enter a valid phone number'
                        : null;
                  },
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(labelText: 'Phone'),
                ),
                const SizedBox(height: AppSpacing.md),
                TextFormField(
                  controller: _line,
                  validator: _required,
                  decoration: const InputDecoration(labelText: 'Address'),
                ),
                const SizedBox(height: AppSpacing.md),
                TextFormField(
                  controller: _city,
                  validator: _required,
                  decoration: const InputDecoration(labelText: 'City'),
                ),
                const SizedBox(height: AppSpacing.md),
                TextFormField(
                  controller: _pincode,
                  maxLength: 6,
                  keyboardType: TextInputType.number,
                  validator: (value) =>
                      RegExp(r'^\d{6}$').hasMatch(value?.trim() ?? '')
                      ? null
                      : 'Enter a valid 6-digit PIN',
                  decoration: const InputDecoration(labelText: 'PIN code'),
                ),
                const SizedBox(height: AppSpacing.md),
                TextFormField(
                  controller: _instructions,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: 'Delivery instructions (optional)',
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _save, child: const Text('Save')),
      ],
    );
  }
}
