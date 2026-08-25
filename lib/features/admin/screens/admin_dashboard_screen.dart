import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/config/app_environment.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/price_format.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/koyas_button.dart';
import '../../../core/widgets/koyas_logo.dart';
import '../../../core/widgets/koyas_surface.dart';
import '../../auth/data/auth_repository.dart';
import '../../checkout/models/checkout_models.dart';
import '../analytics/admin_sales_analytics.dart';
import '../../orders/models/order.dart';
import '../../orders/widgets/order_status_ui.dart';
import '../../products/models/category.dart';
import '../../products/models/product.dart';
import '../../products/models/product_image_upload.dart';
import '../../products/product_search.dart';
import '../../products/widgets/product_visual.dart';
import '../../store/data/supabase_store_repository.dart';
import '../../store/providers/store_provider.dart';
import '../../store/widgets/store_realtime_sync.dart';

class AdminDashboardScreen extends ConsumerStatefulWidget {
  const AdminDashboardScreen({super.key});

  @override
  ConsumerState<AdminDashboardScreen> createState() =>
      _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends ConsumerState<AdminDashboardScreen> {
  String _filter = 'Active';
  AdminAnalyticsPeriod _analyticsPeriod = AdminAnalyticsPeriod.daily;
  bool _refreshing = false;
  final _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollTo(double offset) {
    _scrollController.animateTo(
      offset.clamp(0, _scrollController.position.maxScrollExtent),
      duration: const Duration(milliseconds: 420),
      curve: Curves.easeOutCubic,
    );
  }

  bool _terminal(OrderStatus status) => {
    OrderStatus.delivered,
    OrderStatus.collected,
    OrderStatus.cancelled,
    OrderStatus.rejected,
  }.contains(status);

  Future<void> _signOut() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Sign out?'),
        content: const Text(
          'You will need a new secure code to sign in again.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Stay signed in'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Sign out'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    ref.read(storeProvider.notifier).logout();
    if (mounted) context.go('/login');
    if (AppEnvironment.hasSupabaseConfig) {
      try {
        await AuthRepository().signOut();
      } catch (_) {
        // Local staff data is already gone even if remote sign-out is offline.
      }
    }
  }

  Future<void> _refreshDashboard() async {
    if (_refreshing || !AppEnvironment.hasSupabaseConfig) return;
    setState(() => _refreshing = true);
    try {
      final bundle = await SupabaseStoreRepository().loadStore();
      ref.read(storeProvider.notifier).hydrateRemoteBundle(bundle);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Orders and inventory could not be refreshed.'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = ref.watch(storeProvider);
    if (!store.isAdminView ||
        (!store.isAdminAccount && store.profile?.id != 'demo-customer')) {
      return Scaffold(
        body: EmptyState(
          icon: Icons.lock_outline_rounded,
          title: 'Staff access required',
          message: 'Sign in with an administrator account to manage the store.',
          action: KoyasButton(
            label: 'Return to login',
            expand: false,
            onPressed: () => context.go('/login'),
          ),
        ),
      );
    }

    final visibleOrders = store.orders
        .where((order) {
          return switch (_filter) {
            'Pickup' => order.fulfilmentType.name == 'pickup',
            'Delivery' => order.fulfilmentType.name == 'delivery',
            'Completed' => _terminal(order.status),
            'Active' => !_terminal(order.status),
            _ => true,
          };
        })
        .toList(growable: false);
    final activeCount = store.orders
        .where((order) => !_terminal(order.status))
        .length;
    final todayRevenue = store.orders
        .where(
          (order) =>
              order.paymentStatus == PaymentStatus.paid &&
              DateUtils.isSameDay(order.createdAt, DateTime.now()),
        )
        .fold<int>(0, (sum, order) => sum + order.totalPaise);
    final lowStock = store.products
        .where(
          (product) => product.stockQuantity > 0 && product.stockQuantity <= 12,
        )
        .toList(growable: false);
    final outOfStockCount = store.products
        .where((product) => product.stockQuantity == 0)
        .length;
    return StoreRealtimeSync(
      child: Scaffold(
        backgroundColor: AppColors.canvas,
        body: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final desktop = constraints.maxWidth >= 980;
              final content = _DashboardContent(
                scrollController: _scrollController,
                store: store,
                activeCount: activeCount,
                todayRevenue: todayRevenue,
                lowStockCount: lowStock.length,
                outOfStockCount: outOfStockCount,
                visibleOrders: visibleOrders,
                filter: _filter,
                onFilterChanged: (value) => setState(() => _filter = value),
                analyticsPeriod: _analyticsPeriod,
                onAnalyticsPeriodChanged: (value) =>
                    setState(() => _analyticsPeriod = value),
                terminal: _terminal,
                onSignOut: _signOut,
                onRefresh: AppEnvironment.hasSupabaseConfig
                    ? _refreshDashboard
                    : null,
                refreshing: _refreshing,
              );
              if (!desktop) return content;
              return Row(
                children: [
                  _AdminSidebar(
                    onDashboard: () => _scrollTo(0),
                    onAnalytics: () => _scrollTo(520),
                    onSalesControls: () => _scrollTo(1250),
                    onOrders: () => _scrollTo(1900),
                    onInventory: () => _scrollTo(2700),
                    onSignOut: _signOut,
                  ),
                  const VerticalDivider(width: 1),
                  Expanded(child: content),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _AdminSidebar extends StatelessWidget {
  const _AdminSidebar({
    required this.onDashboard,
    required this.onAnalytics,
    required this.onSalesControls,
    required this.onOrders,
    required this.onInventory,
    required this.onSignOut,
  });

  final VoidCallback onDashboard;
  final VoidCallback onAnalytics;
  final VoidCallback onSalesControls;
  final VoidCallback onOrders;
  final VoidCallback onInventory;
  final VoidCallback onSignOut;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 240,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const KoyasLogo(compact: true),
            const SizedBox(height: AppSpacing.xxxl),
            FilledButton.tonalIcon(
              onPressed: onDashboard,
              icon: const Icon(Icons.dashboard_rounded),
              label: const Text('Dashboard'),
            ),
            const SizedBox(height: AppSpacing.sm),
            ListTile(
              leading: const Icon(Icons.analytics_outlined),
              title: const Text('Analytics'),
              onTap: onAnalytics,
            ),
            ListTile(
              leading: const Icon(Icons.local_offer_outlined),
              title: const Text('Delivery & offers'),
              onTap: onSalesControls,
            ),
            ListTile(
              leading: const Icon(Icons.receipt_long_outlined),
              title: const Text('Orders'),
              onTap: onOrders,
            ),
            ListTile(
              leading: const Icon(Icons.inventory_2_outlined),
              title: const Text('Inventory'),
              onTap: onInventory,
            ),
            const Spacer(),
            OutlinedButton.icon(
              onPressed: onSignOut,
              icon: const Icon(Icons.logout_rounded),
              label: const Text('Sign out'),
            ),
          ],
        ),
      ),
    );
  }
}

class _DashboardContent extends ConsumerWidget {
  const _DashboardContent({
    required this.scrollController,
    required this.store,
    required this.activeCount,
    required this.todayRevenue,
    required this.lowStockCount,
    required this.outOfStockCount,
    required this.visibleOrders,
    required this.filter,
    required this.onFilterChanged,
    required this.analyticsPeriod,
    required this.onAnalyticsPeriodChanged,
    required this.terminal,
    required this.onSignOut,
    required this.onRefresh,
    required this.refreshing,
  });

  final ScrollController scrollController;
  final StoreState store;
  final int activeCount;
  final int todayRevenue;
  final int lowStockCount;
  final int outOfStockCount;
  final List<CustomerOrder> visibleOrders;
  final String filter;
  final ValueChanged<String> onFilterChanged;
  final AdminAnalyticsPeriod analyticsPeriod;
  final ValueChanged<AdminAnalyticsPeriod> onAnalyticsPeriodChanged;
  final bool Function(OrderStatus) terminal;
  final VoidCallback onSignOut;
  final VoidCallback? onRefresh;
  final bool refreshing;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final now = DateTime.now();
    final ordersToday = store.orders
        .where((order) => DateUtils.isSameDay(order.createdAt, now))
        .length;
    final pickupOrders = store.orders
        .where(
          (order) =>
              order.fulfilmentType.name == 'pickup' && !terminal(order.status),
        )
        .length;
    final completedOrders = store.orders
        .where((order) => terminal(order.status))
        .length;
    final monthRevenue = store.orders
        .where(
          (order) =>
              order.paymentStatus == PaymentStatus.paid &&
              order.createdAt.year == now.year &&
              order.createdAt.month == now.month,
        )
        .fold<int>(0, (sum, order) => sum + order.totalPaise);
    final activeOffers = store.products
        .where((product) => product.discountPricePaise != null)
        .toList(growable: false);
    final analytics = AdminSalesAnalyticsCalculator.calculate(
      orders: store.orders,
      period: analyticsPeriod,
      now: now,
    );
    return CustomScrollView(
      controller: scrollController,
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.all(AppSpacing.xxl),
          sliver: SliverList.list(
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Store dashboard',
                          style: Theme.of(context).textTheme.headlineLarge,
                        ),
                        const SizedBox(height: AppSpacing.xs),
                        Text(
                          DateFormat('EEEE, d MMMM').format(DateTime.now()),
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(color: AppColors.inkSecondary),
                        ),
                      ],
                    ),
                  ),
                  if (AppEnvironment.hasSupabaseConfig) ...[
                    const Chip(
                      avatar: Icon(
                        Icons.sensors_rounded,
                        size: 18,
                        color: AppColors.success,
                      ),
                      label: Text('Live updates'),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                  ],
                  if (onRefresh != null) ...[
                    IconButton(
                      tooltip: 'Refresh orders and inventory',
                      onPressed: refreshing ? null : onRefresh,
                      icon: refreshing
                          ? const SizedBox.square(
                              dimension: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.refresh_rounded),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                  ],
                  IconButton.filledTonal(
                    tooltip: 'Sign out',
                    onPressed: onSignOut,
                    icon: const Icon(Icons.logout_rounded),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.xxxl),
              GridView.count(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisCount: MediaQuery.sizeOf(context).width >= 760 ? 3 : 1,
                mainAxisSpacing: AppSpacing.md,
                crossAxisSpacing: AppSpacing.md,
                childAspectRatio: MediaQuery.sizeOf(context).width >= 760
                    ? 2.2
                    : 3.1,
                children: [
                  _MetricCard(
                    label: 'Orders today',
                    value: '$ordersToday',
                    icon: Icons.today_rounded,
                    color: AppColors.info,
                  ),
                  _MetricCard(
                    label: 'Active orders',
                    value: '$activeCount',
                    icon: Icons.receipt_long_rounded,
                    color: AppColors.brand600,
                  ),
                  _MetricCard(
                    label: 'Paid today',
                    value: formatPrice(todayRevenue),
                    icon: Icons.trending_up_rounded,
                    color: AppColors.success,
                  ),
                  _MetricCard(
                    label: 'Pickup queue',
                    value: '$pickupOrders',
                    icon: Icons.storefront_outlined,
                    color: AppColors.offer,
                  ),
                  _MetricCard(
                    label: 'Completed',
                    value: '$completedOrders',
                    icon: Icons.task_alt_rounded,
                    color: AppColors.success,
                  ),
                  _MetricCard(
                    label: 'Paid this month',
                    value: formatPrice(monthRevenue),
                    icon: Icons.calendar_month_outlined,
                    color: AppColors.brand600,
                  ),
                  _MetricCard(
                    label: 'Low stock',
                    value: '$lowStockCount items',
                    icon: Icons.inventory_2_outlined,
                    color: lowStockCount > 0
                        ? AppColors.warning
                        : AppColors.success,
                  ),
                  _MetricCard(
                    label: 'Out of stock',
                    value: '$outOfStockCount items',
                    icon: Icons.remove_shopping_cart_outlined,
                    color: outOfStockCount > 0
                        ? AppColors.error
                        : AppColors.success,
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.section),
              _AdminAnalyticsPanel(
                analytics: analytics,
                now: now,
                onPeriodChanged: onAnalyticsPeriodChanged,
              ),
              const SizedBox(height: AppSpacing.section),
              Text(
                'Delivery & offers',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                'These settings are controlled by staff and reflected in customer checkout.',
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(color: AppColors.inkSecondary),
              ),
              const SizedBox(height: AppSpacing.md),
              LayoutBuilder(
                builder: (context, constraints) {
                  final delivery = _DeliveryPricingCard(
                    store: store,
                    onEdit: () => _editDeliveryPricing(context, ref),
                  );
                  final offers = _OfferManagementCard(
                    offers: activeOffers,
                    onAdd: () => _addOffer(context, ref),
                    onManage: () => _manageOffer(context, ref),
                    onEdit: (product) => _editOffer(context, ref, product),
                  );
                  if (constraints.maxWidth < 760) {
                    return Column(
                      children: [
                        delivery,
                        const SizedBox(height: AppSpacing.md),
                        offers,
                      ],
                    );
                  }
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: delivery),
                      const SizedBox(width: AppSpacing.md),
                      Expanded(child: offers),
                    ],
                  );
                },
              ),
              const SizedBox(height: AppSpacing.section),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Order queue',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                  ),
                  PopupMenuButton<String>(
                    initialValue: filter,
                    onSelected: onFilterChanged,
                    itemBuilder: (context) => [
                      for (final value in const [
                        'Active',
                        'All',
                        'Pickup',
                        'Delivery',
                        'Completed',
                      ])
                        PopupMenuItem(value: value, child: Text(value)),
                    ],
                    child: Chip(
                      avatar: const Icon(Icons.filter_list_rounded, size: 18),
                      label: Text(filter),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              if (visibleOrders.isEmpty)
                const KoyasSurface(child: Text('No orders match this filter.'))
              else
                ...visibleOrders.map(
                  (order) => Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.md),
                    child: _AdminOrderRow(
                      order: order,
                      canAdvance: !terminal(order.status),
                      onAdvance: () => _advanceOrder(context, ref, order),
                    ),
                  ),
                ),
              const SizedBox(height: AppSpacing.section),
              _CategoryInventory(
                categories: store.categories,
                products: store.products,
                onAddProduct: (categoryId) =>
                    _editProduct(context, ref, initialCategoryId: categoryId),
                onEditProduct: (product) =>
                    _editProduct(context, ref, product: product),
                onStockChanged: (product, quantity) =>
                    _updateStock(context, ref, product, quantity),
                onStockAdjusted: (product, delta) =>
                    _adjustStock(context, ref, product, delta),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _editProduct(
    BuildContext context,
    WidgetRef ref, {
    Product? product,
    String? initialCategoryId,
  }) async {
    final result = await showDialog<_ProductEditorResult>(
      context: context,
      builder: (context) => _ProductEditorDialog(
        product: product,
        categories: store.categories,
        initialCategoryId: initialCategoryId,
      ),
    );
    if (result == null) return;
    final updated = result.product;
    try {
      if (AppEnvironment.hasSupabaseConfig) {
        final repository = SupabaseStoreRepository();
        await repository.saveProduct(updated, image: result.image);
        final bundle = await repository.loadStore();
        ref.read(storeProvider.notifier).hydrateRemoteBundle(bundle);
      } else {
        ref.read(storeProvider.notifier).adminSaveProduct(updated);
      }
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Product or image could not be saved. Try again.'),
          ),
        );
      }
      return;
    }
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            product == null ? 'Product added.' : 'Product updated.',
          ),
        ),
      );
    }
  }

  Future<void> _editDeliveryPricing(BuildContext context, WidgetRef ref) async {
    final result = await showDialog<_DeliveryPricingResult>(
      context: context,
      builder: (context) => _DeliveryPricingDialog(store: store),
    );
    if (result == null) return;
    try {
      if (AppEnvironment.hasSupabaseConfig) {
        final repository = SupabaseStoreRepository();
        await repository.updateDeliveryPricing(
          deliveryChargePaise: result.deliveryChargePaise,
          freeDeliveryThresholdPaise: result.freeDeliveryThresholdPaise,
        );
        final bundle = await repository.loadStore();
        ref.read(storeProvider.notifier).hydrateRemoteBundle(bundle);
      } else {
        ref
            .read(storeProvider.notifier)
            .adminUpdateDeliveryPricing(
              deliveryChargePaise: result.deliveryChargePaise,
              freeDeliveryThresholdPaise: result.freeDeliveryThresholdPaise,
            );
      }
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Delivery pricing could not be saved.')),
        );
      }
      return;
    }
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result.deliveryChargePaise == 0
                ? 'Delivery is now free.'
                : 'Delivery pricing updated.',
          ),
        ),
      );
    }
  }

  Future<void> _addOffer(BuildContext context, WidgetRef ref) async {
    final product = await showDialog<Product>(
      context: context,
      builder: (context) => _OfferProductPickerDialog(
        products: store.products
            .where((product) => product.discountPricePaise == null)
            .toList(growable: false),
      ),
    );
    if (product != null && context.mounted) {
      await _editOffer(context, ref, product);
    }
  }

  Future<void> _manageOffer(BuildContext context, WidgetRef ref) async {
    final product = await showDialog<Product>(
      context: context,
      builder: (context) => _OfferProductPickerDialog(
        products: store.products
            .where((product) => product.discountPricePaise != null)
            .toList(growable: false),
      ),
    );
    if (product != null && context.mounted) {
      await _editOffer(context, ref, product);
    }
  }

  Future<void> _editOffer(
    BuildContext context,
    WidgetRef ref,
    Product product,
  ) async {
    final updated = await showDialog<Product>(
      context: context,
      builder: (context) => _OfferEditorDialog(product: product),
    );
    if (updated == null) return;
    try {
      if (AppEnvironment.hasSupabaseConfig) {
        final repository = SupabaseStoreRepository();
        await repository.saveProduct(updated);
        final bundle = await repository.loadStore();
        ref.read(storeProvider.notifier).hydrateRemoteBundle(bundle);
      } else {
        ref.read(storeProvider.notifier).adminSaveProduct(updated);
      }
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Offer could not be saved.')),
        );
      }
      return;
    }
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            updated.discountPricePaise == null
                ? 'Offer removed from ${product.name}.'
                : 'Offer applied to ${product.name}.',
          ),
        ),
      );
    }
  }

  Future<void> _updateStock(
    BuildContext context,
    WidgetRef ref,
    Product product,
    int quantity,
  ) => _persistStock(context, ref, product, requestedQuantity: quantity);

  Future<void> _adjustStock(
    BuildContext context,
    WidgetRef ref,
    Product product,
    int delta,
  ) => _persistStock(context, ref, product, adjustment: delta);

  Future<void> _persistStock(
    BuildContext context,
    WidgetRef ref,
    Product product, {
    int? requestedQuantity,
    int? adjustment,
  }) async {
    assert((requestedQuantity == null) != (adjustment == null));
    try {
      final int savedQuantity;
      if (AppEnvironment.hasSupabaseConfig) {
        final repository = SupabaseStoreRepository();
        savedQuantity = requestedQuantity != null
            ? await repository.setProductStock(product.id, requestedQuantity)
            : await repository.adjustProductStock(product.id, adjustment!);
      } else {
        savedQuantity =
            requestedQuantity ??
            (product.stockQuantity + adjustment!).clamp(0, 999999).toInt();
      }
      final updated = product.copyWith(stockQuantity: savedQuantity);
      ref.read(storeProvider.notifier).adminSaveProduct(updated);
      if (context.mounted && requestedQuantity != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${product.name} stock set to $savedQuantity.'),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${product.name} stock could not be updated.'),
          ),
        );
      }
    }
  }

  Future<void> _advanceOrder(
    BuildContext context,
    WidgetRef ref,
    CustomerOrder order,
  ) async {
    try {
      if (AppEnvironment.hasSupabaseConfig) {
        final repository = SupabaseStoreRepository();
        await repository.advanceOrder(order);
        final bundle = await repository.loadStore();
        ref.read(storeProvider.notifier).hydrateRemoteBundle(bundle);
      } else {
        ref.read(storeProvider.notifier).advanceOrder(order.id);
      }
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Order status could not be updated.')),
        );
      }
    }
  }
}

class _CategoryInventory extends StatefulWidget {
  const _CategoryInventory({
    required this.categories,
    required this.products,
    required this.onAddProduct,
    required this.onEditProduct,
    required this.onStockChanged,
    required this.onStockAdjusted,
  });

  final List<ProductCategory> categories;
  final List<Product> products;
  final ValueChanged<String?> onAddProduct;
  final ValueChanged<Product> onEditProduct;
  final Future<void> Function(Product product, int quantity) onStockChanged;
  final Future<void> Function(Product product, int delta) onStockAdjusted;

  @override
  State<_CategoryInventory> createState() => _CategoryInventoryState();
}

class _CategoryInventoryState extends State<_CategoryInventory> {
  static const _displayLimit = 100;

  String? _selectedCategoryId;
  String _query = '';
  String _stockFilter = 'All';
  final Set<String> _busyProductIds = {};

  Future<void> _setStock(Product product, int quantity) async {
    if (_busyProductIds.contains(product.id)) return;
    final safeQuantity = quantity.clamp(0, 999999);
    setState(() => _busyProductIds.add(product.id));
    try {
      await widget.onStockChanged(product, safeQuantity);
    } finally {
      if (mounted) setState(() => _busyProductIds.remove(product.id));
    }
  }

  Future<void> _adjustStock(Product product, int delta) async {
    if (_busyProductIds.contains(product.id)) return;
    setState(() => _busyProductIds.add(product.id));
    try {
      await widget.onStockAdjusted(product, delta);
    } finally {
      if (mounted) setState(() => _busyProductIds.remove(product.id));
    }
  }

  Future<void> _showStockEditor(Product product) async {
    final quantity = await showDialog<int>(
      context: context,
      builder: (_) => _StockEditorDialog(product: product),
    );
    if (quantity != null) await _setStock(product, quantity);
  }

  @override
  Widget build(BuildContext context) {
    final categoryExists = widget.categories.any(
      (category) => category.id == _selectedCategoryId,
    );
    final selectedCategoryId = categoryExists ? _selectedCategoryId : null;
    final selectedCategory = selectedCategoryId == null
        ? null
        : widget.categories.firstWhere(
            (category) => category.id == selectedCategoryId,
          );
    final categoryProducts = widget.products
        .where(
          (product) =>
              selectedCategoryId == null ||
              product.categoryId == selectedCategoryId,
        )
        .toList(growable: false);
    final searchedProducts = ProductSearch.search(
      products: categoryProducts,
      query: _query,
    );
    final visibleProducts = searchedProducts
        .where((product) {
          return switch (_stockFilter) {
            'In stock' => product.stockQuantity > 12,
            'Low stock' =>
              product.stockQuantity > 0 && product.stockQuantity <= 12,
            'Out of stock' => product.stockQuantity == 0,
            _ => true,
          };
        })
        .toList(growable: false);
    final displayedProducts = visibleProducts
        .take(_displayLimit)
        .toList(growable: false);
    final visibleUnits = visibleProducts.fold<int>(
      0,
      (total, product) => total + product.stockQuantity,
    );
    final visibleLowStock = searchedProducts
        .where(
          (product) => product.stockQuantity > 0 && product.stockQuantity <= 12,
        )
        .length;
    final visibleOutOfStock = searchedProducts
        .where((product) => product.stockQuantity == 0)
        .length;

    return Column(
      key: const Key('admin-category-inventory'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: AppSpacing.lg,
          runSpacing: AppSpacing.md,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Inventory by category',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  selectedCategory == null
                      ? 'Browse every category or choose one to manage its products.'
                      : 'Managing ${selectedCategory.name}. New products will be added here.',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AppColors.inkSecondary,
                  ),
                ),
              ],
            ),
            FilledButton.tonalIcon(
              key: const Key('admin-add-product'),
              onPressed: () => widget.onAddProduct(selectedCategoryId),
              icon: const Icon(Icons.add_rounded),
              label: const Text('Add product'),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.lg),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              ChoiceChip(
                key: const Key('admin-category-all'),
                label: Text('All (${widget.products.length})'),
                selected: selectedCategoryId == null,
                selectedColor: AppColors.brandSoft,
                backgroundColor: AppColors.surface,
                showCheckmark: false,
                labelStyle: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: selectedCategoryId == null
                      ? AppColors.brand700
                      : AppColors.ink,
                  fontWeight: FontWeight.w700,
                ),
                onSelected: (_) => setState(() => _selectedCategoryId = null),
              ),
              const SizedBox(width: AppSpacing.sm),
              for (final category in widget.categories) ...[
                ChoiceChip(
                  key: Key('admin-category-${category.id}'),
                  avatar: Icon(
                    selectedCategoryId == category.id
                        ? Icons.folder_rounded
                        : Icons.folder_outlined,
                    size: 18,
                    color: selectedCategoryId == category.id
                        ? AppColors.brand700
                        : AppColors.inkSecondary,
                  ),
                  label: Text(
                    '${category.name} (${widget.products.where((product) => product.categoryId == category.id).length})',
                  ),
                  selected: selectedCategoryId == category.id,
                  selectedColor: AppColors.brandSoft,
                  backgroundColor: AppColors.surface,
                  showCheckmark: false,
                  labelStyle: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: selectedCategoryId == category.id
                        ? AppColors.brand700
                        : AppColors.ink,
                    fontWeight: FontWeight.w700,
                  ),
                  onSelected: (_) =>
                      setState(() => _selectedCategoryId = category.id),
                ),
                const SizedBox(width: AppSpacing.sm),
              ],
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        TextField(
          key: const Key('admin-product-search'),
          onChanged: (value) => setState(() => _query = value),
          decoration: const InputDecoration(
            labelText: 'Search inventory',
            hintText: 'Product, brand, category, or need',
            prefixIcon: Icon(Icons.search_rounded),
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: [
            for (final filter in const [
              'All',
              'In stock',
              'Low stock',
              'Out of stock',
            ])
              ChoiceChip(
                key: Key(
                  'admin-stock-filter-${filter.toLowerCase().replaceAll(' ', '-')}',
                ),
                label: Text(filter),
                selected: _stockFilter == filter,
                showCheckmark: false,
                onSelected: (_) => setState(() => _stockFilter = filter),
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: [
            Chip(
              avatar: const Icon(Icons.sell_outlined, size: 18),
              label: Text('${visibleProducts.length} products'),
              backgroundColor: AppColors.surface,
              labelStyle: Theme.of(
                context,
              ).textTheme.labelLarge?.copyWith(color: AppColors.ink),
            ),
            Chip(
              avatar: const Icon(Icons.inventory_outlined, size: 18),
              label: Text('$visibleUnits total units'),
              backgroundColor: AppColors.surface,
              labelStyle: Theme.of(
                context,
              ).textTheme.labelLarge?.copyWith(color: AppColors.ink),
            ),
            Chip(
              avatar: Icon(
                visibleLowStock == 0
                    ? Icons.check_circle_outline_rounded
                    : Icons.warning_amber_rounded,
                size: 18,
                color: visibleLowStock == 0
                    ? AppColors.success
                    : AppColors.warning,
              ),
              label: Text('$visibleLowStock low stock'),
              backgroundColor: AppColors.surface,
              labelStyle: Theme.of(
                context,
              ).textTheme.labelLarge?.copyWith(color: AppColors.ink),
            ),
            Chip(
              avatar: const Icon(
                Icons.remove_shopping_cart_outlined,
                size: 18,
                color: AppColors.error,
              ),
              label: Text('$visibleOutOfStock out of stock'),
              backgroundColor: AppColors.surface,
              labelStyle: Theme.of(
                context,
              ).textTheme.labelLarge?.copyWith(color: AppColors.ink),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        if (visibleProducts.length > displayedProducts.length) ...[
          Text(
            'Showing the first ${displayedProducts.length} of ${visibleProducts.length} products. Search to narrow the list.',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: AppColors.inkSecondary),
          ),
          const SizedBox(height: AppSpacing.md),
        ],
        if (visibleProducts.isEmpty)
          KoyasSurface(
            child: EmptyState(
              icon: Icons.inventory_2_outlined,
              title: 'No products in this category',
              message: 'Add the first product to start tracking its stock.',
              action: KoyasButton(
                label: 'Add product',
                expand: false,
                onPressed: () => widget.onAddProduct(selectedCategoryId),
              ),
            ),
          )
        else
          KoyasSurface(
            child: Column(
              children: [
                for (
                  var index = 0;
                  index < displayedProducts.length;
                  index++
                ) ...[
                  _InventoryProductRow(
                    key: Key('admin-product-${displayedProducts[index].id}'),
                    product: displayedProducts[index],
                    busy: _busyProductIds.contains(displayedProducts[index].id),
                    onDecrease: () =>
                        _adjustStock(displayedProducts[index], -1),
                    onIncrease: () => _adjustStock(displayedProducts[index], 1),
                    onSetStock: () =>
                        _showStockEditor(displayedProducts[index]),
                    onEdit: () =>
                        widget.onEditProduct(displayedProducts[index]),
                  ),
                  if (index != displayedProducts.length - 1)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: AppSpacing.md),
                      child: Divider(height: 1),
                    ),
                ],
              ],
            ),
          ),
      ],
    );
  }
}

class _StockEditorDialog extends StatefulWidget {
  const _StockEditorDialog({required this.product});

  final Product product;

  @override
  State<_StockEditorDialog> createState() => _StockEditorDialogState();
}

class _StockEditorDialogState extends State<_StockEditorDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(
      text: '${widget.product.stockQuantity}',
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Set ${widget.product.name} stock'),
      content: SizedBox(
        width: 420,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Enter the total quantity currently available for sale.',
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(color: AppColors.inkSecondary),
              ),
              const SizedBox(height: AppSpacing.lg),
              TextFormField(
                key: const Key('admin-stock-input'),
                controller: _controller,
                autofocus: true,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Stock quantity',
                  prefixIcon: Icon(Icons.inventory_2_outlined),
                ),
                validator: (value) {
                  final parsed = int.tryParse(value?.trim() ?? '');
                  return parsed == null || parsed < 0
                      ? 'Enter zero or a positive whole number'
                      : null;
                },
              ),
              const SizedBox(height: AppSpacing.md),
              Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                children: [
                  ActionChip(
                    label: const Text('Out of stock'),
                    onPressed: () => _controller.text = '0',
                  ),
                  ActionChip(
                    label: const Text('+5 units'),
                    onPressed: () => _controller.text =
                        '${widget.product.stockQuantity + 5}',
                  ),
                  ActionChip(
                    label: const Text('+10 units'),
                    onPressed: () => _controller.text =
                        '${widget.product.stockQuantity + 10}',
                  ),
                ],
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
            Navigator.of(context).pop(int.parse(_controller.text.trim()));
          },
          child: const Text('Update stock'),
        ),
      ],
    );
  }
}

class _InventoryProductRow extends StatelessWidget {
  const _InventoryProductRow({
    required this.product,
    required this.busy,
    required this.onDecrease,
    required this.onIncrease,
    required this.onSetStock,
    required this.onEdit,
    super.key,
  });

  final Product product;
  final bool busy;
  final VoidCallback onDecrease;
  final VoidCallback onIncrease;
  final VoidCallback onSetStock;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final stockColor = product.stockQuantity == 0
        ? AppColors.error
        : product.stockQuantity <= 12
        ? AppColors.warning
        : AppColors.success;
    final stockBackground = product.stockQuantity == 0
        ? AppColors.errorSoft
        : product.stockQuantity <= 12
        ? AppColors.warningSoft
        : AppColors.successSoft;
    final details = Row(
      children: [
        SizedBox(
          width: 44,
          height: 44,
          child: ProductVisual(
            product: product,
            radius: AppRadii.md,
            iconSize: 22,
          ),
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(product.name, style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: AppSpacing.xs),
              Text(
                '${product.unit} · ${formatPrice(product.effectivePricePaise)}',
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: AppColors.inkSecondary),
              ),
              if (product.brand.isNotEmpty ||
                  product.subcategory.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.xs),
                Text(
                  [
                    if (product.brand.isNotEmpty) product.brand,
                    if (product.subcategory.isNotEmpty) product.subcategory,
                  ].join(' · '),
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: AppColors.inkTertiary),
                ),
              ],
              if ((product.billingName.isNotEmpty &&
                      product.billingName != product.name) ||
                  product.itemCode.isNotEmpty ||
                  product.barcode.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.xs),
                Text(
                  [
                    if (product.billingName.isNotEmpty &&
                        product.billingName != product.name)
                      'Billing: ${product.billingName}',
                    if (product.itemCode.isNotEmpty)
                      'Code: ${product.itemCode}',
                    if (product.barcode.isNotEmpty)
                      'Barcode: ${product.barcode}',
                  ].join(' · '),
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: AppColors.inkTertiary),
                ),
              ],
            ],
          ),
        ),
      ],
    );
    final stockBadge = Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: stockBackground,
        borderRadius: BorderRadius.circular(AppRadii.full),
      ),
      child: Text(
        product.stockQuantity == 0
            ? 'Out of stock'
            : '${product.stockQuantity} in stock',
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: stockColor,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
    final controls = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton.outlined(
          key: Key('admin-stock-decrease-${product.id}'),
          tooltip: 'Decrease ${product.name} stock',
          onPressed: busy || product.stockQuantity == 0 ? null : onDecrease,
          icon: const Icon(Icons.remove_rounded),
        ),
        SizedBox(
          width: 42,
          child: busy
              ? const Center(
                  child: SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              : Text(
                  '${product.stockQuantity}',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
        ),
        IconButton.filledTonal(
          key: Key('admin-stock-increase-${product.id}'),
          tooltip: 'Increase ${product.name} stock',
          onPressed: busy ? null : onIncrease,
          icon: const Icon(Icons.add_rounded),
        ),
        const SizedBox(width: AppSpacing.sm),
        TextButton(
          key: Key('admin-stock-set-${product.id}'),
          onPressed: busy ? null : onSetStock,
          child: const Text('Set'),
        ),
      ],
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 680) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(child: details),
                  IconButton(
                    tooltip: 'Edit ${product.name}',
                    onPressed: onEdit,
                    icon: const Icon(Icons.edit_outlined),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              Row(children: [stockBadge, const Spacer(), controls]),
            ],
          );
        }
        return Row(
          children: [
            Expanded(child: details),
            stockBadge,
            const SizedBox(width: AppSpacing.lg),
            controls,
            const SizedBox(width: AppSpacing.sm),
            IconButton(
              tooltip: 'Edit ${product.name}',
              onPressed: onEdit,
              icon: const Icon(Icons.edit_outlined),
            ),
          ],
        );
      },
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return KoyasSurface(
      elevated: true,
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.11),
              borderRadius: BorderRadius.circular(AppRadii.lg),
            ),
            child: Icon(icon, color: color),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(value, style: Theme.of(context).textTheme.titleLarge),
                Text(
                  label,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppColors.inkSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AdminOrderRow extends StatelessWidget {
  const _AdminOrderRow({
    required this.order,
    required this.canAdvance,
    required this.onAdvance,
  });

  final CustomerOrder order;
  final bool canAdvance;
  final VoidCallback onAdvance;

  @override
  Widget build(BuildContext context) {
    return KoyasSurface(
      child: Wrap(
        spacing: AppSpacing.lg,
        runSpacing: AppSpacing.md,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          SizedBox(
            width: 146,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '#${order.displayReference.replaceFirst('KOY', '')}',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                Text(
                  DateFormat('h:mm a').format(order.createdAt),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppColors.inkSecondary,
                  ),
                ),
              ],
            ),
          ),
          SizedBox(
            width: 150,
            child: Text(
              '${order.items.length} items · ${formatPrice(order.totalPaise)}',
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.sm,
            ),
            decoration: BoxDecoration(
              color: order.status.color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(AppRadii.full),
            ),
            child: Text(
              order.status.label,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: order.status.color,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          if (canAdvance)
            FilledButton.tonalIcon(
              onPressed: onAdvance,
              icon: const Icon(Icons.arrow_forward_rounded, size: 18),
              label: Text(
                order.fulfilmentType == FulfilmentType.pickup
                    ? order.status == OrderStatus.readyForPickup
                          ? 'Mark collected'
                          : 'Mark ready for pickup'
                    : 'Advance status',
              ),
            )
          else
            Text(
              'Complete',
              style: Theme.of(
                context,
              ).textTheme.labelLarge?.copyWith(color: AppColors.inkTertiary),
            ),
        ],
      ),
    );
  }
}

class _AdminAnalyticsPanel extends StatelessWidget {
  const _AdminAnalyticsPanel({
    required this.analytics,
    required this.now,
    required this.onPeriodChanged,
  });

  final AdminSalesAnalytics analytics;
  final DateTime now;
  final ValueChanged<AdminAnalyticsPeriod> onPeriodChanged;

  String get _periodLabel => switch (analytics.period) {
    AdminAnalyticsPeriod.daily => DateFormat('EEEE, d MMMM yyyy').format(now),
    AdminAnalyticsPeriod.monthly => DateFormat('MMMM yyyy').format(now),
    AdminAnalyticsPeriod.yearly => DateFormat('yyyy').format(now),
  };

  @override
  Widget build(BuildContext context) {
    final maxQuantity = analytics.topProducts.isEmpty
        ? 1
        : analytics.topProducts.first.quantity;
    return KoyasSurface(
      key: const Key('admin-sales-analytics'),
      elevated: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: AppSpacing.md,
            runSpacing: AppSpacing.md,
            crossAxisAlignment: WrapCrossAlignment.center,
            alignment: WrapAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Sales analytics',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    _periodLabel,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: AppColors.inkSecondary,
                    ),
                  ),
                ],
              ),
              Wrap(
                spacing: AppSpacing.sm,
                children: [
                  for (final period in AdminAnalyticsPeriod.values)
                    ChoiceChip(
                      key: Key('admin-analytics-${period.name}'),
                      label: Text(switch (period) {
                        AdminAnalyticsPeriod.daily => 'Daily',
                        AdminAnalyticsPeriod.monthly => 'Monthly',
                        AdminAnalyticsPeriod.yearly => 'Yearly',
                      }),
                      selected: analytics.period == period,
                      showCheckmark: false,
                      onSelected: (_) => onPeriodChanged(period),
                    ),
                ],
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xxl),
          LayoutBuilder(
            builder: (context, constraints) {
              final columns = constraints.maxWidth >= 850
                  ? 3
                  : constraints.maxWidth >= 500
                  ? 2
                  : 1;
              return GridView.count(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisCount: columns,
                mainAxisSpacing: AppSpacing.md,
                crossAxisSpacing: AppSpacing.md,
                childAspectRatio: columns == 1 ? 3.4 : 2.3,
                children: [
                  _AnalyticsMetric(
                    label: 'Sales value',
                    value: formatPrice(analytics.salesPaise),
                    icon: Icons.payments_outlined,
                    color: AppColors.success,
                  ),
                  _AnalyticsMetric(
                    label: 'Orders',
                    value: '${analytics.orderCount}',
                    icon: Icons.receipt_long_outlined,
                    color: AppColors.info,
                  ),
                  _AnalyticsMetric(
                    label: 'Items sold',
                    value: '${analytics.itemsSold}',
                    icon: Icons.shopping_basket_outlined,
                    color: AppColors.brand600,
                  ),
                  _AnalyticsMetric(
                    label: 'Average order',
                    value: formatPrice(analytics.averageOrderPaise),
                    icon: Icons.calculate_outlined,
                    color: AppColors.brand700,
                  ),
                  _AnalyticsMetric(
                    label: 'Delivery fees',
                    value: formatPrice(analytics.deliveryFeesPaise),
                    icon: Icons.delivery_dining_outlined,
                    color: AppColors.offer,
                  ),
                  _AnalyticsMetric(
                    label: 'Offers given',
                    value: formatPrice(analytics.discountsPaise),
                    icon: Icons.local_offer_outlined,
                    color: AppColors.warning,
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: AppSpacing.lg),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              Chip(
                avatar: const Icon(Icons.storefront_outlined, size: 18),
                label: Text('${analytics.pickupOrders} pickup'),
              ),
              Chip(
                avatar: const Icon(Icons.delivery_dining_outlined, size: 18),
                label: Text('${analytics.deliveryOrders} delivery'),
              ),
              Chip(
                avatar: const Icon(Icons.inventory_2_outlined, size: 18),
                label: Text(
                  '${formatPrice(analytics.productSalesPaise)} product sales',
                ),
              ),
            ],
          ),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: AppSpacing.xxl),
            child: Divider(height: 1),
          ),
          Text(
            'Most ordered products',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Ranked by total quantity ordered during this period.',
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: AppColors.inkSecondary),
          ),
          const SizedBox(height: AppSpacing.lg),
          if (analytics.topProducts.isEmpty)
            Container(
              padding: const EdgeInsets.all(AppSpacing.xxl),
              decoration: BoxDecoration(
                color: AppColors.surfaceMuted,
                borderRadius: BorderRadius.circular(AppRadii.lg),
              ),
              child: const Text(
                'No valid orders were placed during this period.',
                textAlign: TextAlign.center,
              ),
            )
          else
            for (
              var index = 0;
              index < analytics.topProducts.take(10).length;
              index++
            ) ...[
              _TopProductAnalyticsRow(
                key: Key(
                  'admin-top-product-${analytics.topProducts[index].productId.isEmpty ? index : analytics.topProducts[index].productId}',
                ),
                rank: index + 1,
                product: analytics.topProducts[index],
                maxQuantity: maxQuantity,
              ),
              if (index < analytics.topProducts.take(10).length - 1)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: AppSpacing.md),
                  child: Divider(height: 1),
                ),
            ],
        ],
      ),
    );
  }
}

class _AnalyticsMetric extends StatelessWidget {
  const _AnalyticsMetric({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.surfaceMuted,
        borderRadius: BorderRadius.circular(AppRadii.lg),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(AppRadii.md),
            ),
            child: Icon(icon, color: color, size: 22),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppColors.inkSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TopProductAnalyticsRow extends StatelessWidget {
  const _TopProductAnalyticsRow({
    required this.rank,
    required this.product,
    required this.maxQuantity,
    super.key,
  });

  final int rank;
  final AdminProductAnalytics product;
  final int maxQuantity;

  @override
  Widget build(BuildContext context) {
    final orderLabel = product.orderCount == 1 ? 'order' : 'orders';
    return Semantics(
      label:
          'Rank $rank, ${product.name}, ${product.quantity} units across ${product.orderCount} $orderLabel',
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            alignment: Alignment.center,
            decoration: const BoxDecoration(
              color: AppColors.brandSoft,
              shape: BoxShape.circle,
            ),
            child: Text(
              '$rank',
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: AppColors.brand700,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        product.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Text(
                      '${product.quantity} units',
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: AppColors.brand700,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.xs),
                ClipRRect(
                  borderRadius: BorderRadius.circular(AppRadii.full),
                  child: ColoredBox(
                    color: AppColors.surfaceMuted,
                    child: FractionallySizedBox(
                      alignment: Alignment.centerLeft,
                      widthFactor: product.quantity / maxQuantity,
                      child: const SizedBox(
                        height: 7,
                        child: ColoredBox(color: AppColors.brand600),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  '${product.orderCount} $orderLabel · ${product.unit} · ${formatPrice(product.salesPaise)} sales',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppColors.inkSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DeliveryPricingCard extends StatelessWidget {
  const _DeliveryPricingCard({required this.store, required this.onEdit});

  final StoreState store;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final free = store.baseDeliveryChargePaise == 0;
    return KoyasSurface(
      key: const Key('admin-delivery-pricing'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.delivery_dining_rounded),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  'Delivery pricing',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              Chip(
                label: Text(free ? 'Free' : 'Paid'),
                backgroundColor: free
                    ? AppColors.successSoft
                    : AppColors.brandSoft,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            free
                ? 'Free delivery is active for every customer order.'
                : '${formatPrice(store.baseDeliveryChargePaise)} per delivery, free for orders of ${formatPrice(store.freeDeliveryThresholdPaise)} or more.',
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: AppColors.inkSecondary),
          ),
          const SizedBox(height: AppSpacing.lg),
          OutlinedButton.icon(
            key: const Key('admin-edit-delivery-pricing'),
            onPressed: onEdit,
            icon: const Icon(Icons.edit_outlined),
            label: const Text('Change delivery pricing'),
          ),
        ],
      ),
    );
  }
}

class _OfferManagementCard extends StatelessWidget {
  const _OfferManagementCard({
    required this.offers,
    required this.onAdd,
    required this.onManage,
    required this.onEdit,
  });

  final List<Product> offers;
  final VoidCallback onAdd;
  final VoidCallback onManage;
  final ValueChanged<Product> onEdit;

  @override
  Widget build(BuildContext context) {
    return KoyasSurface(
      key: const Key('admin-offers'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.local_offer_outlined),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  'Product offers',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              Chip(label: Text('${offers.length} active')),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            offers.isEmpty
                ? 'No offers are active. Products stay at their regular price until staff creates an offer.'
                : 'Only staff-created offers are shown to customers.',
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: AppColors.inkSecondary),
          ),
          if (offers.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.md),
            for (final product in offers.take(3))
              ListTile(
                key: Key('admin-active-offer-${product.id}'),
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: Text(
                  product.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  '${formatPrice(product.discountPricePaise!)} · ${product.discountPercent}% off',
                ),
                trailing: TextButton(
                  onPressed: () => onEdit(product),
                  child: const Text('Change'),
                ),
              ),
            if (offers.length > 3)
              Text(
                '+${offers.length - 3} more active offers',
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: AppColors.inkSecondary),
              ),
          ],
          const SizedBox(height: AppSpacing.lg),
          if (offers.isNotEmpty) ...[
            OutlinedButton.icon(
              key: const Key('admin-manage-offers'),
              onPressed: onManage,
              icon: const Icon(Icons.tune_rounded),
              label: const Text('Manage active offers'),
            ),
            const SizedBox(height: AppSpacing.sm),
          ],
          FilledButton.tonalIcon(
            key: const Key('admin-add-offer'),
            onPressed: onAdd,
            icon: const Icon(Icons.add_rounded),
            label: const Text('Add an offer'),
          ),
        ],
      ),
    );
  }
}

class _DeliveryPricingDialog extends StatefulWidget {
  const _DeliveryPricingDialog({required this.store});

  final StoreState store;

  @override
  State<_DeliveryPricingDialog> createState() => _DeliveryPricingDialogState();
}

class _DeliveryPricingDialogState extends State<_DeliveryPricingDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _deliveryCharge;
  late final TextEditingController _freeThreshold;
  late bool _freeDelivery;

  @override
  void initState() {
    super.initState();
    _freeDelivery = widget.store.baseDeliveryChargePaise == 0;
    _deliveryCharge = TextEditingController(
      text: (widget.store.baseDeliveryChargePaise / 100).toStringAsFixed(2),
    );
    _freeThreshold = TextEditingController(
      text: (widget.store.freeDeliveryThresholdPaise / 100).toStringAsFixed(2),
    );
  }

  @override
  void dispose() {
    _deliveryCharge.dispose();
    _freeThreshold.dispose();
    super.dispose();
  }

  int? _paise(String value) {
    final amount = double.tryParse(value.trim());
    return amount == null || !amount.isFinite ? null : (amount * 100).round();
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.of(context).pop(
      _DeliveryPricingResult(
        deliveryChargePaise: _freeDelivery ? 0 : _paise(_deliveryCharge.text)!,
        freeDeliveryThresholdPaise: _freeDelivery
            ? widget.store.freeDeliveryThresholdPaise
            : _paise(_freeThreshold.text)!,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Delivery pricing'),
      content: SizedBox(
        width: 500,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Choose free delivery or set the exact amount charged at checkout.',
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(color: AppColors.inkSecondary),
              ),
              const SizedBox(height: AppSpacing.md),
              SwitchListTile.adaptive(
                key: const Key('admin-free-delivery'),
                contentPadding: EdgeInsets.zero,
                value: _freeDelivery,
                onChanged: (value) => setState(() => _freeDelivery = value),
                title: const Text('Free delivery'),
                subtitle: const Text('Customers will not pay a delivery fee.'),
              ),
              if (!_freeDelivery) ...[
                const SizedBox(height: AppSpacing.md),
                TextFormField(
                  key: const Key('admin-delivery-charge'),
                  controller: _deliveryCharge,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Delivery charge (₹)',
                    prefixIcon: Icon(Icons.currency_rupee_rounded),
                  ),
                  validator: (value) {
                    final amount = _paise(value ?? '');
                    return amount == null || amount <= 0 || amount > 1000000
                        ? 'Enter an amount from ₹0.01 to ₹10,000'
                        : null;
                  },
                ),
                const SizedBox(height: AppSpacing.md),
                TextFormField(
                  key: const Key('admin-free-delivery-threshold'),
                  controller: _freeThreshold,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Free delivery above (₹)',
                    helperText:
                        'Orders at or above this amount will have free delivery.',
                    prefixIcon: Icon(Icons.redeem_outlined),
                  ),
                  validator: (value) {
                    final amount = _paise(value ?? '');
                    return amount == null || amount <= 0 || amount > 100000000
                        ? 'Enter a valid order amount'
                        : null;
                  },
                ),
              ],
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
          key: const Key('admin-save-delivery-pricing'),
          onPressed: _save,
          child: const Text('Save pricing'),
        ),
      ],
    );
  }
}

class _OfferProductPickerDialog extends StatefulWidget {
  const _OfferProductPickerDialog({required this.products});

  final List<Product> products;

  @override
  State<_OfferProductPickerDialog> createState() =>
      _OfferProductPickerDialogState();
}

class _OfferProductPickerDialogState extends State<_OfferProductPickerDialog> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final matches = ProductSearch.search(
      products: widget.products,
      query: _query,
    ).take(80).toList(growable: false);
    return AlertDialog(
      title: const Text('Choose a product'),
      content: SizedBox(
        width: 620,
        height: 520,
        child: Column(
          children: [
            TextField(
              key: const Key('admin-offer-product-search'),
              autofocus: true,
              onChanged: (value) => setState(() => _query = value),
              decoration: const InputDecoration(
                labelText: 'Search products',
                prefixIcon: Icon(Icons.search_rounded),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Expanded(
              child: matches.isEmpty
                  ? const Center(
                      child: Text('No products are available for a new offer.'),
                    )
                  : ListView.separated(
                      itemCount: matches.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final product = matches[index];
                        return ListTile(
                          key: Key('admin-offer-product-${product.id}'),
                          title: Text(product.name),
                          subtitle: Text(
                            '${product.unit} · ${formatPrice(product.pricePaise)}',
                          ),
                          trailing: const Icon(Icons.chevron_right_rounded),
                          onTap: () => Navigator.of(context).pop(product),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
      ],
    );
  }
}

class _OfferEditorDialog extends StatefulWidget {
  const _OfferEditorDialog({required this.product});

  final Product product;

  @override
  State<_OfferEditorDialog> createState() => _OfferEditorDialogState();
}

class _OfferEditorDialogState extends State<_OfferEditorDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _offerPrice;

  @override
  void initState() {
    super.initState();
    _offerPrice = TextEditingController(
      text: widget.product.discountPricePaise == null
          ? ''
          : (widget.product.discountPricePaise! / 100).toStringAsFixed(2),
    );
  }

  @override
  void dispose() {
    _offerPrice.dispose();
    super.dispose();
  }

  int? _paise(String value) {
    final amount = double.tryParse(value.trim());
    return amount == null || !amount.isFinite ? null : (amount * 100).round();
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.of(context).pop(
      widget.product.copyWith(discountPricePaise: _paise(_offerPrice.text)!),
    );
  }

  @override
  Widget build(BuildContext context) {
    final parsed = _paise(_offerPrice.text);
    final percent =
        parsed == null || parsed <= 0 || parsed >= widget.product.pricePaise
        ? null
        : ((widget.product.pricePaise - parsed) *
                  100 /
                  widget.product.pricePaise)
              .round();
    return AlertDialog(
      title: Text(
        widget.product.discountPricePaise == null
            ? 'Create product offer'
            : 'Change product offer',
      ),
      content: SizedBox(
        width: 480,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                widget.product.name,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                'Regular price: ${formatPrice(widget.product.pricePaise)}',
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(color: AppColors.inkSecondary),
              ),
              const SizedBox(height: AppSpacing.lg),
              TextFormField(
                key: const Key('admin-offer-price'),
                controller: _offerPrice,
                autofocus: true,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  labelText: 'Customer offer price (₹)',
                  prefixIcon: Icon(Icons.local_offer_outlined),
                ),
                validator: (value) {
                  final amount = _paise(value ?? '');
                  return amount == null ||
                          amount <= 0 ||
                          amount >= widget.product.pricePaise
                      ? 'Enter an offer below the regular price'
                      : null;
                },
              ),
              if (percent != null) ...[
                const SizedBox(height: AppSpacing.md),
                Text(
                  'Customers will see $percent% OFF and pay ${formatPrice(parsed!)}.',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AppColors.success,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        if (widget.product.discountPricePaise != null)
          TextButton(
            key: const Key('admin-remove-offer'),
            onPressed: () => Navigator.of(
              context,
            ).pop(widget.product.copyWith(clearDiscount: true)),
            child: const Text('Remove offer'),
          ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const Key('admin-save-offer'),
          onPressed: _save,
          child: const Text('Save offer'),
        ),
      ],
    );
  }
}

class _ProductEditorDialog extends StatefulWidget {
  const _ProductEditorDialog({
    required this.product,
    required this.categories,
    this.initialCategoryId,
  });

  final Product? product;
  final List<ProductCategory> categories;
  final String? initialCategoryId;

  @override
  State<_ProductEditorDialog> createState() => _ProductEditorDialogState();
}

class _ProductEditorDialogState extends State<_ProductEditorDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _brand;
  late final TextEditingController _subcategory;
  late final TextEditingController _description;
  late final TextEditingController _unit;
  late final TextEditingController _price;
  late final TextEditingController _discount;
  late final TextEditingController _stock;
  late String _categoryId;
  late bool _featured;
  ProductImageUpload? _selectedImage;
  String? _imageError;
  bool _pickingImage = false;

  @override
  void initState() {
    super.initState();
    final product = widget.product;
    _name = TextEditingController(text: product?.name ?? '');
    _brand = TextEditingController(text: product?.brand ?? '');
    _subcategory = TextEditingController(text: product?.subcategory ?? '');
    _description = TextEditingController(text: product?.description ?? '');
    _unit = TextEditingController(text: product?.unit ?? '1 pack');
    _price = TextEditingController(
      text: product == null
          ? ''
          : (product.pricePaise / 100).toStringAsFixed(2),
    );
    _discount = TextEditingController(
      text: product?.discountPricePaise == null
          ? ''
          : (product!.discountPricePaise! / 100).toStringAsFixed(2),
    );
    _stock = TextEditingController(text: '${product?.stockQuantity ?? 0}');
    final hasInitialCategory = widget.categories.any(
      (category) => category.id == widget.initialCategoryId,
    );
    _categoryId =
        product?.categoryId ??
        (hasInitialCategory
            ? widget.initialCategoryId!
            : widget.categories.first.id);
    _featured = product?.featured ?? false;
  }

  @override
  void dispose() {
    _name.dispose();
    _brand.dispose();
    _subcategory.dispose();
    _description.dispose();
    _unit.dispose();
    _price.dispose();
    _discount.dispose();
    _stock.dispose();
    super.dispose();
  }

  String? _required(String? value) =>
      value == null || value.trim().isEmpty ? 'This field is required' : null;

  String? _requiredLength(String? value, {required int min, required int max}) {
    final requiredError = _required(value);
    if (requiredError != null) return requiredError;
    final length = value!.trim().length;
    if (length < min) return 'Enter at least $min characters';
    if (length > max) return 'Use $max characters or fewer';
    return null;
  }

  String? _optionalLength(String? value, int max) {
    if ((value?.trim().length ?? 0) > max) {
      return 'Use $max characters or fewer';
    }
    return null;
  }

  int? _paise(String value) {
    final amount = double.tryParse(value.trim());
    return amount == null || !amount.isFinite ? null : (amount * 100).round();
  }

  Future<void> _pickImage() async {
    if (_pickingImage) return;
    setState(() {
      _pickingImage = true;
      _imageError = null;
    });
    try {
      final result = await FilePicker.pickFiles(
        dialogTitle: 'Choose a product image',
        type: FileType.custom,
        allowedExtensions: const ['jpg', 'jpeg', 'png', 'webp'],
        withData: true,
      );
      if (result == null || result.files.isEmpty) return;
      final file = result.files.single;
      final bytes = file.bytes ?? await file.xFile.readAsBytes();
      final upload = ProductImageUpload.fromBytes(
        bytes: bytes,
        fileName: file.name,
      );
      if (mounted) setState(() => _selectedImage = upload);
    } on FormatException catch (error) {
      if (mounted) setState(() => _imageError = error.message.toString());
    } catch (_) {
      if (mounted) {
        setState(() => _imageError = 'The image could not be opened.');
      }
    } finally {
      if (mounted) setState(() => _pickingImage = false);
    }
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;
    final price = _paise(_price.text)!;
    final discount = _discount.text.trim().isEmpty
        ? null
        : _paise(_discount.text);
    final category = widget.categories.firstWhere(
      (item) => item.id == _categoryId,
    );
    final existing = widget.product;
    Navigator.of(context).pop(
      _ProductEditorResult(
        image: _selectedImage,
        product: Product(
          id:
              existing?.id ??
              'product-${DateTime.now().millisecondsSinceEpoch}',
          categoryId: _categoryId,
          name: _name.text.trim(),
          brand: _brand.text.trim(),
          subcategory: _subcategory.text.trim(),
          billingName: existing?.billingName ?? _name.text.trim(),
          printName: existing?.printName ?? _name.text.trim(),
          itemCode: existing?.itemCode ?? '',
          barcode: existing?.barcode ?? '',
          imageAttribution: _selectedImage == null
              ? existing?.imageAttribution ?? ''
              : '',
          imageAsset: existing?.imageAsset ?? '',
          imagePath: existing?.imagePath ?? '',
          imageBytes: _selectedImage?.bytes ?? existing?.imageBytes,
          description: _description.text.trim(),
          unit: _unit.text.trim(),
          pricePaise: price,
          discountPricePaise: discount,
          stockQuantity: int.parse(_stock.text.trim()),
          visualKey: category.visualKey,
          imageUrl: existing?.imageUrl,
          featured: _featured,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.product == null ? 'Add product' : 'Edit product'),
      content: SizedBox(
        width: 560,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  key: const Key('admin-product-image-preview'),
                  width: double.infinity,
                  height: 180,
                  decoration: BoxDecoration(
                    color: AppColors.canvas,
                    borderRadius: BorderRadius.circular(AppRadii.lg),
                    border: Border.all(color: AppColors.outline),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: _selectedImage != null
                      ? Image.memory(_selectedImage!.bytes, fit: BoxFit.contain)
                      : widget.product != null
                      ? ProductVisual(product: widget.product!)
                      : const Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.add_photo_alternate_outlined,
                                size: 40,
                              ),
                              SizedBox(height: AppSpacing.sm),
                              Text('No product picture selected'),
                            ],
                          ),
                        ),
                ),
                const SizedBox(height: AppSpacing.sm),
                Align(
                  alignment: Alignment.centerLeft,
                  child: OutlinedButton.icon(
                    key: const Key('admin-pick-product-image'),
                    onPressed: _pickingImage ? null : _pickImage,
                    icon: _pickingImage
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.photo_library_outlined),
                    label: Text(
                      _selectedImage != null ||
                              widget.product?.imageUrl?.isNotEmpty == true ||
                              widget.product?.imageAsset.isNotEmpty == true
                          ? 'Replace picture'
                          : 'Add picture',
                    ),
                  ),
                ),
                if (_selectedImage != null) ...[
                  const SizedBox(height: AppSpacing.xs),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      '${_selectedImage!.fileName} · ${(_selectedImage!.bytes.length / 1024).ceil()} KB',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppColors.inkSecondary,
                      ),
                    ),
                  ),
                ],
                if (_imageError != null) ...[
                  const SizedBox(height: AppSpacing.xs),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      _imageError!,
                      style: Theme.of(
                        context,
                      ).textTheme.bodySmall?.copyWith(color: AppColors.error),
                    ),
                  ),
                ],
                const SizedBox(height: AppSpacing.md),
                TextFormField(
                  controller: _name,
                  validator: (value) =>
                      _requiredLength(value, min: 2, max: 200),
                  decoration: const InputDecoration(labelText: 'Product name'),
                ),
                const SizedBox(height: AppSpacing.md),
                DropdownButtonFormField<String>(
                  value: _categoryId,
                  decoration: const InputDecoration(labelText: 'Category'),
                  items: widget.categories
                      .map(
                        (category) => DropdownMenuItem(
                          value: category.id,
                          child: Text(category.name),
                        ),
                      )
                      .toList(),
                  onChanged: (value) {
                    if (value != null) setState(() => _categoryId = value);
                  },
                ),
                const SizedBox(height: AppSpacing.md),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _brand,
                        validator: (value) => _optionalLength(value, 120),
                        decoration: const InputDecoration(labelText: 'Brand'),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: TextFormField(
                        controller: _subcategory,
                        validator: (value) => _optionalLength(value, 120),
                        decoration: const InputDecoration(
                          labelText: 'Subcategory',
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
                TextFormField(
                  controller: _description,
                  validator: (value) =>
                      _requiredLength(value, min: 2, max: 2000),
                  maxLines: 2,
                  decoration: const InputDecoration(labelText: 'Description'),
                ),
                const SizedBox(height: AppSpacing.md),
                TextFormField(
                  controller: _unit,
                  validator: (value) => _requiredLength(value, min: 1, max: 80),
                  decoration: const InputDecoration(
                    labelText: 'Unit',
                    hintText: '1 kg, 500 ml, 12 pieces',
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _price,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        validator: (value) {
                          final amount = _paise(value ?? '');
                          return amount == null ||
                                  amount <= 0 ||
                                  amount > 100000000
                              ? 'Enter a valid price'
                              : null;
                        },
                        decoration: const InputDecoration(
                          labelText: 'Price (₹)',
                        ),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: TextFormField(
                        controller: _discount,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return null;
                          }
                          final discount = _paise(value);
                          final price = _paise(_price.text);
                          return discount == null ||
                                  discount <= 0 ||
                                  price == null ||
                                  discount >= price
                              ? 'Must be below price'
                              : null;
                        },
                        decoration: const InputDecoration(
                          labelText: 'Offer price (₹, optional)',
                          helperText:
                              'Leave empty to sell at the regular price.',
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
                TextFormField(
                  controller: _stock,
                  keyboardType: TextInputType.number,
                  validator: (value) {
                    final stock = int.tryParse(value ?? '');
                    return stock == null || stock < 0 || stock > 999999
                        ? 'Enter a valid stock quantity'
                        : null;
                  },
                  decoration: const InputDecoration(
                    labelText: 'Stock quantity',
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  value: _featured,
                  onChanged: (value) => setState(() => _featured = value),
                  title: const Text('Featured on home'),
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
        FilledButton(onPressed: _save, child: const Text('Save product')),
      ],
    );
  }
}

class _ProductEditorResult {
  const _ProductEditorResult({required this.product, this.image});

  final Product product;
  final ProductImageUpload? image;
}

class _DeliveryPricingResult {
  const _DeliveryPricingResult({
    required this.deliveryChargePaise,
    required this.freeDeliveryThresholdPaise,
  });

  final int deliveryChargePaise;
  final int freeDeliveryThresholdPaise;
}
