import '../../checkout/widgets/delivery_pin_summary.dart';
import '../../../core/widgets/four_dot_loader.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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
import '../../offers/models/store_offer.dart';
import '../analytics/admin_sales_analytics.dart';
import '../widgets/stock_quantity_editor.dart';
import '../widgets/staff_order_alert_bar.dart';
import '../printing/order_bill_printer.dart';
import '../widgets/resource_usage_button.dart';
import '../../orders/models/order.dart';
import '../../orders/widgets/order_status_ui.dart';
import '../../products/models/category.dart';
import '../../products/models/product.dart';
import '../../products/models/product_image_upload.dart';
import '../../products/product_search.dart';
import '../../products/services/product_image_picker.dart';
import '../../products/widgets/category_tile.dart';
import '../../products/widgets/product_visual.dart';
import '../../store/data/supabase_store_repository.dart';
import '../../store/providers/store_provider.dart';
import '../../store/widgets/store_realtime_sync.dart';

enum AdminSection { overview, analytics, pricing, orders, inventory }

String _inventoryError(Object error, String fallback) {
  if (error is StoreValidationException) return error.message;
  if (error is PostgrestException && error.code == 'PT409') {
    return 'These details changed while you were editing. Refresh and try again.';
  }
  return fallback;
}

extension _AdminPaymentStatusUi on PaymentStatus {
  String get adminLabel => switch (this) {
    PaymentStatus.pending => 'Payment pending',
    PaymentStatus.paid => 'Payment received',
    PaymentStatus.failed => 'Payment failed',
    PaymentStatus.cancelled => 'Payment cancelled',
  };

  Color get adminColor => switch (this) {
    PaymentStatus.pending => AppColors.warning,
    PaymentStatus.paid => AppColors.success,
    PaymentStatus.failed || PaymentStatus.cancelled => AppColors.error,
  };
}

extension AdminSectionUi on AdminSection {
  String get path => switch (this) {
    AdminSection.overview => '/dashboard',
    AdminSection.analytics => '/analytics',
    AdminSection.pricing => '/pricing',
    AdminSection.orders => '/orders',
    AdminSection.inventory => '/inventory',
  };

  String get title => switch (this) {
    AdminSection.overview => 'Store dashboard',
    AdminSection.analytics => 'Sales analytics',
    AdminSection.pricing => 'Order pricing & offers',
    AdminSection.orders => 'Order queue',
    AdminSection.inventory => 'Inventory',
  };

  String get navigationLabel => switch (this) {
    AdminSection.overview => 'Overview',
    AdminSection.analytics => 'Analytics',
    AdminSection.pricing => 'Pricing',
    AdminSection.orders => 'Orders',
    AdminSection.inventory => 'Inventory',
  };

  String get description => switch (this) {
    AdminSection.overview =>
      'A quick view of today’s orders, revenue, and stock health.',
    AdminSection.analytics =>
      'Review sales performance and the products customers order most.',
    AdminSection.pricing =>
      'Control minimum ordering, delivery charges, and product offers.',
    AdminSection.orders =>
      'Review fulfilment queues and advance customer order statuses.',
    AdminSection.inventory =>
      'Search products, update physical stock, and manage the catalogue.',
  };

  IconData get icon => switch (this) {
    AdminSection.overview => Icons.dashboard_outlined,
    AdminSection.analytics => Icons.analytics_outlined,
    AdminSection.pricing => Icons.local_offer_outlined,
    AdminSection.orders => Icons.receipt_long_outlined,
    AdminSection.inventory => Icons.inventory_2_outlined,
  };

  IconData get selectedIcon => switch (this) {
    AdminSection.overview => Icons.dashboard_rounded,
    AdminSection.analytics => Icons.analytics_rounded,
    AdminSection.pricing => Icons.local_offer_rounded,
    AdminSection.orders => Icons.receipt_long_rounded,
    AdminSection.inventory => Icons.inventory_2_rounded,
  };

  String get keyName => 'admin-nav-${name.toLowerCase()}';
}

class AdminDashboardScreen extends ConsumerStatefulWidget {
  const AdminDashboardScreen({
    this.section = AdminSection.overview,
    this.manageLiveSync = true,
    this.orderFocusKey,
    super.key,
  });

  final AdminSection section;
  final bool manageLiveSync;
  final String? orderFocusKey;

  @override
  ConsumerState<AdminDashboardScreen> createState() =>
      _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends ConsumerState<AdminDashboardScreen> {
  String _filter = 'Active';
  AdminAnalyticsPeriod _analyticsPeriod = AdminAnalyticsPeriod.daily;
  bool _refreshing = false;

  @override
  void didUpdateWidget(covariant AdminDashboardScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.orderFocusKey != null &&
        widget.orderFocusKey != oldWidget.orderFocusKey) {
      _filter = 'Active';
    }
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
              DateUtils.isSameDay(
                order.paidAt ?? order.createdAt,
                DateTime.now(),
              ),
        )
        .fold<int>(0, (sum, order) => sum + order.totalPaise);
    final lowStock = store.products
        .where(
          (product) =>
              product.active &&
              product.stockQuantity > 0 &&
              product.stockQuantity <= 12,
        )
        .toList(growable: false);
    final outOfStockCount = store.products
        .where((product) => product.active && product.stockQuantity == 0)
        .length;
    void selectSection(AdminSection section) {
      if (section != widget.section) context.go(section.path);
    }

    final dashboard = LayoutBuilder(
      builder: (context, constraints) {
        final desktop = constraints.maxWidth >= 980;
        final content = _DashboardContent(
          section: widget.section,
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
        return Scaffold(
          backgroundColor: AppColors.canvas,
          body: SafeArea(
            child: desktop
                ? Row(
                    children: [
                      _AdminSidebar(
                        selected: widget.section,
                        onSelected: selectSection,
                      ),
                      const VerticalDivider(width: 1),
                      Expanded(child: content),
                    ],
                  )
                : content,
          ),
          bottomNavigationBar: desktop
              ? null
              : _AdminBottomNavigation(
                  selected: widget.section,
                  onSelected: selectSection,
                ),
        );
      },
    );
    return widget.manageLiveSync
        ? StoreRealtimeSync(child: dashboard)
        : dashboard;
  }
}

class _AdminSidebar extends StatelessWidget {
  const _AdminSidebar({required this.selected, required this.onSelected});

  final AdminSection selected;
  final ValueChanged<AdminSection> onSelected;

  @override
  Widget build(BuildContext context) {
    return NavigationRail(
      key: const Key('admin-side-navigation'),
      extended: true,
      minExtendedWidth: 248,
      selectedIndex: selected.index,
      onDestinationSelected: (index) => onSelected(AdminSection.values[index]),
      leading: const Padding(
        padding: EdgeInsets.fromLTRB(
          AppSpacing.xl,
          AppSpacing.lg,
          AppSpacing.xl,
          AppSpacing.xxxl,
        ),
        child: KoyasLogo(compact: true),
      ),
      destinations: [
        for (final section in AdminSection.values)
          NavigationRailDestination(
            icon: Icon(section.icon, key: Key(section.keyName)),
            selectedIcon: Icon(
              section.selectedIcon,
              key: Key('${section.keyName}-selected'),
            ),
            label: Text(section.navigationLabel),
          ),
      ],
    );
  }
}

class _AdminBottomNavigation extends StatelessWidget {
  const _AdminBottomNavigation({
    required this.selected,
    required this.onSelected,
  });

  final AdminSection selected;
  final ValueChanged<AdminSection> onSelected;

  @override
  Widget build(BuildContext context) {
    final compactLabels =
        MediaQuery.sizeOf(context).width < 360 &&
        MediaQuery.textScalerOf(context).scale(12) > 14;
    return NavigationBar(
      key: const Key('admin-bottom-navigation'),
      selectedIndex: selected.index,
      labelBehavior: compactLabels
          ? NavigationDestinationLabelBehavior.alwaysHide
          : NavigationDestinationLabelBehavior.onlyShowSelected,
      onDestinationSelected: (index) => onSelected(AdminSection.values[index]),
      destinations: [
        for (final section in AdminSection.values)
          NavigationDestination(
            key: Key(section.keyName),
            icon: Icon(section.icon),
            selectedIcon: Icon(section.selectedIcon),
            label: section.navigationLabel,
          ),
      ],
    );
  }
}

class _DashboardContent extends ConsumerWidget {
  const _DashboardContent({
    required this.section,
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

  final AdminSection section;
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
              (order.paidAt ?? order.createdAt).year == now.year &&
              (order.paidAt ?? order.createdAt).month == now.month,
        )
        .fold<int>(0, (sum, order) => sum + order.totalPaise);
    final sectionBody = switch (section) {
      AdminSection.overview => _OverviewSection(
        ordersToday: ordersToday,
        activeCount: activeCount,
        todayRevenue: todayRevenue,
        pickupOrders: pickupOrders,
        completedOrders: completedOrders,
        monthRevenue: monthRevenue,
        lowStockCount: lowStockCount,
        outOfStockCount: outOfStockCount,
      ),
      AdminSection.analytics => _AdminAnalyticsPanel(
        analytics: AdminSalesAnalyticsCalculator.calculate(
          orders: store.orders,
          period: analyticsPeriod,
          now: now,
        ),
        now: now,
        onPeriodChanged: onAnalyticsPeriodChanged,
      ),
      AdminSection.pricing => _PricingSection(
        store: store,
        cartOffers: store.offers,
        activeOffers: store.products
            .where(
              (product) => product.active && product.discountPricePaise != null,
            )
            .toList(growable: false),
        onEditPricing: () => _editOrderPricing(context, ref),
        onAddOffer: () => _addOffer(context, ref),
        onManageOffer: () => _manageOffer(context, ref),
        onEditOffer: (product) => _editOffer(context, ref, product),
        onAddCartOffer: () => _editCartOffer(context, ref),
        onEditCartOffer: (offer) => _editCartOffer(context, ref, offer: offer),
      ),
      AdminSection.orders => _OrdersSection(
        visibleOrders: visibleOrders,
        filter: filter,
        onFilterChanged: onFilterChanged,
        terminal: terminal,
        onAdvance: (order) => _advanceOrder(context, ref, order),
        onReject: (order) =>
            _closeOrder(context, ref, order, nextStatus: OrderStatus.rejected),
        onCancel: (order) =>
            _closeOrder(context, ref, order, nextStatus: OrderStatus.cancelled),
        onMarkPaid: (order) => _markPaymentReceived(context, ref, order),
      ),
      AdminSection.inventory => _CategoryInventory(
        categories: store.categories,
        products: store.products,
        onAddProduct: (categoryId) =>
            _editProduct(context, ref, initialCategoryId: categoryId),
        onEditProduct: (product) =>
            _editProduct(context, ref, product: product),
        onProductActiveChanged: (product, active) =>
            _setProductActive(context, ref, product, active),
        onStockChanged: (product, quantity) =>
            _updateStock(context, ref, product, quantity),
        onStockAdjusted: (product, delta) =>
            _adjustStock(context, ref, product, delta),
      ),
    };
    return CustomScrollView(
      key: PageStorageKey<String>('admin-section-${section.name}'),
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
                          section.title,
                          style: Theme.of(context).textTheme.headlineLarge,
                        ),
                        const SizedBox(height: AppSpacing.xs),
                        Text(
                          section == AdminSection.overview
                              ? '${section.description} ${DateFormat('EEEE, d MMMM').format(now)}.'
                              : section.description,
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(color: AppColors.inkSecondary),
                        ),
                      ],
                    ),
                  ),
                  if (onRefresh != null) ...[
                    IconButton(
                      tooltip: 'Refresh orders and inventory',
                      onPressed: refreshing ? null : onRefresh,
                      icon: refreshing
                          ? const SizedBox.square(
                              dimension: 20,
                              child: FourDotLoader(size: 22),
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
              if (AppEnvironment.hasSupabaseConfig)
                const Align(
                  alignment: Alignment.centerLeft,
                  child: ResourceUsageButton(),
                ),
              const SizedBox(height: AppSpacing.md),
              StaffOrderAlertBar(
                onOpenOrders: () => context.go(
                  '/orders?focus=${DateTime.now().microsecondsSinceEpoch}',
                ),
              ),
              const SizedBox(height: AppSpacing.xxxl),
              KeyedSubtree(
                key: ValueKey<AdminSection>(section),
                child: sectionBody,
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
        await repository.saveProduct(
          updated,
          image: result.image,
          removeImage: result.removeImage,
        );
        if (context.mounted) {
          if (context.mounted) {
            await _refreshSavedInventory(context, ref, repository);
          }
        }
      } else {
        ref
            .read(storeProvider.notifier)
            .adminSaveProduct(
              result.removeImage ? updated.copyWith(clearImage: true) : updated,
            );
      }
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _inventoryError(
                error,
                'Product save was not confirmed. Refresh inventory before trying again.',
              ),
            ),
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

  Future<void> _setProductActive(
    BuildContext context,
    WidgetRef ref,
    Product product,
    bool active,
  ) async {
    if (!active) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text('Archive ${product.name}?'),
          content: const Text(
            'Archived products disappear from the customer catalogue but keep '
            'their order history and can be restored later.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              key: const Key('admin-confirm-archive-product'),
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Archive product'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
    }

    final updated = product.copyWith(active: active, available: active);
    try {
      if (AppEnvironment.hasSupabaseConfig) {
        final repository = SupabaseStoreRepository();
        await repository.saveProduct(updated);
        if (context.mounted) {
          if (context.mounted) {
            await _refreshSavedInventory(context, ref, repository);
          }
        }
      } else {
        ref.read(storeProvider.notifier).adminSaveProduct(updated);
      }
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _inventoryError(
                error,
                active
                    ? 'Product could not be restored.'
                    : 'Product could not be archived.',
              ),
            ),
          ),
        );
      }
      return;
    }
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(active ? 'Product restored.' : 'Product archived.'),
        ),
      );
    }
  }

  Future<void> _editOrderPricing(BuildContext context, WidgetRef ref) async {
    final expectedRevision = store.settingsRevision;
    final result = await showDialog<_OrderPricingResult>(
      context: context,
      builder: (context) => _OrderPricingDialog(store: store),
    );
    if (result == null) return;
    try {
      if (AppEnvironment.hasSupabaseConfig) {
        final repository = SupabaseStoreRepository();
        await repository.updateOrderPricing(
          expectedRevision: expectedRevision,
          minimumOrderPaise: result.minimumOrderPaise,
          deliveryChargePaise: result.deliveryChargePaise,
          freeDeliveryThresholdPaise: result.freeDeliveryThresholdPaise,
        );
        if (context.mounted) {
          await _refreshSavedInventory(context, ref, repository);
        }
      } else {
        ref
            .read(storeProvider.notifier)
            .adminUpdateOrderPricing(
              expectedRevision: expectedRevision,
              minimumOrderPaise: result.minimumOrderPaise,
              deliveryChargePaise: result.deliveryChargePaise,
              freeDeliveryThresholdPaise: result.freeDeliveryThresholdPaise,
            );
      }
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _inventoryError(
                error,
                'Pricing save was not confirmed. Refresh before retrying.',
              ),
            ),
          ),
        );
      }
      return;
    }
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result.minimumOrderPaise == 0
                ? 'Order pricing updated. There is no minimum order.'
                : 'Order pricing updated.',
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
        if (context.mounted) {
          if (context.mounted) {
            await _refreshSavedInventory(context, ref, repository);
          }
        }
      } else {
        ref.read(storeProvider.notifier).adminSaveProduct(updated);
      }
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_inventoryError(error, 'Offer could not be saved.')),
          ),
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

  Future<void> _editCartOffer(
    BuildContext context,
    WidgetRef ref, {
    StoreOffer? offer,
  }) async {
    final saved = await showDialog<StoreOffer>(
      context: context,
      builder: (context) => _CartOfferEditorDialog(
        offer: offer,
        products: store.products.where((product) => product.active).toList(),
      ),
    );
    if (saved == null) return;
    try {
      if (AppEnvironment.hasSupabaseConfig) {
        final repository = SupabaseStoreRepository();
        await repository.saveOffer(saved);
        if (context.mounted) {
          await _refreshSavedInventory(context, ref, repository);
        }
      } else {
        ref.read(storeProvider.notifier).adminSaveOffer(saved);
      }
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _inventoryError(
                error,
                'Offer save was not confirmed. Refresh before retrying.',
              ),
            ),
          ),
        );
      }
      return;
    }
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            saved.active
                ? 'Offer ${saved.code} is active.'
                : 'Offer ${saved.code} is disabled.',
          ),
        ),
      );
    }
  }

  Future<bool> _updateStock(
    BuildContext context,
    WidgetRef ref,
    Product product,
    int quantity,
  ) => _persistStock(context, ref, product, requestedQuantity: quantity);

  Future<bool> _adjustStock(
    BuildContext context,
    WidgetRef ref,
    Product product,
    int delta,
  ) => _persistStock(context, ref, product, adjustment: delta);

  Future<bool> _persistStock(
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
            ? await repository.setProductStock(
                product.id,
                requestedQuantity,
                expectedRevision: product.revision,
              )
            : await repository.adjustProductStock(product.id, adjustment!);
        if (context.mounted) {
          await _refreshSavedInventory(context, ref, repository);
        }
      } else {
        final current =
            ref.read(storeProvider).productById(product.id) ?? product;
        savedQuantity =
            requestedQuantity ??
            (current.stockQuantity + adjustment!).clamp(0, 999999).toInt();
        // Deltas apply to current state; exact counts retain the editor's revision.
        final updated = (requestedQuantity == null ? current : product)
            .copyWith(stockQuantity: savedQuantity);
        ref.read(storeProvider.notifier).adminSaveProduct(updated);
      }
      if (context.mounted && requestedQuantity != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${product.name} stock set to $savedQuantity.'),
            duration: const Duration(seconds: 2),
          ),
        );
      }
      return true;
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _inventoryError(
                error,
                '${product.name} stock update was not confirmed. Refresh inventory before retrying.',
              ),
            ),
          ),
        );
      }
      return false;
    }
  }

  Future<void> _refreshSavedInventory(
    BuildContext context,
    WidgetRef ref,
    SupabaseStoreRepository repository,
  ) async {
    try {
      final bundle = await repository.loadStore();
      if (context.mounted &&
          ref.read(storeProvider).profile?.id == bundle.profile.id) {
        ref.read(storeProvider.notifier).hydrateRemoteBundle(bundle);
      }
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Change saved. Store details could not refresh; refresh before making another edit.',
            ),
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
        if (context.mounted) {
          await _refreshSavedInventory(context, ref, repository);
        }
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

  Future<void> _closeOrder(
    BuildContext context,
    WidgetRef ref,
    CustomerOrder order, {
    required OrderStatus nextStatus,
  }) async {
    final rejecting = nextStatus == OrderStatus.rejected;
    final action = rejecting ? 'Reject' : 'Cancel';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('$action order?'),
        content: Text(
          '$action ${order.displayReference}? Reserved stock will be returned to inventory.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Keep order'),
          ),
          FilledButton(
            key: Key(
              rejecting
                  ? 'admin-confirm-reject-${order.id}'
                  : 'admin-confirm-cancel-${order.id}',
            ),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(action),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    try {
      if (AppEnvironment.hasSupabaseConfig) {
        final repository = SupabaseStoreRepository();
        if (rejecting) {
          await repository.rejectOrder(order.id);
        } else {
          await repository.cancelOrderByAdmin(order.id);
        }
        if (context.mounted) {
          await _refreshSavedInventory(context, ref, repository);
        }
      } else if (rejecting) {
        ref.read(storeProvider.notifier).adminRejectOrder(order.id);
      } else {
        ref.read(storeProvider.notifier).adminCancelOrder(order.id);
      }
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Order ${rejecting ? 'rejected' : 'cancelled'}.'),
          ),
        );
      }
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Order could not be ${rejecting ? 'rejected' : 'cancelled'}.',
            ),
          ),
        );
      }
    }
  }

  Future<void> _markPaymentReceived(
    BuildContext context,
    WidgetRef ref,
    CustomerOrder order,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Record payment received?'),
        content: Text(
          'Confirm that ${formatPrice(order.totalPaise)} was received for ${order.displayReference}.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Not yet'),
          ),
          FilledButton.icon(
            key: Key('admin-confirm-payment-${order.id}'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            icon: const Icon(Icons.payments_rounded),
            label: const Text('Confirm payment'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    try {
      if (AppEnvironment.hasSupabaseConfig) {
        final repository = SupabaseStoreRepository();
        await repository.markOrderPaid(order.id);
        if (context.mounted) {
          await _refreshSavedInventory(context, ref, repository);
        }
      } else {
        ref.read(storeProvider.notifier).adminMarkOrderPaid(order.id);
      }
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Payment recorded as received.')),
        );
      }
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Payment could not be recorded.')),
        );
      }
    }
  }
}

class _OverviewSection extends StatelessWidget {
  const _OverviewSection({
    required this.ordersToday,
    required this.activeCount,
    required this.todayRevenue,
    required this.pickupOrders,
    required this.completedOrders,
    required this.monthRevenue,
    required this.lowStockCount,
    required this.outOfStockCount,
  });

  final int ordersToday;
  final int activeCount;
  final int todayRevenue;
  final int pickupOrders;
  final int completedOrders;
  final int monthRevenue;
  final int lowStockCount;
  final int outOfStockCount;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      key: const Key('admin-overview-section'),
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 1050
            ? 4
            : constraints.maxWidth >= 480
            ? 2
            : 1;
        return _AdminMetricGrid(
          columns: columns,
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
              color: lowStockCount > 0 ? AppColors.warning : AppColors.success,
            ),
            _MetricCard(
              label: 'Out of stock',
              value: '$outOfStockCount items',
              icon: Icons.remove_shopping_cart_outlined,
              color: outOfStockCount > 0 ? AppColors.error : AppColors.success,
            ),
          ],
        );
      },
    );
  }
}

class _PricingSection extends StatelessWidget {
  const _PricingSection({
    required this.store,
    required this.cartOffers,
    required this.activeOffers,
    required this.onEditPricing,
    required this.onAddOffer,
    required this.onManageOffer,
    required this.onEditOffer,
    required this.onAddCartOffer,
    required this.onEditCartOffer,
  });

  final StoreState store;
  final List<StoreOffer> cartOffers;
  final List<Product> activeOffers;
  final VoidCallback onEditPricing;
  final VoidCallback onAddOffer;
  final VoidCallback onManageOffer;
  final ValueChanged<Product> onEditOffer;
  final VoidCallback onAddCartOffer;
  final ValueChanged<StoreOffer> onEditCartOffer;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      key: const Key('admin-pricing-section'),
      builder: (context, constraints) {
        final pricing = _OrderPricingCard(store: store, onEdit: onEditPricing);
        final offers = _OfferManagementCard(
          offers: activeOffers,
          onAdd: onAddOffer,
          onManage: onManageOffer,
          onEdit: onEditOffer,
        );
        final top = constraints.maxWidth < 760
            ? Column(
                children: [
                  pricing,
                  const SizedBox(height: AppSpacing.md),
                  offers,
                ],
              )
            : Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: pricing),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(child: offers),
                ],
              );
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            top,
            const SizedBox(height: AppSpacing.md),
            _CartOfferManagementCard(
              offers: cartOffers,
              products: store.products,
              onAdd: onAddCartOffer,
              onEdit: onEditCartOffer,
            ),
          ],
        );
      },
    );
  }
}

class _OrdersSection extends StatelessWidget {
  const _OrdersSection({
    required this.visibleOrders,
    required this.filter,
    required this.onFilterChanged,
    required this.terminal,
    required this.onAdvance,
    required this.onReject,
    required this.onCancel,
    required this.onMarkPaid,
  });

  final List<CustomerOrder> visibleOrders;
  final String filter;
  final ValueChanged<String> onFilterChanged;
  final bool Function(OrderStatus) terminal;
  final ValueChanged<CustomerOrder> onAdvance;
  final ValueChanged<CustomerOrder> onReject;
  final ValueChanged<CustomerOrder> onCancel;
  final ValueChanged<CustomerOrder> onMarkPaid;

  @override
  Widget build(BuildContext context) {
    return Column(
      key: const Key('admin-orders-section'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Align(
          alignment: Alignment.centerRight,
          child: PopupMenuButton<String>(
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
        ),
        const SizedBox(height: AppSpacing.md),
        if (visibleOrders.isEmpty)
          const KoyasSurface(child: Text('No orders match this filter.'))
        else
          for (final order in visibleOrders)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.md),
              child: _AdminOrderRow(
                order: order,
                canAdvance: !terminal(order.status),
                onAdvance: () => onAdvance(order),
                onReject: () => onReject(order),
                onCancel: () => onCancel(order),
                onMarkPaid: () => onMarkPaid(order),
              ),
            ),
      ],
    );
  }
}

class _BrandFilterOption {
  const _BrandFilterOption({
    required this.value,
    required this.label,
    required this.productCount,
  });

  final String value;
  final String label;
  final int productCount;
}

class _BrandFilterDialog extends StatefulWidget {
  const _BrandFilterDialog({
    required this.options,
    required this.selectedValue,
  });

  final List<_BrandFilterOption> options;
  final String selectedValue;

  @override
  State<_BrandFilterDialog> createState() => _BrandFilterDialogState();
}

class _BrandFilterDialogState extends State<_BrandFilterDialog> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final normalizedQuery = _query.trim().toLowerCase();
    final visibleOptions = widget.options
        .where(
          (option) =>
              normalizedQuery.isEmpty ||
              option.label.toLowerCase().contains(normalizedQuery),
        )
        .toList(growable: false);
    return AlertDialog(
      title: const Text('Filter by brand'),
      content: SizedBox(
        width: 460,
        height: 520,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              key: const Key('admin-brand-search'),
              autofocus: true,
              onChanged: (value) => setState(() => _query = value),
              decoration: const InputDecoration(
                labelText: 'Search brands',
                prefixIcon: Icon(Icons.search_rounded),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Expanded(
              child: visibleOptions.isEmpty
                  ? const Center(child: Text('No brands match this search.'))
                  : ListView.separated(
                      itemCount: visibleOptions.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final option = visibleOptions[index];
                        final selected = option.value == widget.selectedValue;
                        return ListTile(
                          key: Key('admin-brand-option-${option.value}'),
                          selected: selected,
                          leading: Icon(
                            selected
                                ? Icons.check_circle_rounded
                                : Icons.circle_outlined,
                            color: selected
                                ? AppColors.brand700
                                : AppColors.inkTertiary,
                          ),
                          title: Text(option.label),
                          trailing: Text('${option.productCount}'),
                          onTap: () => Navigator.of(context).pop(option.value),
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

class _CategoryInventory extends StatefulWidget {
  const _CategoryInventory({
    required this.categories,
    required this.products,
    required this.onAddProduct,
    required this.onEditProduct,
    required this.onProductActiveChanged,
    required this.onStockChanged,
    required this.onStockAdjusted,
  });

  final List<ProductCategory> categories;
  final List<Product> products;
  final ValueChanged<String?> onAddProduct;
  final ValueChanged<Product> onEditProduct;
  final Future<void> Function(Product product, bool active)
  onProductActiveChanged;
  final Future<bool> Function(Product product, int quantity) onStockChanged;
  final Future<bool> Function(Product product, int delta) onStockAdjusted;

  @override
  State<_CategoryInventory> createState() => _CategoryInventoryState();
}

class _CategoryInventoryState extends State<_CategoryInventory> {
  static const _displayLimit = 100;
  static const _allBrands = '__all_brands__';
  static const _unbranded = '__unbranded__';

  String? _selectedCategoryId;
  String _selectedBrand = _allBrands;
  String _query = '';
  String _catalogueFilter = 'Active';
  String _stockFilter = 'All';
  Timer? _searchDebounce;
  final Set<String> _busyProductIds = {};

  @override
  void dispose() {
    _searchDebounce?.cancel();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 160), () {
      if (mounted) setState(() => _query = value.trim());
    });
  }

  Future<bool> _setStock(Product product, int quantity) async {
    if (_busyProductIds.contains(product.id)) return false;
    final safeQuantity = quantity.clamp(0, 999999);
    setState(() => _busyProductIds.add(product.id));
    try {
      return await widget.onStockChanged(product, safeQuantity);
    } finally {
      if (mounted) setState(() => _busyProductIds.remove(product.id));
    }
  }

  Future<bool> _adjustStock(Product product, int delta) async {
    if (_busyProductIds.contains(product.id)) return false;
    setState(() => _busyProductIds.add(product.id));
    try {
      return await widget.onStockAdjusted(product, delta);
    } finally {
      if (mounted) setState(() => _busyProductIds.remove(product.id));
    }
  }

  Future<void> _setProductActive(Product product, bool active) async {
    if (_busyProductIds.contains(product.id)) return;
    setState(() => _busyProductIds.add(product.id));
    try {
      await widget.onProductActiveChanged(product, active);
    } finally {
      if (mounted) setState(() => _busyProductIds.remove(product.id));
    }
  }

  Future<void> _showStockEditor(Product product) async {
    if (_busyProductIds.contains(product.id)) return;
    final quantity = await showDialog<int>(
      context: context,
      builder: (_) => _StockEditorDialog(product: product),
    );
    if (quantity != null) await _setStock(product, quantity);
  }

  Future<void> _chooseBrand(List<_BrandFilterOption> options) async {
    final selected = await showDialog<String>(
      context: context,
      builder: (context) =>
          _BrandFilterDialog(options: options, selectedValue: _selectedBrand),
    );
    if (selected != null && mounted) {
      setState(() => _selectedBrand = selected);
    }
  }

  String _brandValue(Product product) {
    final brand = product.brand.trim();
    return brand.isEmpty ? _unbranded : brand;
  }

  int _inventoryOrder(Product first, Product second) {
    final brandComparison = _brandValue(
      first,
    ).toLowerCase().compareTo(_brandValue(second).toLowerCase());
    if (brandComparison != 0) return brandComparison;
    return first.name.toLowerCase().compareTo(second.name.toLowerCase());
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
    bool matchesCatalogueStatus(Product product) => switch (_catalogueFilter) {
      'Active' => product.active,
      'Archived' => !product.active,
      _ => true,
    };
    final catalogueProducts = widget.products
        .where(matchesCatalogueStatus)
        .toList(growable: false);
    final categoryProducts = catalogueProducts
        .where(
          (product) =>
              selectedCategoryId == null ||
              product.categoryId == selectedCategoryId,
        )
        .toList(growable: false);
    final brandCounts = <String, int>{};
    for (final product in categoryProducts) {
      final brand = _brandValue(product);
      brandCounts.update(brand, (count) => count + 1, ifAbsent: () => 1);
    }
    final availableBrands =
        brandCounts.keys
            .where((brand) => brand != _unbranded)
            .toList(growable: false)
          ..sort(
            (first, second) =>
                first.toLowerCase().compareTo(second.toLowerCase()),
          );
    final selectedBrand =
        _selectedBrand == _allBrands || brandCounts.containsKey(_selectedBrand)
        ? _selectedBrand
        : _allBrands;
    final brandOptions = <_BrandFilterOption>[
      _BrandFilterOption(
        value: _allBrands,
        label: 'All brands',
        productCount: categoryProducts.length,
      ),
      for (final brand in availableBrands)
        _BrandFilterOption(
          value: brand,
          label: brand,
          productCount: brandCounts[brand]!,
        ),
      if (brandCounts.containsKey(_unbranded))
        _BrandFilterOption(
          value: _unbranded,
          label: 'No brand',
          productCount: brandCounts[_unbranded]!,
        ),
    ];
    final selectedBrandOption = brandOptions.firstWhere(
      (option) => option.value == selectedBrand,
    );
    final searchedProducts = ProductSearch.search(
      products: widget.products,
      query: _query,
      categoryId: selectedCategoryId,
      filter: (product) =>
          matchesCatalogueStatus(product) &&
          (selectedBrand == _allBrands ||
              _brandValue(product) == selectedBrand),
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
        .toList(growable: true);
    if (_query.trim().isEmpty) visibleProducts.sort(_inventoryOrder);
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
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: [
            for (final filter in const ['Active', 'Archived', 'All'])
              ChoiceChip(
                key: Key('admin-catalogue-${filter.toLowerCase()}'),
                avatar: Icon(
                  filter == 'Archived'
                      ? Icons.archive_outlined
                      : filter == 'Active'
                      ? Icons.storefront_outlined
                      : Icons.all_inbox_outlined,
                  size: 18,
                ),
                label: Text(
                  '$filter (${switch (filter) {
                    'Active' => widget.products.where((product) => product.active).length,
                    'Archived' => widget.products.where((product) => !product.active).length,
                    _ => widget.products.length,
                  }})',
                ),
                selected: _catalogueFilter == filter,
                onSelected: (_) => setState(() {
                  _catalogueFilter = filter;
                  _selectedBrand = _allBrands;
                  if (filter == 'Archived') _stockFilter = 'All';
                }),
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        SingleChildScrollView(
          key: const Key('admin-category-picker'),
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              ChoiceChip(
                key: const Key('admin-category-all'),
                label: Text('All (${catalogueProducts.length})'),
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
                onSelected: (_) => setState(() {
                  _selectedCategoryId = null;
                  _selectedBrand = _allBrands;
                }),
              ),
              const SizedBox(width: AppSpacing.sm),
              for (final category in widget.categories) ...[
                ChoiceChip(
                  key: Key('admin-category-${category.id}'),
                  avatar: CategoryPicture(
                    visualKey: category.visualKey,
                    width: 24,
                    height: 24,
                    padding: 1,
                    radius: 6,
                  ),
                  avatarBoxConstraints: const BoxConstraints.tightFor(
                    width: 24,
                    height: 24,
                  ),
                  label: ConstrainedBox(
                    constraints: BoxConstraints(
                      minHeight: 24,
                      maxWidth: (MediaQuery.sizeOf(context).width - 180).clamp(
                        100,
                        320,
                      ),
                    ),
                    child: Text(
                      '${category.name} (${catalogueProducts.where((product) => product.categoryId == category.id).length})',
                    ),
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
                  onSelected: (_) => setState(() {
                    _selectedCategoryId = category.id;
                    _selectedBrand = _allBrands;
                  }),
                ),
                const SizedBox(width: AppSpacing.sm),
              ],
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        LayoutBuilder(
          builder: (context, constraints) {
            final search = TextField(
              key: const Key('admin-product-search'),
              onChanged: _onSearchChanged,
              decoration: const InputDecoration(
                labelText: 'Search inventory',
                hintText: 'Product, brand, barcode, SKU, or need',
                prefixIcon: Icon(Icons.search_rounded),
              ),
            );
            final brand = SizedBox(
              width: constraints.maxWidth < 720 ? double.infinity : 300,
              child: OutlinedButton.icon(
                key: const Key('admin-brand-filter'),
                onPressed: () => _chooseBrand(brandOptions),
                icon: const Icon(Icons.branding_watermark_outlined),
                label: Text(
                  '${selectedBrandOption.label} (${selectedBrandOption.productCount})',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            );
            if (constraints.maxWidth < 720) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  search,
                  const SizedBox(height: AppSpacing.md),
                  brand,
                ],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: search),
                const SizedBox(width: AppSpacing.md),
                brand,
              ],
            );
          },
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
            ActionChip(
              key: const Key('admin-all-products-summary'),
              avatar: const Icon(Icons.sell_outlined, size: 18),
              label: Text('${visibleProducts.length} products'),
              onPressed: () => setState(() => _stockFilter = 'All'),
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
            ActionChip(
              key: const Key('admin-low-stock-summary'),
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
              onPressed: () => setState(() => _stockFilter = 'Low stock'),
              backgroundColor: AppColors.surface,
              labelStyle: Theme.of(
                context,
              ).textTheme.labelLarge?.copyWith(color: AppColors.ink),
            ),
            ActionChip(
              key: const Key('admin-out-of-stock-summary'),
              avatar: const Icon(
                Icons.remove_shopping_cart_outlined,
                size: 18,
                color: AppColors.error,
              ),
              label: Text('$visibleOutOfStock out of stock'),
              onPressed: () => setState(() => _stockFilter = 'Out of stock'),
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
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Padding(
                    padding: EdgeInsets.only(bottom: AppSpacing.lg),
                    child: Text(
                      'Type the total stock or use +/−, then tap Save.',
                    ),
                  ),
                ),
                for (
                  var index = 0;
                  index < displayedProducts.length;
                  index++
                ) ...[
                  _InventoryProductRow(
                    key: Key('admin-product-${displayedProducts[index].id}'),
                    product: displayedProducts[index],
                    busy: _busyProductIds.contains(displayedProducts[index].id),
                    onStockChanged: _setStock,
                    onStockAdjusted: _adjustStock,
                    onSetStock: () =>
                        _showStockEditor(displayedProducts[index]),
                    onEdit: () =>
                        widget.onEditProduct(displayedProducts[index]),
                    onActiveChanged: (active) =>
                        _setProductActive(displayedProducts[index], active),
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
                  return parsed == null || parsed < 0 || parsed > 999999
                      ? 'Enter a whole number from 0 to 999999'
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
    required this.onStockChanged,
    required this.onStockAdjusted,
    required this.onSetStock,
    required this.onEdit,
    required this.onActiveChanged,
    super.key,
  });

  final Product product;
  final bool busy;
  final Future<bool> Function(Product product, int quantity) onStockChanged;
  final Future<bool> Function(Product product, int delta) onStockAdjusted;
  final VoidCallback onSetStock;
  final VoidCallback onEdit;
  final ValueChanged<bool> onActiveChanged;

  @override
  Widget build(BuildContext context) {
    final stockColor = !product.active
        ? AppColors.inkSecondary
        : product.stockQuantity == 0
        ? AppColors.error
        : product.stockQuantity <= 12
        ? AppColors.warning
        : AppColors.success;
    final stockBackground = !product.active
        ? AppColors.surfaceMuted
        : product.stockQuantity == 0
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
        !product.active
            ? 'Archived'
            : product.stockQuantity == 0
            ? 'Out of stock'
            : '${product.stockQuantity} in stock',
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: stockColor,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
    final controls = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        StockQuantityEditor(
          product: product,
          busy: busy,
          onSetStock: onStockChanged,
          onAdjustStock: onStockAdjusted,
        ),
        TextButton(
          key: Key('admin-stock-set-${product.id}'),
          onPressed: busy || !product.active ? null : onSetStock,
          child: const Text('Set total…'),
        ),
      ],
    );

    final actionsMenu = PopupMenuButton<String>(
      key: Key('admin-product-actions-${product.id}'),
      tooltip: 'Manage ${product.name}',
      enabled: !busy,
      onSelected: (action) {
        switch (action) {
          case 'edit':
            onEdit();
            break;
          case 'toggle-active':
            onActiveChanged(!product.active);
            break;
        }
      },
      itemBuilder: (context) => [
        const PopupMenuItem(
          value: 'edit',
          child: ListTile(
            leading: Icon(Icons.edit_outlined),
            title: Text('Edit product'),
            contentPadding: EdgeInsets.zero,
          ),
        ),
        PopupMenuItem(
          value: 'toggle-active',
          child: ListTile(
            leading: Icon(
              product.active
                  ? Icons.archive_outlined
                  : Icons.unarchive_outlined,
            ),
            title: Text(product.active ? 'Archive product' : 'Restore product'),
            contentPadding: EdgeInsets.zero,
          ),
        ),
      ],
      icon: const Icon(Icons.more_vert_rounded),
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
                  actionsMenu,
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                children: [stockBadge, controls],
              ),
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
            actionsMenu,
          ],
        );
      },
    );
  }
}

/// Equal-height rows that grow with text instead of clipping at a fixed ratio.
class _AdminMetricGrid extends StatelessWidget {
  const _AdminMetricGrid({required this.columns, required this.children});

  final int columns;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (var start = 0; start < children.length; start += columns) ...[
          if (start > 0) const SizedBox(height: AppSpacing.md),
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var offset = 0; offset < columns; offset++) ...[
                  if (offset > 0) const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: start + offset < children.length
                        ? children[start + offset]
                        : const SizedBox.shrink(),
                  ),
                ],
              ],
            ),
          ),
        ],
      ],
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
    required this.onReject,
    required this.onCancel,
    required this.onMarkPaid,
  });

  final CustomerOrder order;
  final bool canAdvance;
  final VoidCallback onAdvance;
  final VoidCallback onReject;
  final VoidCallback onCancel;
  final VoidCallback onMarkPaid;

  String get _contactName {
    final value = order.fulfilmentType == FulfilmentType.delivery
        ? (order.deliveryRecipientName.isNotEmpty
              ? order.deliveryRecipientName
              : order.customerName)
        : order.customerName;
    return value.trim().isEmpty ? 'Contact not recorded' : value;
  }

  String get _contactSummary {
    final phone = order.fulfilmentType == FulfilmentType.delivery
        ? (order.deliveryRecipientPhone.isNotEmpty
              ? order.deliveryRecipientPhone
              : order.customerPhone)
        : order.customerPhone;
    final destination = order.fulfilmentType == FulfilmentType.delivery
        ? order.addressText ?? 'Address not recorded'
        : 'Store pickup';
    return phone.trim().isEmpty ? destination : '$phone · $destination';
  }

  bool get _canRecordPayment {
    if (order.paymentStatus != PaymentStatus.pending) return false;
    return switch (order.paymentMethod) {
      PaymentMethod.payAtStore => {
        OrderStatus.readyForPickup,
        OrderStatus.collected,
      }.contains(order.status),
      PaymentMethod.cashOnDelivery => {
        OrderStatus.outForDelivery,
        OrderStatus.delivered,
      }.contains(order.status),
      PaymentMethod.online => false,
    };
  }

  @override
  Widget build(BuildContext context) {
    return KoyasSurface(
      key: Key('admin-order-${order.id}'),
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
          SizedBox(
            width: 260,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _contactName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelLarge,
                ),
                Text(
                  _contactSummary,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppColors.inkSecondary,
                  ),
                ),
              ],
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
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.sm,
            ),
            decoration: BoxDecoration(
              color: order.paymentStatus.adminColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(AppRadii.full),
            ),
            child: Text(
              order.paymentStatus.adminLabel,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: order.paymentStatus.adminColor,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          OutlinedButton.icon(
            key: Key('admin-order-details-${order.id}'),
            onPressed: () => showDialog<void>(
              context: context,
              builder: (context) => _AdminOrderDetailsDialog(order: order),
            ),
            icon: const Icon(Icons.visibility_outlined, size: 18),
            label: const Text('View details'),
          ),
          if (_canRecordPayment)
            FilledButton.icon(
              key: Key('admin-mark-paid-${order.id}'),
              onPressed: onMarkPaid,
              icon: const Icon(Icons.payments_rounded, size: 18),
              label: const Text('Mark payment received'),
            ),
          if (order.status == OrderStatus.placed)
            TextButton.icon(
              key: Key('admin-reject-${order.id}'),
              onPressed: onReject,
              icon: const Icon(Icons.block_rounded, size: 18),
              label: const Text('Reject'),
            ),
          if (order.status == OrderStatus.confirmed)
            TextButton.icon(
              key: Key('admin-cancel-${order.id}'),
              onPressed: onCancel,
              icon: const Icon(Icons.cancel_outlined, size: 18),
              label: const Text('Cancel order'),
            ),
          if (canAdvance && !_canRecordPayment)
            FilledButton.tonalIcon(
              key: Key('admin-advance-${order.id}'),
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
          else if (!canAdvance)
            Text(
              'Complete',
              style: Theme.of(
                context,
              ).textTheme.labelLarge?.copyWith(color: AppColors.inkTertiary),
            )
          else
            Text(
              'Record payment before completion',
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: AppColors.warning,
                fontWeight: FontWeight.w700,
              ),
            ),
        ],
      ),
    );
  }
}

class _AdminOrderDetailsDialog extends ConsumerStatefulWidget {
  const _AdminOrderDetailsDialog({required CustomerOrder order})
    : initialOrder = order;

  final CustomerOrder initialOrder;

  @override
  ConsumerState<_AdminOrderDetailsDialog> createState() =>
      _AdminOrderDetailsDialogState();
}

class _AdminOrderDetailsDialogState
    extends ConsumerState<_AdminOrderDetailsDialog> {
  String? _printError;

  String _value(String value) => value.trim().isEmpty ? 'Not recorded' : value;

  String _paymentMethodLabel(CustomerOrder order) =>
      switch (order.paymentMethod) {
        PaymentMethod.cashOnDelivery => 'Cash or UPI on delivery',
        PaymentMethod.payAtStore => 'Cash or UPI at pickup',
        PaymentMethod.online => 'Online payment',
      };

  @override
  Widget build(BuildContext context) {
    final order = ref.watch(
      storeProvider.select(
        (store) => store.orders.firstWhere(
          (order) => order.id == widget.initialOrder.id,
          orElse: () => widget.initialOrder,
        ),
      ),
    );
    final delivery = order.fulfilmentType == FulfilmentType.delivery;
    final recipientName = delivery
        ? _value(
            order.deliveryRecipientName.isNotEmpty
                ? order.deliveryRecipientName
                : order.customerName,
          )
        : _value(order.customerName);
    final recipientPhone = delivery
        ? _value(
            order.deliveryRecipientPhone.isNotEmpty
                ? order.deliveryRecipientPhone
                : order.customerPhone,
          )
        : _value(order.customerPhone);

    return Dialog(
      key: Key('admin-order-details-dialog-${order.id}'),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 720,
          maxHeight: MediaQuery.sizeOf(context).height * 0.9,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.xl,
                AppSpacing.xl,
                AppSpacing.md,
                AppSpacing.md,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Order ${order.displayReference}',
                          style: Theme.of(context).textTheme.headlineSmall,
                        ),
                        const SizedBox(height: AppSpacing.xs),
                        Text(
                          '${order.status.label} · ${DateFormat('d MMM y, h:mm a').format(order.createdAt)}',
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: AppColors.inkSecondary),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    key: Key('admin-close-order-details-${order.id}'),
                    tooltip: 'Close details',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(AppSpacing.xl),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _AdminOrderDetailSection(
                      title: delivery ? 'Delivery' : 'Pickup customer',
                      icon: delivery
                          ? Icons.delivery_dining_rounded
                          : Icons.storefront_rounded,
                      children: [
                        _AdminOrderDetailField(
                          label: delivery ? 'Recipient' : 'Customer',
                          value: recipientName,
                        ),
                        _AdminOrderDetailField(
                          label: 'Phone',
                          value: recipientPhone,
                        ),
                        if (delivery) ...[
                          _AdminOrderDetailField(
                            label: 'Delivery address',
                            value: _value(order.addressText ?? ''),
                          ),
                          if (order.deliveryPin != null)
                            DeliveryPinSummary(
                              pin: order.deliveryPin!,
                              staff: true,
                            ),
                          _AdminOrderDetailField(
                            label: 'Delivery instructions',
                            value: order.deliveryInstructions.trim().isEmpty
                                ? 'No delivery instructions'
                                : order.deliveryInstructions,
                          ),
                        ],
                        if (delivery &&
                            (order.customerName != recipientName ||
                                order.customerPhone != recipientPhone)) ...[
                          _AdminOrderDetailField(
                            label: 'Ordering customer',
                            value: _value(order.customerName),
                          ),
                          _AdminOrderDetailField(
                            label: 'Customer phone',
                            value: _value(order.customerPhone),
                          ),
                        ],
                        _AdminOrderDetailField(
                          label: 'Fulfilment',
                          value:
                              '${DateFormat('EEE, d MMM y').format(order.fulfilmentDate)} · ${order.slotLabel}',
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    _AdminOrderDetailSection(
                      title: 'Payment',
                      icon: Icons.payments_outlined,
                      children: [
                        _AdminOrderDetailField(
                          label: 'Method',
                          value: _paymentMethodLabel(order),
                        ),
                        _AdminOrderDetailField(
                          label: 'Status',
                          value: order.paymentStatus.adminLabel,
                        ),
                        if (order.paidAt != null)
                          _AdminOrderDetailField(
                            label: 'Received at',
                            value: DateFormat(
                              'd MMM y, h:mm a',
                            ).format(order.paidAt!),
                          ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    _AdminOrderDetailSection(
                      title: 'Items (${order.items.length})',
                      icon: Icons.shopping_basket_outlined,
                      children: [
                        for (final item in order.items)
                          Padding(
                            padding: const EdgeInsets.only(
                              bottom: AppSpacing.sm,
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: Text(
                                    '${item.quantity} × ${item.name} · ${item.unit}${item.isFreeOfferItem ? ' · FREE' : ''}',
                                  ),
                                ),
                                const SizedBox(width: AppSpacing.md),
                                Text(
                                  item.isFreeOfferItem
                                      ? 'Free'
                                      : formatPrice(item.totalPaise),
                                ),
                              ],
                            ),
                          ),
                        const Divider(),
                        _AdminOrderAmountRow(
                          label: 'Subtotal',
                          amountPaise: order.subtotalPaise,
                        ),
                        _AdminOrderAmountRow(
                          label: 'Delivery',
                          amountPaise: order.deliveryChargePaise,
                        ),
                        if (order.offerCode != null)
                          _AdminOrderAmountRow(
                            label: 'Offer ${order.offerCode}',
                            amountPaise: -order.offerDiscountPaise,
                          ),
                        _AdminOrderAmountRow(
                          label: 'Total',
                          amountPaise: order.totalPaise,
                          emphasized: true,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if (_printError != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                      child: Semantics(
                        liveRegion: true,
                        child: Text(
                          _printError!,
                          style: const TextStyle(color: AppColors.error),
                        ),
                      ),
                    ),
                  FilledButton.icon(
                    key: Key('admin-print-bill-${order.id}'),
                    onPressed: () {
                      setState(() => _printError = null);
                      try {
                        ref.read(orderBillPrinterProvider)(order);
                      } catch (error) {
                        setState(
                          () => _printError = error is StateError
                              ? error.message
                              : 'The bill could not be opened. Please try again.',
                        );
                      }
                    },
                    icon: const Icon(Icons.print_outlined),
                    label: const Text('Print bill'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AdminOrderDetailSection extends StatelessWidget {
  const _AdminOrderDetailSection({
    required this.title,
    required this.icon,
    required this.children,
  });

  final String title;
  final IconData icon;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.canvas,
        borderRadius: BorderRadius.circular(AppRadii.lg),
        border: Border.all(color: AppColors.outline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(icon, size: 20, color: AppColors.brand600),
              const SizedBox(width: AppSpacing.sm),
              Text(title, style: Theme.of(context).textTheme.titleMedium),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          ...children,
        ],
      ),
    );
  }
}

class _AdminOrderDetailField extends StatelessWidget {
  const _AdminOrderDetailField({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 145,
            child: Text(
              label,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: AppColors.inkSecondary),
            ),
          ),
          Expanded(child: SelectableText(value)),
        ],
      ),
    );
  }
}

class _AdminOrderAmountRow extends StatelessWidget {
  const _AdminOrderAmountRow({
    required this.label,
    required this.amountPaise,
    this.emphasized = false,
  });

  final String label;
  final int amountPaise;
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    final style = emphasized
        ? Theme.of(context).textTheme.titleSmall
        : Theme.of(context).textTheme.bodyMedium;
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.xs),
      child: Row(
        children: [
          Expanded(child: Text(label, style: style)),
          Text(formatPrice(amountPaise), style: style),
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
              return _AdminMetricGrid(
                columns: columns,
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

class _OrderPricingCard extends StatelessWidget {
  const _OrderPricingCard({required this.store, required this.onEdit});

  final StoreState store;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final free = store.baseDeliveryChargePaise == 0;
    return KoyasSurface(
      key: const Key('admin-order-pricing'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.delivery_dining_rounded),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  'Order pricing',
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
            store.minimumOrderPaise == 0
                ? 'No minimum order is active.'
                : 'Minimum order: ${formatPrice(store.minimumOrderPaise)}.',
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: AppColors.inkSecondary),
          ),
          const SizedBox(height: AppSpacing.sm),
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
            key: const Key('admin-edit-order-pricing'),
            onPressed: onEdit,
            icon: const Icon(Icons.edit_outlined),
            label: const Text('Change order pricing'),
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

class _CartOfferManagementCard extends StatelessWidget {
  const _CartOfferManagementCard({
    required this.offers,
    required this.products,
    required this.onAdd,
    required this.onEdit,
  });

  final List<StoreOffer> offers;
  final List<Product> products;
  final VoidCallback onAdd;
  final ValueChanged<StoreOffer> onEdit;

  Product? _product(String? id) {
    if (id == null) return null;
    for (final product in products) {
      if (product.id == id) return product;
    }
    return null;
  }

  String _benefit(StoreOffer offer) {
    final parts = <String>[];
    if (offer.discountType == OfferDiscountType.flat) {
      parts.add('${formatPrice(offer.discountValue)} off');
    } else if (offer.discountType == OfferDiscountType.percentage) {
      parts.add('${offer.discountValue}% off');
    }
    final freeProduct = _product(offer.freeProductId);
    if (freeProduct != null) {
      parts.add('${offer.freeQuantity} × ${freeProduct.name} free');
    }
    return parts.join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final activeCount = offers.where((offer) => offer.active).length;
    return KoyasSurface(
      key: const Key('admin-cart-offers'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.redeem_outlined),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  'Minimum-buy & free-product offers',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              Chip(label: Text('$activeCount active')),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Control customer codes, minimum basket values, discounts, free products, schedules, and usage limits.',
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: AppColors.inkSecondary),
          ),
          if (offers.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.md),
            for (final offer in offers)
              ListTile(
                key: Key('admin-cart-offer-${offer.id}'),
                contentPadding: EdgeInsets.zero,
                leading: CircleAvatar(
                  backgroundColor: offer.active
                      ? AppColors.successSoft
                      : AppColors.surfaceMuted,
                  child: Icon(
                    offer.hasFreeProduct
                        ? Icons.card_giftcard_rounded
                        : Icons.percent_rounded,
                    color: offer.active
                        ? AppColors.success
                        : AppColors.inkTertiary,
                  ),
                ),
                title: Text('${offer.code} · ${offer.title}'),
                subtitle: Text(
                  '${_benefit(offer)}\nMinimum ${formatPrice(offer.minimumSubtotalPaise)} · ${offer.active ? 'Active' : 'Disabled'}',
                ),
                isThreeLine: true,
                trailing: TextButton(
                  key: Key('admin-edit-cart-offer-${offer.id}'),
                  onPressed: () => onEdit(offer),
                  child: const Text('Edit'),
                ),
              ),
          ] else ...[
            const SizedBox(height: AppSpacing.md),
            const Text('No cart offers have been created yet.'),
          ],
          const SizedBox(height: AppSpacing.md),
          FilledButton.tonalIcon(
            key: const Key('admin-add-cart-offer'),
            onPressed: onAdd,
            icon: const Icon(Icons.add_rounded),
            label: const Text('Create cart offer'),
          ),
        ],
      ),
    );
  }
}

class _OrderPricingDialog extends StatefulWidget {
  const _OrderPricingDialog({required this.store});

  final StoreState store;

  @override
  State<_OrderPricingDialog> createState() => _OrderPricingDialogState();
}

class _OrderPricingDialogState extends State<_OrderPricingDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _minimumOrder;
  late final TextEditingController _deliveryCharge;
  late final TextEditingController _freeThreshold;
  late bool _freeDelivery;

  @override
  void initState() {
    super.initState();
    _freeDelivery = widget.store.baseDeliveryChargePaise == 0;
    _minimumOrder = TextEditingController(
      text: (widget.store.minimumOrderPaise / 100).toStringAsFixed(2),
    );
    _deliveryCharge = TextEditingController(
      text: (widget.store.baseDeliveryChargePaise / 100).toStringAsFixed(2),
    );
    _freeThreshold = TextEditingController(
      text: (widget.store.freeDeliveryThresholdPaise / 100).toStringAsFixed(2),
    );
  }

  @override
  void dispose() {
    _minimumOrder.dispose();
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
      _OrderPricingResult(
        minimumOrderPaise: _paise(_minimumOrder.text)!,
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
      title: const Text('Order pricing'),
      content: SizedBox(
        width: 500,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Set the minimum order and delivery pricing applied at checkout. Use ₹0 for no minimum order.',
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(color: AppColors.inkSecondary),
              ),
              const SizedBox(height: AppSpacing.md),
              TextFormField(
                key: const Key('admin-minimum-order'),
                controller: _minimumOrder,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'Minimum order (₹)',
                  helperText: 'Enter ₹0 to allow orders of any value.',
                  prefixIcon: Icon(Icons.shopping_cart_checkout_rounded),
                ),
                validator: (value) {
                  final amount = _paise(value ?? '');
                  return amount == null || amount < 0 || amount > 100000000
                      ? 'Enter an amount from ₹0 to ₹10,00,000'
                      : null;
                },
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
          key: const Key('admin-save-order-pricing'),
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
      filter: (product) => product.active,
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

enum _CartOfferDiscountChoice { none, flat, percentage }

enum _CartOfferFulfilmentChoice { all, pickup, delivery }

class _CartOfferEditorDialog extends StatefulWidget {
  const _CartOfferEditorDialog({required this.offer, required this.products});

  final StoreOffer? offer;
  final List<Product> products;

  @override
  State<_CartOfferEditorDialog> createState() => _CartOfferEditorDialogState();
}

class _CartOfferEditorDialogState extends State<_CartOfferEditorDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _code;
  late final TextEditingController _title;
  late final TextEditingController _description;
  late final TextEditingController _minimum;
  late final TextEditingController _discountValue;
  late final TextEditingController _maximumDiscount;
  late final TextEditingController _freeQuantity;
  late final TextEditingController _totalLimit;
  late final TextEditingController _customerLimit;
  late _CartOfferDiscountChoice _discountChoice;
  late _CartOfferFulfilmentChoice _fulfilmentChoice;
  String? _freeProductId;
  DateTime? _startsAt;
  DateTime? _endsAt;
  late bool _active;
  String? _benefitError;

  @override
  void initState() {
    super.initState();
    final offer = widget.offer;
    _code = TextEditingController(text: offer?.code ?? '');
    _title = TextEditingController(text: offer?.title ?? '');
    _description = TextEditingController(text: offer?.description ?? '');
    _minimum = TextEditingController(
      text: offer == null
          ? '0.00'
          : (offer.minimumSubtotalPaise / 100).toStringAsFixed(2),
    );
    _discountChoice = switch (offer?.discountType) {
      OfferDiscountType.flat => _CartOfferDiscountChoice.flat,
      OfferDiscountType.percentage => _CartOfferDiscountChoice.percentage,
      null => _CartOfferDiscountChoice.none,
    };
    _discountValue = TextEditingController(
      text: offer == null || !offer.hasDiscount
          ? ''
          : offer.discountType == OfferDiscountType.flat
          ? (offer.discountValue / 100).toStringAsFixed(2)
          : '${offer.discountValue}',
    );
    _maximumDiscount = TextEditingController(
      text: offer?.maximumDiscountPaise == null
          ? ''
          : (offer!.maximumDiscountPaise! / 100).toStringAsFixed(2),
    );
    _freeProductId = offer?.freeProductId;
    _freeQuantity = TextEditingController(text: '${offer?.freeQuantity ?? 1}');
    _totalLimit = TextEditingController(
      text: offer?.totalRedemptionLimit?.toString() ?? '',
    );
    _customerLimit = TextEditingController(
      text: '${offer?.perCustomerLimit ?? 1}',
    );
    _fulfilmentChoice = switch (offer?.requiredFulfilment) {
      FulfilmentType.pickup => _CartOfferFulfilmentChoice.pickup,
      FulfilmentType.delivery => _CartOfferFulfilmentChoice.delivery,
      null => _CartOfferFulfilmentChoice.all,
    };
    _startsAt = offer?.startsAt;
    _endsAt = offer?.endsAt;
    _active = offer?.active ?? true;
  }

  @override
  void dispose() {
    _code.dispose();
    _title.dispose();
    _description.dispose();
    _minimum.dispose();
    _discountValue.dispose();
    _maximumDiscount.dispose();
    _freeQuantity.dispose();
    _totalLimit.dispose();
    _customerLimit.dispose();
    super.dispose();
  }

  int? _paise(String value) {
    final amount = double.tryParse(value.trim());
    return amount == null || !amount.isFinite ? null : (amount * 100).round();
  }

  int? _optionalPositiveInteger(String value) {
    if (value.trim().isEmpty) return null;
    final parsed = int.tryParse(value.trim());
    return parsed != null && parsed > 0 ? parsed : -1;
  }

  Product? get _freeProduct {
    for (final product in widget.products) {
      if (product.id == _freeProductId) return product;
    }
    return null;
  }

  Future<void> _chooseFreeProduct() async {
    final product = await showDialog<Product>(
      context: context,
      builder: (context) =>
          _OfferProductPickerDialog(products: widget.products),
    );
    if (product != null && mounted) {
      setState(() {
        _freeProductId = product.id;
        _benefitError = null;
      });
    }
  }

  Future<void> _pickDate({required bool start}) async {
    final initial = start
        ? _startsAt ?? DateTime.now()
        : _endsAt ?? _startsAt ?? DateTime.now().add(const Duration(days: 7));
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 3650)),
    );
    if (picked == null || !mounted) return;
    setState(() {
      if (start) {
        _startsAt = DateTime(picked.year, picked.month, picked.day);
      } else {
        _endsAt = DateTime(picked.year, picked.month, picked.day, 23, 59, 59);
      }
    });
  }

  void _save() {
    setState(() => _benefitError = null);
    if (!_formKey.currentState!.validate()) return;
    final hasDiscount = _discountChoice != _CartOfferDiscountChoice.none;
    if (!hasDiscount && _freeProductId == null) {
      setState(
        () => _benefitError = 'Choose a discount, a free product, or both.',
      );
      return;
    }
    if (_startsAt != null && _endsAt != null && !_endsAt!.isAfter(_startsAt!)) {
      setState(() => _benefitError = 'End date must be after the start date.');
      return;
    }

    final discountType = switch (_discountChoice) {
      _CartOfferDiscountChoice.none => null,
      _CartOfferDiscountChoice.flat => OfferDiscountType.flat,
      _CartOfferDiscountChoice.percentage => OfferDiscountType.percentage,
    };
    final discountValue = switch (_discountChoice) {
      _CartOfferDiscountChoice.none => 0,
      _CartOfferDiscountChoice.flat => _paise(_discountValue.text)!,
      _CartOfferDiscountChoice.percentage => int.parse(
        _discountValue.text.trim(),
      ),
    };
    final requiredFulfilment = switch (_fulfilmentChoice) {
      _CartOfferFulfilmentChoice.all => null,
      _CartOfferFulfilmentChoice.pickup => FulfilmentType.pickup,
      _CartOfferFulfilmentChoice.delivery => FulfilmentType.delivery,
    };

    Navigator.of(context).pop(
      StoreOffer(
        revision: widget.offer?.revision ?? 0,
        id:
            widget.offer?.id ??
            'new-offer-${DateTime.now().microsecondsSinceEpoch}',
        code: _code.text.trim().toUpperCase(),
        title: _title.text.trim(),
        description: _description.text.trim(),
        minimumSubtotalPaise: _paise(_minimum.text)!,
        discountType: discountType,
        discountValue: discountValue,
        maximumDiscountPaise:
            _discountChoice == _CartOfferDiscountChoice.percentage &&
                _maximumDiscount.text.trim().isNotEmpty
            ? _paise(_maximumDiscount.text)
            : null,
        freeProductId: _freeProductId,
        freeQuantity: int.parse(_freeQuantity.text.trim()),
        requiredFulfilment: requiredFulfilment,
        startsAt: _startsAt,
        endsAt: _endsAt,
        totalRedemptionLimit: _optionalPositiveInteger(_totalLimit.text),
        perCustomerLimit: int.parse(_customerLimit.text.trim()),
        active: _active,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final dateFormat = DateFormat('d MMM y');
    return AlertDialog(
      title: Text(
        widget.offer == null ? 'Create cart offer' : 'Edit cart offer',
      ),
      content: SizedBox(
        width: 680,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        key: const Key('admin-cart-offer-code'),
                        controller: _code,
                        textCapitalization: TextCapitalization.characters,
                        decoration: const InputDecoration(
                          labelText: 'Customer code',
                          hintText: 'SAVE10',
                        ),
                        validator: (value) =>
                            RegExp(
                              r'^[A-Za-z0-9_-]{3,24}$',
                            ).hasMatch(value?.trim() ?? '')
                            ? null
                            : 'Use 3–24 letters, numbers, dashes, or underscores',
                      ),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: TextFormField(
                        key: const Key('admin-cart-offer-title'),
                        controller: _title,
                        decoration: const InputDecoration(
                          labelText: 'Offer title',
                        ),
                        validator: (value) {
                          final length = value?.trim().length ?? 0;
                          return length < 2 || length > 120
                              ? 'Enter 2–120 characters'
                              : null;
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
                TextFormField(
                  key: const Key('admin-cart-offer-description'),
                  controller: _description,
                  maxLength: 500,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: 'Customer description',
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                TextFormField(
                  key: const Key('admin-cart-offer-minimum'),
                  controller: _minimum,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Minimum basket (₹)',
                    prefixIcon: Icon(Icons.shopping_basket_outlined),
                  ),
                  validator: (value) {
                    final amount = _paise(value ?? '');
                    return amount == null || amount < 0
                        ? 'Enter a valid minimum'
                        : null;
                  },
                ),
                const SizedBox(height: AppSpacing.md),
                DropdownButtonFormField<_CartOfferDiscountChoice>(
                  key: const Key('admin-cart-offer-discount-type'),
                  initialValue: _discountChoice,
                  decoration: const InputDecoration(
                    labelText: 'Discount benefit',
                  ),
                  items: const [
                    DropdownMenuItem(
                      value: _CartOfferDiscountChoice.none,
                      child: Text('No price discount'),
                    ),
                    DropdownMenuItem(
                      value: _CartOfferDiscountChoice.flat,
                      child: Text('Flat amount off'),
                    ),
                    DropdownMenuItem(
                      value: _CartOfferDiscountChoice.percentage,
                      child: Text('Percentage off'),
                    ),
                  ],
                  onChanged: (value) => setState(
                    () => _discountChoice =
                        value ?? _CartOfferDiscountChoice.none,
                  ),
                ),
                if (_discountChoice != _CartOfferDiscountChoice.none) ...[
                  const SizedBox(height: AppSpacing.md),
                  TextFormField(
                    key: const Key('admin-cart-offer-discount-value'),
                    controller: _discountValue,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: InputDecoration(
                      labelText:
                          _discountChoice == _CartOfferDiscountChoice.flat
                          ? 'Discount amount (₹)'
                          : 'Discount percentage',
                    ),
                    validator: (value) {
                      if (_discountChoice == _CartOfferDiscountChoice.flat) {
                        final amount = _paise(value ?? '');
                        return amount == null || amount <= 0
                            ? 'Enter a positive discount'
                            : null;
                      }
                      final percent = int.tryParse(value?.trim() ?? '');
                      return percent == null || percent < 1 || percent > 100
                          ? 'Enter a percentage from 1 to 100'
                          : null;
                    },
                  ),
                ],
                if (_discountChoice == _CartOfferDiscountChoice.percentage) ...[
                  const SizedBox(height: AppSpacing.md),
                  TextFormField(
                    key: const Key('admin-cart-offer-maximum-discount'),
                    controller: _maximumDiscount,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(
                      labelText: 'Maximum discount (₹, optional)',
                    ),
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) return null;
                      final amount = _paise(value);
                      return amount == null || amount <= 0
                          ? 'Enter a positive maximum'
                          : null;
                    },
                  ),
                ],
                const SizedBox(height: AppSpacing.lg),
                Text(
                  'Free product',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: AppSpacing.sm),
                if (_freeProduct == null)
                  OutlinedButton.icon(
                    key: const Key('admin-cart-offer-choose-free-product'),
                    onPressed: _chooseFreeProduct,
                    icon: const Icon(Icons.card_giftcard_rounded),
                    label: const Text('Choose a free product'),
                  )
                else
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(_freeProduct!.name),
                    subtitle: Text(_freeProduct!.unit),
                    trailing: IconButton(
                      key: const Key('admin-cart-offer-remove-free-product'),
                      tooltip: 'Remove free product',
                      onPressed: () => setState(() => _freeProductId = null),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ),
                if (_freeProduct != null) ...[
                  const SizedBox(height: AppSpacing.sm),
                  TextFormField(
                    key: const Key('admin-cart-offer-free-quantity'),
                    controller: _freeQuantity,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Free quantity',
                    ),
                    validator: (value) {
                      final quantity = int.tryParse(value?.trim() ?? '');
                      return quantity == null || quantity < 1 || quantity > 20
                          ? 'Enter a quantity from 1 to 20'
                          : null;
                    },
                  ),
                ],
                if (_benefitError != null) ...[
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    _benefitError!,
                    style: Theme.of(
                      context,
                    ).textTheme.bodySmall?.copyWith(color: AppColors.error),
                  ),
                ],
                const SizedBox(height: AppSpacing.lg),
                DropdownButtonFormField<_CartOfferFulfilmentChoice>(
                  key: const Key('admin-cart-offer-fulfilment'),
                  initialValue: _fulfilmentChoice,
                  decoration: const InputDecoration(
                    labelText: 'Valid fulfilment',
                  ),
                  items: const [
                    DropdownMenuItem(
                      value: _CartOfferFulfilmentChoice.all,
                      child: Text('Pickup and delivery'),
                    ),
                    DropdownMenuItem(
                      value: _CartOfferFulfilmentChoice.pickup,
                      child: Text('Pickup only'),
                    ),
                    DropdownMenuItem(
                      value: _CartOfferFulfilmentChoice.delivery,
                      child: Text('Delivery only'),
                    ),
                  ],
                  onChanged: (value) => setState(
                    () => _fulfilmentChoice =
                        value ?? _CartOfferFulfilmentChoice.all,
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.sm,
                  children: [
                    OutlinedButton.icon(
                      key: const Key('admin-cart-offer-start-date'),
                      onPressed: () => _pickDate(start: true),
                      icon: const Icon(Icons.event_outlined),
                      label: Text(
                        _startsAt == null
                            ? 'Starts immediately'
                            : 'Starts ${dateFormat.format(_startsAt!)}',
                      ),
                    ),
                    if (_startsAt != null)
                      IconButton(
                        tooltip: 'Clear start date',
                        onPressed: () => setState(() => _startsAt = null),
                        icon: const Icon(Icons.close_rounded),
                      ),
                    OutlinedButton.icon(
                      key: const Key('admin-cart-offer-end-date'),
                      onPressed: () => _pickDate(start: false),
                      icon: const Icon(Icons.event_busy_outlined),
                      label: Text(
                        _endsAt == null
                            ? 'No end date'
                            : 'Ends ${dateFormat.format(_endsAt!)}',
                      ),
                    ),
                    if (_endsAt != null)
                      IconButton(
                        tooltip: 'Clear end date',
                        onPressed: () => setState(() => _endsAt = null),
                        icon: const Icon(Icons.close_rounded),
                      ),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        key: const Key('admin-cart-offer-total-limit'),
                        controller: _totalLimit,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Total uses (optional)',
                        ),
                        validator: (value) =>
                            _optionalPositiveInteger(value ?? '') == -1
                            ? 'Enter a positive limit'
                            : null,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: TextFormField(
                        key: const Key('admin-cart-offer-customer-limit'),
                        controller: _customerLimit,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Uses per customer',
                        ),
                        validator: (value) {
                          final limit = int.tryParse(value?.trim() ?? '');
                          return limit == null || limit < 1 || limit > 10000
                              ? 'Enter 1–10,000'
                              : null;
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.sm),
                SwitchListTile.adaptive(
                  key: const Key('admin-cart-offer-active'),
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Offer active'),
                  subtitle: const Text(
                    'Disabled offers cannot be applied by customers.',
                  ),
                  value: _active,
                  onChanged: (value) => setState(() => _active = value),
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
        FilledButton(
          key: const Key('admin-save-cart-offer'),
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
  late final TextEditingController _billingName;
  late final TextEditingController _printName;
  late final TextEditingController _itemCode;
  late final TextEditingController _barcode;
  late final TextEditingController _brand;
  late final TextEditingController _subcategory;
  late final TextEditingController _description;
  late final TextEditingController _unit;
  late final TextEditingController _price;
  late final TextEditingController _discount;
  late final TextEditingController _stock;
  late String _categoryId;
  late bool _featured;
  late bool _active;
  ProductImageUpload? _selectedImage;
  bool _removeImage = false;
  String? _imageError;
  bool _pickingImage = false;

  @override
  void initState() {
    super.initState();
    final product = widget.product;
    _name = TextEditingController(text: product?.name ?? '');
    _billingName = TextEditingController(text: product?.billingName ?? '');
    _printName = TextEditingController(text: product?.printName ?? '');
    _itemCode = TextEditingController(text: product?.itemCode ?? '');
    _barcode = TextEditingController(text: product?.barcode ?? '');
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
    _active = product?.active ?? true;
  }

  @override
  void dispose() {
    _name.dispose();
    _billingName.dispose();
    _printName.dispose();
    _itemCode.dispose();
    _barcode.dispose();
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
      final upload = await pickProductImage();
      if (upload == null) return;
      if (mounted) {
        setState(() {
          _selectedImage = upload;
          _removeImage = false;
        });
      }
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
        removeImage: _removeImage,
        product: Product(
          id:
              existing?.id ??
              'product-${DateTime.now().millisecondsSinceEpoch}',
          categoryId: _categoryId,
          name: _name.text.trim(),
          brand: _brand.text.trim(),
          subcategory: _subcategory.text.trim(),
          billingName: _billingName.text.trim().isEmpty
              ? _name.text.trim()
              : _billingName.text.trim(),
          printName: _printName.text.trim().isEmpty
              ? _name.text.trim()
              : _printName.text.trim(),
          itemCode: _itemCode.text.trim(),
          barcode: _barcode.text.trim(),
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
          revision: existing?.revision ?? 0,
          visualKey: category.visualKey,
          imageUrl: existing?.imageUrl,
          featured: _featured,
          active: _active,
          available: _active != existing?.active
              ? _active
              : existing?.available ?? true,
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
                  height: widget.product == null && _selectedImage == null
                      ? null
                      : 180,
                  constraints: const BoxConstraints(minHeight: 180),
                  padding: const EdgeInsets.all(AppSpacing.sm),
                  decoration: BoxDecoration(
                    color: AppColors.canvas,
                    borderRadius: BorderRadius.circular(AppRadii.lg),
                    border: Border.all(color: AppColors.outline),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: _selectedImage != null
                      ? Image.memory(_selectedImage!.bytes, fit: BoxFit.contain)
                      : widget.product != null && !_removeImage
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
                            child: FourDotLoader(size: 22),
                          )
                        : const Icon(Icons.photo_library_outlined),
                    label: Text(
                      _selectedImage != null ||
                              (!_removeImage &&
                                  (widget.product?.imageUrl?.isNotEmpty ==
                                          true ||
                                      widget.product?.imageAsset.isNotEmpty ==
                                          true ||
                                      widget.product?.imagePath.isNotEmpty ==
                                          true))
                          ? 'Replace picture'
                          : 'Add picture',
                    ),
                  ),
                ),
                if (_selectedImage != null ||
                    (!_removeImage &&
                        (widget.product?.imageUrl?.isNotEmpty == true ||
                            widget.product?.imageAsset.isNotEmpty == true ||
                            widget.product?.imagePath.isNotEmpty == true))) ...[
                  const SizedBox(height: AppSpacing.xs),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      key: const Key('admin-remove-product-image'),
                      onPressed: () => setState(() {
                        _selectedImage = null;
                        _removeImage = true;
                      }),
                      icon: const Icon(Icons.delete_outline_rounded),
                      label: const Text('Remove picture'),
                    ),
                  ),
                ],
                if (_removeImage && widget.product != null) ...[
                  const SizedBox(height: AppSpacing.xs),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: () => setState(() => _removeImage = false),
                      icon: const Icon(Icons.undo_rounded),
                      label: const Text('Keep current picture'),
                    ),
                  ),
                ],
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
                  key: const Key('admin-product-name'),
                  controller: _name,
                  validator: (value) =>
                      _requiredLength(value, min: 2, max: 200),
                  decoration: const InputDecoration(
                    labelText: 'Storefront product name',
                    helperText: 'This is the name customers will see.',
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                DropdownButtonFormField<String>(
                  key: const Key('admin-product-category'),
                  initialValue: _categoryId,
                  isExpanded: true,
                  itemHeight: null,
                  decoration: const InputDecoration(labelText: 'Category'),
                  items: widget.categories
                      .map(
                        (category) => DropdownMenuItem(
                          value: category.id,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            child: Row(
                              children: [
                                CategoryPicture(
                                  visualKey: category.visualKey,
                                  width: 32,
                                  height: 32,
                                  padding: 1,
                                  radius: 6,
                                ),
                                const SizedBox(width: AppSpacing.sm),
                                Expanded(child: Text(category.name)),
                              ],
                            ),
                          ),
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
                        key: const Key('admin-product-brand'),
                        controller: _brand,
                        validator: (value) => _optionalLength(value, 120),
                        decoration: const InputDecoration(labelText: 'Brand'),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: TextFormField(
                        key: const Key('admin-product-subcategory'),
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
                  key: const Key('admin-product-description'),
                  controller: _description,
                  validator: (value) =>
                      _requiredLength(value, min: 2, max: 2000),
                  maxLines: 2,
                  decoration: const InputDecoration(labelText: 'Description'),
                ),
                const SizedBox(height: AppSpacing.md),
                TextFormField(
                  key: const Key('admin-product-unit'),
                  controller: _unit,
                  validator: (value) => _requiredLength(value, min: 1, max: 80),
                  decoration: const InputDecoration(
                    labelText: 'Unit',
                    hintText: '1 kg, 500 ml, 12 pieces',
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                ExpansionTile(
                  key: const Key('admin-advanced-product-details'),
                  tilePadding: EdgeInsets.zero,
                  childrenPadding: const EdgeInsets.only(bottom: AppSpacing.md),
                  initiallyExpanded:
                      _itemCode.text.isNotEmpty || _barcode.text.isNotEmpty,
                  leading: const Icon(Icons.tune_rounded),
                  title: const Text('Billing, barcode & SKU details'),
                  subtitle: const Text(
                    'Optional internal names and codes used by staff.',
                  ),
                  children: [
                    TextFormField(
                      key: const Key('admin-product-billing-name'),
                      controller: _billingName,
                      validator: (value) => _optionalLength(value, 200),
                      decoration: const InputDecoration(
                        labelText: 'Billing name',
                        hintText: 'Defaults to the storefront name',
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    TextFormField(
                      key: const Key('admin-product-print-name'),
                      controller: _printName,
                      validator: (value) => _optionalLength(value, 200),
                      decoration: const InputDecoration(
                        labelText: 'Receipt / print name',
                        hintText: 'Defaults to the storefront name',
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            key: const Key('admin-product-item-code'),
                            controller: _itemCode,
                            validator: (value) => _optionalLength(value, 80),
                            decoration: const InputDecoration(
                              labelText: 'SKU / item code',
                            ),
                          ),
                        ),
                        const SizedBox(width: AppSpacing.md),
                        Expanded(
                          child: TextFormField(
                            key: const Key('admin-product-barcode'),
                            controller: _barcode,
                            validator: (value) => _optionalLength(value, 80),
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: 'Barcode',
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        key: const Key('admin-product-price'),
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
                        key: const Key('admin-product-discount'),
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
                  key: const Key('admin-product-stock'),
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
                SwitchListTile.adaptive(
                  key: const Key('admin-product-active'),
                  contentPadding: EdgeInsets.zero,
                  value: _active,
                  onChanged: (value) => setState(() => _active = value),
                  title: const Text('Visible in customer catalogue'),
                  subtitle: Text(
                    _active
                        ? 'Customers can find and buy this product.'
                        : 'Archived products remain available to staff only.',
                  ),
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
        FilledButton(
          key: const Key('admin-save-product'),
          onPressed: _save,
          child: const Text('Save product'),
        ),
      ],
    );
  }
}

class _ProductEditorResult {
  const _ProductEditorResult({
    required this.product,
    this.image,
    this.removeImage = false,
  });

  final Product product;
  final ProductImageUpload? image;
  final bool removeImage;
}

class _OrderPricingResult {
  const _OrderPricingResult({
    required this.minimumOrderPaise,
    required this.deliveryChargePaise,
    required this.freeDeliveryThresholdPaise,
  });

  final int minimumOrderPaise;
  final int deliveryChargePaise;
  final int freeDeliveryThresholdPaise;
}
