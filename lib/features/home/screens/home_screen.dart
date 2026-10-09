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
  ).take(24).toList(growable: false);
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
                  AppSpacing.md,
                ),
                sliver: SliverList.list(
                  children: [
                    _HomeHeader(cartCount: cartCount),
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      'Pickup from Koya Stores or get your order delivered today.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppColors.of(context).inkSecondary,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    TextField(
                      readOnly: true,
                      onTap: () => context.push('/products'),
                      decoration: const InputDecoration(
                        hintText: 'Search atta, milk, fruits…',
                        prefixIcon: Icon(Icons.search_rounded),
                        suffixIcon: Icon(Icons.tune_rounded),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    const _HomeOffer(),
                    const SizedBox(height: AppSpacing.xxl),
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
                    const SizedBox(height: AppSpacing.xxl),
                    _SectionHeader(
                      title: 'Popular near you',
                      onTap: () => context.push('/products'),
                    ),
                    const SizedBox(height: AppSpacing.md),
                  ],
                ),
              ),
              SliverLayoutBuilder(
                builder: (context, constraints) {
                  final inset = context.isCompact
                      ? AppSpacing.xl
                      : AppSpacing.xxxl;
                  return SliverPadding(
                    padding: EdgeInsets.fromLTRB(
                      inset,
                      0,
                      inset,
                      AppSpacing.xxxl,
                    ),
                    sliver: SliverGrid.builder(
                      itemCount: featured.length,
                      gridDelegate: ProductGridLayout.delegate(
                        context,
                        constraints.crossAxisExtent - inset * 2,
                      ),
                      itemBuilder: (_, index) => ProductCard(
                        key: ValueKey(featured[index].representative.id),
                        product: featured[index].representative,
                        family: featured[index],
                      ),
                    ),
                  );
                },
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
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: Semantics(
            header: true,
            child: Text(
              'Koya Stores',
              key: const Key('home-store-title'),
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                color: AppColors.of(context).brand700,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
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
                  decoration: BoxDecoration(
                    color: AppColors.of(context).offer,
                    borderRadius: BorderRadius.all(
                      Radius.circular(AppRadii.full),
                    ),
                  ),
                  child: Text(
                    '$cartCount',
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: AppColors.of(context).surface,
                    ),
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
      constraints: const BoxConstraints(minHeight: 140),
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppColors.of(context).brandSoft,
            AppColors.of(context).mint,
            AppColors.of(context).peach,
          ],
          stops: const [0, 0.6, 1],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(AppRadii.xxl),
        border: Border.all(
          color: AppColors.of(context).surface.withValues(alpha: 0.7),
        ),
        boxShadow: AppShadows.of(context, elevated: true),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final copy = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                'SHOP YOUR WAY',
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: AppColors.of(context).brand700,
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                'Free pickup,\nevery day',
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  color: AppColors.of(context).ink,
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                'We will notify you when it is ready',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppColors.of(context).inkSecondary,
                ),
              ),
            ],
          );
          final illustration = ExcludeSemantics(
            child: Image.asset(
              'assets/category_images/fresh-produce.png',
              width: context.isCompact ? 116 : 150,
              height: 108,
              fit: BoxFit.contain,
            ),
          );
          if (constraints.maxWidth < 520 &&
              MediaQuery.textScalerOf(context).scale(20) > 28) {
            return Column(
              key: const Key('home-offer-stacked'),
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                copy,
                const SizedBox(height: AppSpacing.sm),
                Align(alignment: Alignment.centerRight, child: illustration),
              ],
            );
          }
          return Row(
            children: [
              Expanded(child: copy),
              const SizedBox(width: AppSpacing.sm),
              Flexible(child: illustration),
            ],
          );
        },
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
