import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../theme/appearance_provider.dart';
import '../theme/app_colors.dart';

String appearanceLabel(ThemeMode mode) => switch (mode) {
  ThemeMode.light => 'Light',
  ThemeMode.dark => 'Dark',
  ThemeMode.system => 'System',
};

IconData _icon(ThemeMode mode) => switch (mode) {
  ThemeMode.light => Icons.light_mode_outlined,
  ThemeMode.dark => Icons.dark_mode_outlined,
  ThemeMode.system => Icons.brightness_auto_outlined,
};

Future<void> showAppearanceSelector(BuildContext context) =>
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (_) => const _AppearanceChoices(),
    );

class AppearanceSetting extends ConsumerWidget {
  const AppearanceSetting({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(appearanceProvider);
    return ListTile(
      key: const Key('appearance-setting'),
      leading: Icon(_icon(mode)),
      title: const Text('Appearance'),
      subtitle: Text(appearanceLabel(mode)),
      trailing: const Icon(Icons.chevron_right_rounded),
      onTap: () => showAppearanceSelector(context),
    );
  }
}

class AppearanceButton extends ConsumerWidget {
  const AppearanceButton({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) => IconButton(
    tooltip: 'Change appearance',
    onPressed: () => showAppearanceSelector(context),
    icon: Icon(_icon(ref.watch(appearanceProvider))),
  );
}

class _AppearanceChoices extends ConsumerWidget {
  const _AppearanceChoices();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = ref.watch(appearanceProvider);
    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Text(
                'Appearance',
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            for (final mode in [
              ThemeMode.light,
              ThemeMode.dark,
              ThemeMode.system,
            ])
              Semantics(
                selected: current == mode,
                child: ListTile(
                  key: Key('appearance-${mode.name}'),
                  leading: Icon(_icon(mode)),
                  title: Text(appearanceLabel(mode)),
                  subtitle: mode == ThemeMode.system
                      ? const Text('Follow your device setting')
                      : null,
                  trailing: current == mode
                      ? Icon(
                          Icons.check_circle_rounded,
                          color: AppColors.of(context).brand600,
                        )
                      : null,
                  onTap: () async {
                    final messenger = ScaffoldMessenger.of(context);
                    final pending = ref
                        .read(appearanceProvider.notifier)
                        .select(mode);
                    Navigator.of(context).pop();
                    try {
                      await pending;
                    } catch (_) {
                      messenger.showSnackBar(
                        const SnackBar(
                          content: Text(
                            'Appearance changed. Your device could not save this preference.',
                          ),
                        ),
                      );
                    }
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}
