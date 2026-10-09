import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_shadows.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/product_grid_layout.dart';
import '../../../core/utils/app_breakpoints.dart';
import '../../../core/widgets/empty_state.dart';
import '../../cart/widgets/active_cart_ribbon.dart';
import '../../store/providers/store_provider.dart';
import '../models/category.dart';
import '../models/product.dart';
import '../product_search.dart';
import '../product_variants.dart';
import '../providers/product_search_history_provider.dart';
import '../widgets/category_tile.dart';
import '../widgets/product_card.dart';
import '../widgets/product_visual.dart';

class ProductListingScreen extends ConsumerStatefulWidget {
  const ProductListingScreen({this.categoryId, super.key});

  final String? categoryId;

  @override
  ConsumerState<ProductListingScreen> createState() =>
      _ProductListingScreenState();
}

class _ProductListingScreenState extends ConsumerState<ProductListingScreen> {
  static const _popularSearches = <_PopularSearch>[
    _PopularSearch('Atta', Icons.grain_rounded),
    _PopularSearch('Rice', Icons.rice_bowl_rounded),
    _PopularSearch('Milk', Icons.local_drink_rounded),
    _PopularSearch('Biscuits', Icons.cookie_rounded),
    _PopularSearch('Detergent', Icons.local_laundry_service_rounded),
    _PopularSearch('Shampoo', Icons.spa_rounded),
    _PopularSearch('Pooja supplies', Icons.local_florist_rounded),
  ];

  late String? _categoryId = widget.categoryId;
  late final TextEditingController _searchController;
  late final FocusNode _searchFocus;
  String _draftQuery = '';
  String _query = '';
  bool _searchFocused = false;
  Timer? _debounce;

  List<Product>? _cachedProducts;
  String? _cachedQuery;
  String? _cachedCategoryId;
  List<ProductFamily>? _cachedFamilies;

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController();
    _searchFocus = FocusNode()..addListener(_onFocusChanged);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchFocus
      ..removeListener(_onFocusChanged)
      ..dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _onFocusChanged() {
    if (mounted && _searchFocused != _searchFocus.hasFocus) {
      setState(() => _searchFocused = _searchFocus.hasFocus);
    }
  }

  void _onSearchChanged(String value) {
    setState(() => _draftQuery = value);
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 180), () {
      if (mounted) setState(() => _query = value.trim());
    });
  }

  void _commitSearch([String? value]) {
    final query = (value ?? _searchController.text).trim();
    if (query.isEmpty) return;
    _debounce?.cancel();
    _searchController.value = TextEditingValue(
      text: query,
      selection: TextSelection.collapsed(offset: query.length),
    );
    setState(() {
      _draftQuery = query;
      _query = query;
    });
    ref.read(productSearchHistoryProvider.notifier).add(query);
    _searchFocus.unfocus();
  }

  void _clearSearch() {
    _debounce?.cancel();
    _searchController.clear();
    setState(() {
      _draftQuery = '';
      _query = '';
    });
    _searchFocus.requestFocus();
  }

  void _selectCategory(String? categoryId, {bool closeSearch = false}) {
    setState(() => _categoryId = categoryId);
    if (closeSearch) _searchFocus.unfocus();
  }

  List<ProductFamily> _filter(List<Product> products) {
    if (identical(_cachedProducts, products) &&
        _cachedQuery == _query &&
        _cachedCategoryId == _categoryId &&
        _cachedFamilies != null) {
      return _cachedFamilies!;
    }
    final matches = ProductSearch.search(
      products: products,
      query: _query,
      categoryId: _categoryId,
      filter: (product) => product.active,
    );
    final families = ProductVariants.collapse(
      visibleProducts: matches,
      catalogue: products,
    );
    _cachedProducts = products;
    _cachedQuery = _query;
    _cachedCategoryId = _categoryId;
    _cachedFamilies = families;
    return families;
  }

  @override
  Widget build(BuildContext context) {
    final store = ref.watch(storeProvider);
    final history = ref.watch(productSearchHistoryProvider);
    final families = _filter(store.products);
    final selectedCategory = store.categories
        .where((category) => category.id == _categoryId)
        .firstOrNull;
    final draft = _draftQuery.trim();
    final showDiscovery = _searchFocused && draft.isEmpty;
    final showSuggestions = _searchFocused && draft.isNotEmpty;
    final suggestions = showSuggestions
        ? ProductSearch.suggestions(
            products: store.products,
            query: draft,
            categoryId: _categoryId,
            filter: (product) => product.active,
          )
        : const <ProductSearchSuggestion>[];

    return Scaffold(
      appBar: AppBar(
        title: Text(selectedCategory?.name ?? 'Search products'),
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
      bottomNavigationBar: const ActiveCartRibbon(),
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
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(AppRadii.lg),
                    boxShadow: _searchFocused
                        ? AppShadows.of(context, elevated: true)
                        : AppShadows.of(context),
                  ),
                  child: TextField(
                    key: const Key('product-search'),
                    controller: _searchController,
                    focusNode: _searchFocus,
                    autofocus: widget.categoryId == null,
                    textInputAction: TextInputAction.search,
                    autocorrect: true,
                    enableSuggestions: true,
                    onChanged: _onSearchChanged,
                    onSubmitted: _commitSearch,
                    decoration: InputDecoration(
                      hintText: 'Search atta, milk, brands and more',
                      prefixIcon: const Icon(Icons.search_rounded),
                      suffixIcon: draft.isEmpty
                          ? null
                          : IconButton(
                              key: const Key('clear-product-search'),
                              tooltip: 'Clear search',
                              onPressed: _clearSearch,
                              icon: const Icon(Icons.close_rounded),
                            ),
                    ),
                  ),
                ),
              ),
              _CategoryFilters(
                categories: store.categories,
                selectedCategoryId: _categoryId,
                onSelected: _selectCategory,
              ),
              const SizedBox(height: AppSpacing.md),
              Expanded(
                child: showDiscovery
                    ? _SearchDiscovery(
                        history: history,
                        popularSearches: _popularSearches,
                        categories: store.categories,
                        onSearchSelected: _commitSearch,
                        onCategorySelected: (categoryId) =>
                            _selectCategory(categoryId, closeSearch: true),
                        onClearHistory: () => ref
                            .read(productSearchHistoryProvider.notifier)
                            .clear(),
                      )
                    : showSuggestions
                    ? _SearchSuggestions(
                        query: draft,
                        suggestions: suggestions,
                        onSelected: _commitSearch,
                      )
                    : _SearchResults(
                        families: families,
                        query: _query,
                        categoryName: selectedCategory?.name,
                        onClearSearch: _clearSearch,
                        onShowAll: () => _selectCategory(null),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CategoryFilters extends StatelessWidget {
  const _CategoryFilters({
    required this.categories,
    required this.selectedCategoryId,
    required this.onSelected,
  });

  final List<ProductCategory> categories;
  final String? selectedCategoryId;
  final ValueChanged<String?> onSelected;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 32 + MediaQuery.textScalerOf(context).scale(12) * 1.33,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
        children: [
          ChoiceChip(
            label: const Text('All'),
            selected: selectedCategoryId == null,
            onSelected: (_) => onSelected(null),
          ),
          const SizedBox(width: AppSpacing.sm),
          ...categories.expand(
            (category) => [
              ChoiceChip(
                label: Text(category.name),
                selected: selectedCategoryId == category.id,
                onSelected: (_) => onSelected(category.id),
              ),
              const SizedBox(width: AppSpacing.sm),
            ],
          ),
        ],
      ),
    );
  }
}

class _SearchDiscovery extends StatelessWidget {
  const _SearchDiscovery({
    required this.history,
    required this.popularSearches,
    required this.categories,
    required this.onSearchSelected,
    required this.onCategorySelected,
    required this.onClearHistory,
  });

  final List<String> history;
  final List<_PopularSearch> popularSearches;
  final List<ProductCategory> categories;
  final ValueChanged<String> onSearchSelected;
  final ValueChanged<String> onCategorySelected;
  final VoidCallback onClearHistory;

  @override
  Widget build(BuildContext context) {
    return ListView(
      key: const Key('search-discovery'),
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.xl,
        AppSpacing.sm,
        AppSpacing.xl,
        AppSpacing.xxxl,
      ),
      children: [
        if (history.isNotEmpty) ...[
          _SectionHeading(
            title: 'Recent searches',
            actionLabel: 'Clear',
            onAction: onClearHistory,
          ),
          const SizedBox(height: AppSpacing.sm),
          Material(
            color: AppColors.of(context).surface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadii.lg),
              side: BorderSide(color: AppColors.of(context).outline),
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: history.indexed
                  .map((entry) {
                    final (index, query) = entry;
                    return Column(
                      children: [
                        ListTile(
                          leading: const Icon(Icons.history_rounded),
                          title: Text(query),
                          trailing: const Icon(
                            Icons.north_west_rounded,
                            size: 18,
                          ),
                          onTap: () => onSearchSelected(query),
                        ),
                        if (index != history.length - 1)
                          const Divider(indent: 56),
                      ],
                    );
                  })
                  .toList(growable: false),
            ),
          ),
          const SizedBox(height: AppSpacing.xxl),
        ],
        const _SectionHeading(title: 'Popular searches'),
        const SizedBox(height: AppSpacing.md),
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: popularSearches
              .map(
                (search) => ActionChip(
                  avatar: Icon(search.icon, size: 18),
                  label: Text(search.label),
                  onPressed: () => onSearchSelected(search.label),
                ),
              )
              .toList(growable: false),
        ),
        const SizedBox(height: AppSpacing.xxxl),
        const _SectionHeading(title: 'Shop by category'),
        const SizedBox(height: AppSpacing.md),
        LayoutBuilder(
          builder: (context, constraints) {
            final columns = constraints.maxWidth >= 720 ? 3 : 2;
            final tileWidth =
                (constraints.maxWidth - AppSpacing.md * (columns - 1)) /
                columns;
            return Wrap(
              spacing: AppSpacing.md,
              runSpacing: AppSpacing.md,
              children: categories
                  .map(
                    (category) => SizedBox(
                      width: tileWidth,
                      child: _CategoryDiscoveryTile(
                        category: category,
                        onTap: () => onCategorySelected(category.id),
                      ),
                    ),
                  )
                  .toList(growable: false),
            );
          },
        ),
      ],
    );
  }
}

class _SearchSuggestions extends StatelessWidget {
  const _SearchSuggestions({
    required this.query,
    required this.suggestions,
    required this.onSelected,
  });

  final String query;
  final List<ProductSearchSuggestion> suggestions;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    return ListView(
      key: const Key('search-suggestions'),
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.xl,
        AppSpacing.xs,
        AppSpacing.xl,
        AppSpacing.xxxl,
      ),
      children: [
        Material(
          color: AppColors.of(context).brandSoft,
          borderRadius: BorderRadius.circular(AppRadii.lg),
          clipBehavior: Clip.antiAlias,
          child: ListTile(
            key: const Key('search-all-results'),
            leading: CircleAvatar(
              backgroundColor: AppColors.of(context).surface,
              foregroundColor: AppColors.of(context).brand700,
              child: Icon(Icons.search_rounded),
            ),
            title: Text('Search for "$query"'),
            subtitle: const Text('See all matching products'),
            trailing: const Icon(Icons.arrow_forward_rounded),
            onTap: () => onSelected(query),
          ),
        ),
        if (suggestions.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.xxl),
          const _SectionHeading(title: 'Suggested for you'),
          const SizedBox(height: AppSpacing.sm),
          Material(
            color: AppColors.of(context).surface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadii.lg),
              side: BorderSide(color: AppColors.of(context).outline),
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: suggestions.indexed
                  .map((entry) {
                    final (index, suggestion) = entry;
                    return Column(
                      children: [
                        _SuggestionTile(
                          suggestion: suggestion,
                          onTap: () => onSelected(suggestion.query),
                        ),
                        if (index != suggestions.length - 1)
                          const Divider(indent: 76),
                      ],
                    );
                  })
                  .toList(growable: false),
            ),
          ),
        ] else if (query.length >= 2) ...[
          const SizedBox(height: AppSpacing.xxxl),
          const EmptyState(
            icon: Icons.manage_search_rounded,
            title: 'No suggestions yet',
            message: 'Check the spelling or search for a broader grocery item.',
          ),
        ],
      ],
    );
  }
}

class _SuggestionTile extends StatelessWidget {
  const _SuggestionTile({required this.suggestion, required this.onTap});

  final ProductSearchSuggestion suggestion;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final product = suggestion.product;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.xs,
      ),
      leading: SizedBox.square(
        dimension: 52,
        child: product == null
            ? DecoratedBox(
                decoration: BoxDecoration(
                  color: AppColors.of(context).surfaceMuted,
                  borderRadius: BorderRadius.circular(AppRadii.md),
                ),
                child: Icon(
                  suggestion.kind == ProductSearchSuggestionKind.brand
                      ? Icons.sell_outlined
                      : Icons.category_outlined,
                  color: AppColors.of(context).brand700,
                ),
              )
            : ClipRRect(
                borderRadius: BorderRadius.circular(AppRadii.md),
                child: ProductVisual(product: product, iconSize: 26),
              ),
      ),
      title: Text(
        suggestion.label,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(suggestion.detail),
      trailing: const Icon(Icons.north_west_rounded, size: 18),
      onTap: onTap,
    );
  }
}

class _SearchResults extends StatelessWidget {
  const _SearchResults({
    required this.families,
    required this.query,
    required this.categoryName,
    required this.onClearSearch,
    required this.onShowAll,
  });

  final List<ProductFamily> families;
  final String query;
  final String? categoryName;
  final VoidCallback onClearSearch;
  final VoidCallback onShowAll;

  @override
  Widget build(BuildContext context) {
    if (families.isEmpty) {
      return EmptyState(
        icon: Icons.search_off_rounded,
        title: 'No products found',
        message: 'Try another spelling or browse every category.',
        action: FilledButton.tonalIcon(
          onPressed: () {
            onShowAll();
            onClearSearch();
          },
          icon: const Icon(Icons.grid_view_rounded),
          label: const Text('Browse all products'),
        ),
      );
    }

    final description = query.isNotEmpty
        ? '${families.length} results for "$query"'
        : categoryName == null
        ? '${families.length} products available to browse'
        : '${families.length} products in $categoryName';
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.xl,
            0,
            AppSpacing.xl,
            AppSpacing.md,
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  description,
                  key: const Key('product-result-count'),
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AppColors.of(context).inkSecondary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (query.isNotEmpty)
                TextButton(
                  onPressed: onClearSearch,
                  child: const Text('Clear'),
                ),
            ],
          ),
        ),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) => GridView.builder(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.xl,
                0,
                AppSpacing.xl,
                AppSpacing.xxxl,
              ),
              itemCount: families.length,
              gridDelegate: ProductGridLayout.delegate(
                context,
                constraints.maxWidth - (AppSpacing.xl * 2),
              ),
              itemBuilder: (_, index) => ProductCard(
                product: families[index].representative,
                family: families[index],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _CategoryDiscoveryTile extends StatelessWidget {
  const _CategoryDiscoveryTile({required this.category, required this.onTap});

  final ProductCategory category;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.of(context).surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadii.lg),
        side: BorderSide(color: AppColors.of(context).outline),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Row(
            children: [
              CategoryPicture(
                visualKey: category.visualKey,
                width: 56,
                height: 56,
                radius: AppRadii.md,
                padding: 2,
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Text(
                  category.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelLarge,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionHeading extends StatelessWidget {
  const _SectionHeading({required this.title, this.actionLabel, this.onAction});

  final String title;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(title, style: Theme.of(context).textTheme.titleLarge),
        ),
        if (actionLabel != null)
          TextButton(onPressed: onAction, child: Text(actionLabel!)),
      ],
    );
  }
}

class _PopularSearch {
  const _PopularSearch(this.label, this.icon);

  final String label;
  final IconData icon;
}
