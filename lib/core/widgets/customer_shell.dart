import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../features/store/widgets/store_realtime_sync.dart';

class CustomerShell extends StatelessWidget {
  const CustomerShell({required this.location, required this.child, super.key});

  final String location;
  final Widget child;

  int get _selectedIndex {
    if (location.startsWith('/categories') ||
        location.startsWith('/products')) {
      return 1;
    }
    if (location.startsWith('/orders')) return 2;
    if (location.startsWith('/profile')) return 3;
    return 0;
  }

  @override
  Widget build(BuildContext context) {
    void navigate(int index) {
      final destination = switch (index) {
        0 => '/home',
        1 => '/categories',
        2 => '/orders',
        _ => '/profile',
      };
      context.go(destination);
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
                          selectedIndex: _selectedIndex,
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
                      Expanded(child: child),
                    ],
                  )
                : child,
            bottomNavigationBar: desktop
                ? null
                : NavigationBar(
                    selectedIndex: _selectedIndex,
                    onDestinationSelected: navigate,
                    destinations: const [
                      NavigationDestination(
                        icon: Icon(Icons.home_outlined),
                        selectedIcon: Icon(Icons.home_rounded),
                        label: 'Home',
                      ),
                      NavigationDestination(
                        icon: Icon(Icons.grid_view_outlined),
                        selectedIcon: Icon(Icons.grid_view_rounded),
                        label: 'Categories',
                      ),
                      NavigationDestination(
                        icon: Icon(Icons.receipt_long_outlined),
                        selectedIcon: Icon(Icons.receipt_long_rounded),
                        label: 'Orders',
                      ),
                      NavigationDestination(
                        icon: Icon(Icons.person_outline_rounded),
                        selectedIcon: Icon(Icons.person_rounded),
                        label: 'Profile',
                      ),
                    ],
                  ),
          );
        },
      ),
    );
  }
}
