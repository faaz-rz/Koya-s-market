import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_shadows.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/app_breakpoints.dart';
import '../../../core/utils/product_grid_layout.dart';
import '../../../core/widgets/koyas_logo.dart';
import '../../products/product_variants.dart';
import '../../products/widgets/category_tile.dart';
import '../../products/widgets/product_card.dart';
import '../../store/providers/store_provider.dart';

final _homeFeaturedProvider = Provider<List<ProductFamily>>((ref) {
  final products = ref.watch(storeProvider.select((store) => store.products));
  return ProductVariants.collapse(
    visibleProducts: products.where((product) => product.featured),
    catalogue: products,
  );
});

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cartCount = ref.watch(
      storeProvider.select((store) => store.cartCount),
    );
    final categories = ref.watch(
      storeProvider.select((store) => store.categories),
    );
    final featured = ref.watch(_homeFeaturedProvider);
    return SafeArea(
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            maxWidth: AppBreakpoints.maxContentWidth,
          ),
          child: CustomScrollView(
            slivers: [
              SliverPadding(
                padding: EdgeInsets.fromLTRB(
                  context.isCompact ? AppSpacing.xl : AppSpacing.xxxl,
                  AppSpacing.lg,
                  context.isCompact ? AppSpacing.xl : AppSpacing.xxxl,
                  AppSpacing.xxxl,
                ),
                sliver: SliverList.list(
                  children: [
                    _HomeHeader(cartCount: cartCount),
                    const SizedBox(height: AppSpacing.xxl),
                    Text(
                      'Your neighbourhood supermarket,\nnow at your fingertips.',
                      style: Theme.of(context).textTheme.displayLarge,
                    ),
                    const SizedBox(height: AppSpacing.md),
                    Text(
                      'Pickup from Koya Stores or get your order delivered today.',
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        color: AppColors.inkSecondary,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xxl),
                    TextField(
                      readOnly: true,
                      onTap: () => context.push('/products'),
                      decoration: const InputDecoration(
                        hintText: 'Search atta, milk, fruits…',
                        prefixIcon: Icon(Icons.search_rounded),
                        suffixIcon: Icon(Icons.tune_rounded),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xxl),
                    const _HomeOffer(),
                    const SizedBox(height: AppSpacing.section),
                    _SectionHeader(
                      title: 'Shop by category',
                      onTap: () => context.go('/categories'),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    SizedBox(
                      height: CategoryTile.extentFor(
                        context,
                        width: 128,
                        categories: categories,
                        compact: true,
                      ),
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: categories.length,
                        separatorBuilder: (_, _) =>
                            const SizedBox(width: AppSpacing.md),
                        itemBuilder: (context, index) {
                          final category = categories[index];
                          return SizedBox(
                            width: 128,
                            child: CategoryTile(
                              category: category,
                              compact: true,
                              onTap: () => context.push(
                                '/products?category=${category.id}',
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: AppSpacing.section),
                    _SectionHeader(
                      title: 'Popular near you',
                      onTap: () => context.push('/products'),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    LayoutBuilder(
                      builder: (context, constraints) => GridView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: featured.length,
                        gridDelegate: ProductGridLayout.delegate(
                          context,
                          constraints.maxWidth,
                        ),
                        itemBuilder: (_, index) => ProductCard(
                          product: featured[index].representative,
                          family: featured[index],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HomeHeader extends StatelessWidget {
  const _HomeHeader({required this.cartCount});

  final int cartCount;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const KoyasLogo(compact: true),
        const Spacer(),
        Stack(
          clipBehavior: Clip.none,
          children: [
            IconButton.filledTonal(
              tooltip: 'Open cart',
              onPressed: () => context.push('/cart'),
              icon: const Icon(Icons.shopping_bag_outlined),
            ),
            if (cartCount > 0)
              Positioned(
                right: -2,
                top: -4,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: const BoxDecoration(
                    color: AppColors.offer,
                    borderRadius: BorderRadius.all(
                      Radius.circular(AppRadii.full),
                    ),
                  ),
                  child: Text(
                    '$cartCount',
                    style: Theme.of(
                      context,
                    ).textTheme.labelMedium?.copyWith(color: AppColors.surface),
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class _HomeOffer extends StatelessWidget {
  const _HomeOffer();

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 178),
      padding: const EdgeInsets.all(AppSpacing.xxl),
      decoration: BoxDecoration(
        color: AppColors.brand600,
        borderRadius: BorderRadius.circular(AppRadii.xxl),
        boxShadow: AppShadows.medium,
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  'SHOP YOUR WAY',
                  style: Theme.of(
                    context,
                  ).textTheme.labelMedium?.copyWith(color: AppColors.brandSoft),
                ),
                const SizedBox(height: AppSpacing.md),
                Text(
                  'Free pickup,\nevery day',
                  style: Theme.of(
                    context,
                  ).textTheme.headlineLarge?.copyWith(color: AppColors.surface),
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  'We will notify you when it is ready',
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(color: AppColors.brandSoft),
                ),
              ],
            ),
          ),
          Container(
            width: context.isCompact ? 100 : 150,
            height: 126,
            decoration: BoxDecoration(
              color: AppColors.brandSoft,
              borderRadius: BorderRadius.circular(AppRadii.xxl),
            ),
            child: const Icon(
              Icons.shopping_basket_rounded,
              size: 68,
              color: AppColors.brand700,
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, required this.onTap});

  final String title;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(title, style: Theme.of(context).textTheme.titleLarge),
        ),
        TextButton(onPressed: onTap, child: const Text('See all')),
      ],
    );
  }
}
