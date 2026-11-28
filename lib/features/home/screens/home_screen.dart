import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/app_breakpoints.dart';
import '../../../core/utils/product_grid_layout.dart';
import '../../../core/widgets/koyas_logo.dart';
import '../../checkout/models/checkout_models.dart';
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
    final address = ref.watch(
      storeProvider.select((store) => store.selectedAddress),
    );
    final categories = ref.watch(
      storeProvider.select((store) => store.categories),
    ).take(8).toList(growable: false);
    final featured = ref.watch(_homeFeaturedProvider);
    final inset = context.isCompact ? AppSpacing.lg : AppSpacing.xxxl;
    final productInset = context.isCompact ? AppSpacing.md : inset;
    final colors = AppColors.of(context);

    return ColoredBox(
      color: colors.marketCream,
      child: SafeArea(
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: AppBreakpoints.maxContentWidth,
            ),
            child: CustomScrollView(
              slivers: [
                SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(inset, AppSpacing.sm, inset, 0),
                    child: _HomeHeader(address: address),
                  ),
                ),
                PinnedHeaderSliver(
                  child: ColoredBox(
                    color: colors.marketCream,
                    child: Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: inset,
                        vertical: AppSpacing.md,
                      ),
                      child: _SearchEntry(onTap: () => context.push('/products')),
                    ),
                  ),
                ),
                SliverPadding(
                  padding: EdgeInsets.fromLTRB(inset, 0, inset, AppSpacing.md),
                  sliver: SliverList.list(
                    children: [
                      const _MarketBanner(),
                      if (categories.isNotEmpty) ...[
                        const SizedBox(height: AppSpacing.lg),
                        _SectionHeader(
                          title: 'Shop by category',
                          action: 'All categories',
                          onTap: () => context.go('/categories'),
                        ),
                      ],
                    ],
                  ),
                ),
                if (categories.isNotEmpty)
                  SliverLayoutBuilder(
                    builder: (context, constraints) => SliverPadding(
                      padding: EdgeInsets.symmetric(horizontal: inset),
                      sliver: SliverGrid.builder(
                        itemCount: categories.length,
                        gridDelegate: CategoryTile.gridDelegate(
                          context,
                          constraints.crossAxisExtent - inset * 2,
                          categories,
                        ),
                        itemBuilder: (_, index) {
                          final category = categories[index];
                          return CategoryTile(
                            category: category,
                            compact: true,
                            onTap: () => context.push(
                              '/products?category=${category.id}',
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                if (featured.isNotEmpty) ...[
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(
                        inset, AppSpacing.lg, inset, AppSpacing.md,
                      ),
                      child: _SectionHeader(
                        title: 'Store favourites',
                        action: 'See all',
                        onTap: () => context.push('/products?browse=1'),
                      ),
                    ),
                  ),
                  SliverLayoutBuilder(
                    builder: (context, constraints) => SliverPadding(
                      padding: EdgeInsets.fromLTRB(
                        productInset,
                        0,
                        productInset,
                        AppSpacing.xxxl,
                      ),
                      sliver: SliverGrid.builder(
                        itemCount: featured.length,
                        gridDelegate: ProductGridLayout.delegate(
                          context,
                          constraints.crossAxisExtent - productInset * 2,
                        ),
                        itemBuilder: (_, index) => ProductCard(
                          key: ValueKey(featured[index].representative.id),
                          product: featured[index].representative,
                          family: featured[index],
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _HomeHeader extends StatelessWidget {
  const _HomeHeader({required this.address});

  final CustomerAddress? address;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final text = Theme.of(context).textTheme;
    final current = address;
    final addressLabel = current == null
        ? 'Add a delivery address'
        : '${current.label} · ${current.city} ${current.pincode}';
    return Row(
      children: [
        const KoyasLogo(compact: true),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: Semantics(
            button: true,
            label: 'Manage delivery address',
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () => context.go('/profile'),
                borderRadius: BorderRadius.circular(AppRadii.md),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Koya Stores',
                        key: const Key('home-store-title'),
                        style: text.titleLarge?.copyWith(
                          color: colors.ink,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      Row(
                        children: [
                          Icon(Icons.place_outlined, size: 14, color: colors.brand700),
                          const SizedBox(width: AppSpacing.xs),
                          Flexible(
                            child: Text(
                              addressLabel,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: text.bodySmall?.copyWith(color: colors.inkSecondary),
                            ),
                          ),
                          Icon(Icons.keyboard_arrow_down_rounded, size: 16, color: colors.brand700),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _SearchEntry extends StatelessWidget {
  const _SearchEntry({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Material(
      color: colors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadii.lg),
        side: BorderSide(color: colors.outlineStrong),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        key: const Key('home-search'),
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 52),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.lg,
              vertical: AppSpacing.sm,
            ),
            child: Row(
              children: [
                Icon(Icons.search_rounded, color: colors.brand700),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Text(
                    'Search groceries',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: colors.inkSecondary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MarketBanner extends StatelessWidget {
  const _MarketBanner();

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Material(
      color: const Color(0xFF183E2C),
      borderRadius: BorderRadius.circular(AppRadii.xxl),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final stacked = constraints.maxWidth < 520 &&
                MediaQuery.textScalerOf(context).scale(20) > 28;
            final copy = Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Everyday essentials',
                  style: text.headlineSmall?.copyWith(
                    color: AppColors.marketCream,
                    fontWeight: FontWeight.w800,
                    height: 1.12,
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  'Shop for delivery or pickup',
                  style: text.bodySmall?.copyWith(color: const Color(0xFFD4E9DD)),
                ),
                const SizedBox(height: AppSpacing.sm),
                FilledButton(
                  onPressed: () => context.push('/products?browse=1'),
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFFE5EEAA),
                    foregroundColor: AppColors.ink,
                  ),
                  child: const Text('Browse groceries'),
                ),
              ],
            );
            final illustration = ExcludeSemantics(
              child: SizedBox(
                width: constraints.maxWidth > 520 ? 152 : 110,
                height: constraints.maxWidth > 520 ? 152 : 110,
                child: DecoratedBox(
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: Color(0xFF577854),
                  ),
                  child: Image.asset(
                    'assets/category_images/fresh-produce.png',
                    fit: BoxFit.contain,
                  ),
                ),
              ),
            );
            if (stacked) {
              return Column(
                key: const Key('home-offer-stacked'),
                crossAxisAlignment: CrossAxisAlignment.start,
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
                illustration,
              ],
            );
          },
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.title,
    required this.action,
    required this.onTap,
  });

  final String title;
  final String action;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final heading = Semantics(
      header: true,
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleLarge?.copyWith(
          fontWeight: FontWeight.w800,
        ),
      ),
    );
    final link = TextButton(onPressed: onTap, child: Text(action));
    if (MediaQuery.textScalerOf(context).scale(14) > 22) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [heading, link],
      );
    }
    return Row(children: [Expanded(child: heading), link]);
  }
}
