import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/cart/widgets/active_cart_ribbon.dart';
import '../../features/store/providers/store_provider.dart';
import '../theme/app_colors.dart';
import '../theme/app_shadows.dart';
import '../theme/app_motion.dart';
import 'customer_tab_transition.dart';

class CustomerShell extends ConsumerWidget {
  const CustomerShell({required this.navigationShell, super.key});

  final StatefulNavigationShell navigationShell;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cartCount = ref.watch(
      storeProvider.select((store) => store.cartCount),
    );
    void navigate(int index) {
      FocusManager.instance.primaryFocus?.unfocus();
      navigationShell.goBranch(
        index,
        initialLocation: index == navigationShell.currentIndex,
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final desktop = constraints.maxWidth >= 900;
        final branch = CustomerTabTransition(
          index: navigationShell.currentIndex,
          child: navigationShell,
        );
        return Scaffold(
          body: desktop
              ? Row(
                  children: [
                    SafeArea(
                      child: NavigationRail(
                        extended: constraints.maxWidth >= 1120,
                        minExtendedWidth: 224,
                        selectedIndex: navigationShell.currentIndex,
                        onDestinationSelected: navigate,
                        labelType: constraints.maxWidth >= 1120
                            ? NavigationRailLabelType.none
                            : NavigationRailLabelType.all,
                        leading: const Padding(
                          padding: EdgeInsets.only(top: 12, bottom: 24),
                          child: Icon(Icons.eco_rounded, size: 34),
                        ),
                        destinations: const [
                          NavigationRailDestination(
                            icon: Icon(Icons.home_outlined),
                            selectedIcon: Icon(Icons.home_rounded),
                            label: Text('Home'),
                          ),
                          NavigationRailDestination(
                            icon: Icon(Icons.grid_view_outlined),
                            selectedIcon: Icon(Icons.grid_view_rounded),
                            label: Text('Categories'),
                          ),
                          NavigationRailDestination(
                            icon: Icon(Icons.receipt_long_outlined),
                            selectedIcon: Icon(Icons.receipt_long_rounded),
                            label: Text('Orders'),
                          ),
                          NavigationRailDestination(
                            icon: Icon(Icons.person_outline_rounded),
                            selectedIcon: Icon(Icons.person_rounded),
                            label: Text('Profile'),
                          ),
                        ],
                      ),
                    ),
                    const VerticalDivider(width: 1),
                    Expanded(
                      child: Column(
                        children: [
                          Expanded(child: branch),
                          const ActiveCartRibbon(),
                        ],
                      ),
                    ),
                  ],
                )
              : branch,
          bottomNavigationBar: desktop
              ? null
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const ActiveCartRibbon(respectBottomSafeArea: false),
                    DecoratedBox(
                      decoration: BoxDecoration(
                        color: AppColors.of(context).surface,
                        border: Border(
                          top: BorderSide(color: AppColors.of(context).outline),
                        ),
                        boxShadow: AppShadows.of(context),
                      ),
                      child: NavigationBar(
                        height: 76,
                        indicatorColor: AppColors.of(context).brandSoft,
                        labelBehavior:
                            MediaQuery.textScalerOf(context).scale(12) > 18
                            ? NavigationDestinationLabelBehavior.alwaysHide
                            : NavigationDestinationLabelBehavior.alwaysShow,
                        animationDuration: AppMotion.duration(
                          context,
                          const Duration(milliseconds: 200),
                        ),
                        selectedIndex: navigationShell.currentIndex < 2
                            ? navigationShell.currentIndex
                            : navigationShell.currentIndex + 1,
                        onDestinationSelected: (index) {
                          if (index == 2) {
                            FocusManager.instance.primaryFocus?.unfocus();
                            context.push('/cart');
                          } else {
                            navigate(index < 2 ? index : index - 1);
                          }
                        },
                        destinations: [
                          const NavigationDestination(
                            key: Key('customer-tab-home'),
                            icon: Icon(Icons.home_outlined),
                            selectedIcon: Icon(Icons.home_rounded),
                            label: 'Home',
                          ),
                          const NavigationDestination(
                            key: Key('customer-tab-categories'),
                            icon: Icon(Icons.grid_view_outlined),
                            selectedIcon: Icon(Icons.grid_view_rounded),
                            label: 'Categories',
                          ),
                          NavigationDestination(
                            key: const Key('customer-open-cart'),
                            label: '',
                            tooltip: 'Open cart',
                            icon: Semantics(
                              label: 'Open cart',
                              child: Badge.count(
                                count: cartCount,
                                isLabelVisible: cartCount > 0,
                                child: Container(
                                  width: 52,
                                  height: 52,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    gradient: LinearGradient(
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                      colors: [
                                        AppColors.of(context).brand600,
                                        AppColors.of(context).brand500,
                                      ],
                                    ),
                                    boxShadow: AppShadows.of(
                                      context,
                                      elevated: true,
                                    ),
                                  ),
                                  child: Icon(
                                    Icons.shopping_cart_outlined,
                                    color: AppColors.of(context).onBrand,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const NavigationDestination(
                            key: Key('customer-tab-orders'),
                            icon: Icon(Icons.receipt_long_outlined),
                            selectedIcon: Icon(Icons.receipt_long_rounded),
                            label: 'Orders',
                          ),
                          const NavigationDestination(
                            key: Key('customer-tab-profile'),
                            icon: Icon(Icons.person_outline_rounded),
                            selectedIcon: Icon(Icons.person_rounded),
                            label: 'Profile',
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
        );
      },
    );
  }
}
