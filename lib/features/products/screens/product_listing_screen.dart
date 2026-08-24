import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/app_breakpoints.dart';
import '../../../core/widgets/empty_state.dart';
import '../../store/providers/store_provider.dart';
import '../models/product.dart';
import '../product_search.dart';
import '../product_variants.dart';
import '../widgets/product_card.dart';

class ProductListingScreen extends ConsumerStatefulWidget {
  const ProductListingScreen({this.categoryId, super.key});

  final String? categoryId;

  @override
  ConsumerState<ProductListingScreen> createState() =>
      _ProductListingScreenState();
}

class _ProductListingScreenState extends ConsumerState<ProductListingScreen> {
  late String? _categoryId = widget.categoryId;
  String _query = '';
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 280), () {
      if (mounted) setState(() => _query = value);
    });
  }

  List<ProductFamily> _filter(List<Product> products) {
    final matches = ProductSearch.search(
      products: products,
      query: _query,
      categoryId: _categoryId,
    );
    return ProductVariants.collapse(
      visibleProducts: matches,
      catalogue: products,
    );
  }

  @override
  Widget build(BuildContext context) {
    final store = ref.watch(storeProvider);
    final families = _filter(store.products);
    final title = _categoryId == null
        ? 'All products'
        : store.categories
                  .where((category) => category.id == _categoryId)
                  .map((category) => category.name)
                  .firstOrNull ??
              'Products';
    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        actions: [
          IconButton(
            tooltip: 'Cart',
            onPressed: () => context.push('/cart'),
            icon: Badge(
              isLabelVisible: store.cartCount > 0,
              label: Text('${store.cartCount}'),
              child: const Icon(Icons.shopping_bag_outlined),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
        ],
      ),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            maxWidth: AppBreakpoints.maxContentWidth,
          ),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.xl,
                  AppSpacing.sm,
                  AppSpacing.xl,
                  AppSpacing.md,
                ),
                child: TextField(
                  key: const Key('product-search'),
                  onChanged: _onSearchChanged,
                  decoration: const InputDecoration(
                    hintText: 'Search products, brands or needs',
                    prefixIcon: Icon(Icons.search_rounded),
                  ),
                ),
              ),
              SizedBox(
                height: 52,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.xl,
                  ),
                  children: [
                    ChoiceChip(
                      label: const Text('All'),
                      selected: _categoryId == null,
                      onSelected: (_) => setState(() => _categoryId = null),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    ...store.categories.expand(
                      (category) => [
                        ChoiceChip(
                          label: Text(category.name),
                          selected: _categoryId == category.id,
                          onSelected: (_) =>
                              setState(() => _categoryId = category.id),
                        ),
                        const SizedBox(width: AppSpacing.sm),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              Expanded(
                child: families.isEmpty
                    ? const EmptyState(
                        icon: Icons.search_off_rounded,
                        title: 'No products found',
                        message:
                            'Try another search or choose a different category.',
                      )
                    : GridView.builder(
                        padding: const EdgeInsets.fromLTRB(
                          AppSpacing.xl,
                          0,
                          AppSpacing.xl,
                          AppSpacing.xxxl,
                        ),
                        itemCount: families.length,
                        gridDelegate:
                            const SliverGridDelegateWithMaxCrossAxisExtent(
                              maxCrossAxisExtent: 230,
                              mainAxisExtent: 380,
                              mainAxisSpacing: AppSpacing.md,
                              crossAxisSpacing: AppSpacing.md,
                            ),
                        itemBuilder: (_, index) => ProductCard(
                          product: families[index].representative,
                          family: families[index],
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
