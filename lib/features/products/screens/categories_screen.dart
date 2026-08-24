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
    final categories = ref.watch(storeProvider).categories;
    return Scaffold(
      appBar: AppBar(title: const Text('Categories')),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            maxWidth: AppBreakpoints.maxContentWidth,
          ),
          child: GridView.builder(
            padding: const EdgeInsets.all(AppSpacing.xl),
            itemCount: categories.length,
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 230,
              mainAxisExtent: 180,
              mainAxisSpacing: AppSpacing.md,
              crossAxisSpacing: AppSpacing.md,
            ),
            itemBuilder: (_, index) {
              final category = categories[index];
              return CategoryTile(
                category: category,
                onTap: () => context.push('/products?category=${category.id}'),
              );
            },
          ),
        ),
      ),
    );
  }
}
