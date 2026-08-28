import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../features/cart/widgets/active_cart_ribbon.dart';
import '../../features/store/widgets/store_realtime_sync.dart';

class CustomerShell extends StatelessWidget {
  const CustomerShell({required this.navigationShell, super.key});

  final StatefulNavigationShell navigationShell;

  @override
  Widget build(BuildContext context) {
    void navigate(int index) {
      navigationShell.goBranch(
        index,
        initialLocation: index == navigationShell.currentIndex,
      );
    }

    return StoreRealtimeSync(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final desktop = constraints.maxWidth >= 900;
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
                            Expanded(child: navigationShell),
                            const ActiveCartRibbon(),
                          ],
                        ),
                      ),
                    ],
                  )
                : navigationShell,
            bottomNavigationBar: desktop
                ? null
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const ActiveCartRibbon(respectBottomSafeArea: false),
                      NavigationBar(
                        selectedIndex: navigationShell.currentIndex,
                        onDestinationSelected: navigate,
                        destinations: const [
                          NavigationDestination(
                            key: Key('customer-tab-home'),
                            icon: Icon(Icons.home_outlined),
                            selectedIcon: Icon(Icons.home_rounded),
                            label: 'Home',
                          ),
                          NavigationDestination(
                            key: Key('customer-tab-categories'),
                            icon: Icon(Icons.grid_view_outlined),
                            selectedIcon: Icon(Icons.grid_view_rounded),
                            label: 'Categories',
                          ),
                          NavigationDestination(
                            key: Key('customer-tab-orders'),
                            icon: Icon(Icons.receipt_long_outlined),
                            selectedIcon: Icon(Icons.receipt_long_rounded),
                            label: 'Orders',
                          ),
                          NavigationDestination(
                            key: Key('customer-tab-profile'),
                            icon: Icon(Icons.person_outline_rounded),
                            selectedIcon: Icon(Icons.person_rounded),
                            label: 'Profile',
                          ),
                        ],
                      ),
                    ],
                  ),
          );
        },
      ),
    );
  }
}
