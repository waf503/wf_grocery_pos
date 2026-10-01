import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class _NavDestination {
  const _NavDestination(this.label, this.icon, this.selectedIcon);

  final String label;
  final IconData icon;
  final IconData selectedIcon;
}

const List<_NavDestination> _destinations = [
  _NavDestination('Inicio', Icons.dashboard_outlined, Icons.dashboard),
  _NavDestination('Punto de Venta', Icons.point_of_sale_outlined, Icons.point_of_sale),
  _NavDestination('Inventario', Icons.inventory_2_outlined, Icons.inventory_2),
  _NavDestination('Categorías', Icons.category_outlined, Icons.category),
  _NavDestination('Clientes', Icons.people_outline, Icons.people),
  _NavDestination('Caja', Icons.account_balance_wallet_outlined, Icons.account_balance_wallet),
  _NavDestination('Reportes', Icons.bar_chart_outlined, Icons.bar_chart),
];

/// Shell de navegación persistente para las secciones principales del ERP.
///
/// Usa [NavigationRail] extendido en pantallas anchas (escritorio/web) y un
/// [Drawer] + [BottomNavigationBar] en pantallas angostas.
class AppShell extends StatelessWidget {
  const AppShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  static const double _wideBreakpoint = 900;

  void _onDestinationSelected(int index) {
    navigationShell.goBranch(
      index,
      initialLocation: index == navigationShell.currentIndex,
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= _wideBreakpoint;
        if (isWide) {
          return Scaffold(
            body: Row(
              children: [
                NavigationRail(
                  extended: constraints.maxWidth >= 1200,
                  selectedIndex: navigationShell.currentIndex,
                  onDestinationSelected: _onDestinationSelected,
                  leading: const Padding(
                    padding: EdgeInsets.symmetric(vertical: 16),
                    child: _BrandMark(),
                  ),
                  destinations: [
                    for (final d in _destinations)
                      NavigationRailDestination(
                        icon: Icon(d.icon),
                        selectedIcon: Icon(d.selectedIcon),
                        label: Text(d.label),
                      ),
                  ],
                ),
                const VerticalDivider(width: 1),
                Expanded(child: navigationShell),
              ],
            ),
          );
        }

        return Scaffold(
          appBar: AppBar(title: Text(_destinations[navigationShell.currentIndex].label)),
          drawer: Drawer(
            child: SafeArea(
              child: ListView(
                children: [
                  const Padding(
                    padding: EdgeInsets.all(16),
                    child: _BrandMark(),
                  ),
                  for (int i = 0; i < _destinations.length; i++)
                    ListTile(
                      leading: Icon(
                        i == navigationShell.currentIndex
                            ? _destinations[i].selectedIcon
                            : _destinations[i].icon,
                      ),
                      title: Text(_destinations[i].label),
                      selected: i == navigationShell.currentIndex,
                      onTap: () {
                        Navigator.of(context).pop();
                        _onDestinationSelected(i);
                      },
                    ),
                ],
              ),
            ),
          ),
          body: navigationShell,
          bottomNavigationBar: NavigationBar(
            selectedIndex: navigationShell.currentIndex,
            onDestinationSelected: _onDestinationSelected,
            destinations: [
              for (final d in _destinations)
                NavigationDestination(
                  icon: Icon(d.icon),
                  selectedIcon: Icon(d.selectedIcon),
                  label: d.label,
                ),
            ],
          ),
        );
      },
    );
  }
}

class _BrandMark extends StatelessWidget {
  const _BrandMark();

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        CircleAvatar(
          backgroundColor: Theme.of(context).colorScheme.primary,
          foregroundColor: Theme.of(context).colorScheme.onPrimary,
          child: const Icon(Icons.storefront),
        ),
        const SizedBox(width: 8),
        Text(
          'Mi Tienda',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
        ),
      ],
    );
  }
}
