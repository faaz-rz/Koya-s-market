import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/app_breakpoints.dart';
import '../../store/providers/store_provider.dart';
import '../widgets/category_tile.dart';

class CategoriesScreen extends ConsumerWidget {
  const CategoriesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final categories = ref.watch(
      storeProvider.select((store) => store.categories),
    );
    return Scaffold(
      appBar: AppBar(title: const Text('Categories')),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: AppBreakpoints.medium),
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.xl,
              AppSpacing.sm,
              AppSpacing.xl,
              AppSpacing.xxl,
            ),
            itemCount: categories.length,
            separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.md),
            itemBuilder: (_, index) {
              final category = categories[index];
              return CategoryTile(
                category: category,
                horizontal: true,
                onTap: () => context.push('/products?category=${category.id}'),
              );
            },
          ),
        ),
      ),
    );
  }
}
