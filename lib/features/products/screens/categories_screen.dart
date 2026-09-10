import 'dart:math' as math;

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
          child: LayoutBuilder(
            builder: (context, constraints) {
              final available = constraints.maxWidth - AppSpacing.xl * 2;
              final largeText = MediaQuery.textScalerOf(context).scale(16) > 22;
              final columns = math.max(
                largeText ? 1 : 2,
                (available / (largeText ? 220 : 180)).floor(),
              );
              final tileWidth =
                  (available - AppSpacing.md * (columns - 1)) / columns;
              return GridView.builder(
                padding: const EdgeInsets.all(AppSpacing.xl),
                itemCount: categories.length,
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: columns,
                  mainAxisExtent: CategoryTile.extentFor(
                    context,
                    width: tileWidth,
                    categories: categories,
                  ),
                  mainAxisSpacing: AppSpacing.md,
                  crossAxisSpacing: AppSpacing.md,
                ),
                itemBuilder: (_, index) {
                  final category = categories[index];
                  return CategoryTile(
                    category: category,
                    onTap: () =>
                        context.push('/products?category=${category.id}'),
                  );
                },
              );
            },
          ),
        ),
      ),
    );
  }
}
