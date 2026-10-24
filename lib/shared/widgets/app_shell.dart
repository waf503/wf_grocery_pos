import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/security/permissions.dart';
import '../../models/app_user.dart';
import '../../state/auth_provider.dart';
import '../../state/settings_provider.dart';

class _NavDestination {
  const _NavDestination(this.path, this.label, this.icon, this.selectedIcon);

  /// Ruta de la pantalla; su posición en [_destinations] es la de su rama en el router.
  final String path;
  final String label;
  final IconData icon;
  final IconData selectedIcon;
}

const List<_NavDestination> _destinations = [
  _NavDestination('/dashboard', 'Inicio', Icons.dashboard_outlined, Icons.dashboard),
  _NavDestination('/pos', 'Punto de Venta', Icons.point_of_sale_outlined, Icons.point_of_sale),
  _NavDestination('/sales', 'Ventas', Icons.receipt_long_outlined, Icons.receipt_long),
  _NavDestination('/inventory', 'Inventario', Icons.inventory_2_outlined, Icons.inventory_2),
  _NavDestination('/categories', 'Categorías', Icons.category_outlined, Icons.category),
  _NavDestination('/units', 'Unidades', Icons.straighten_outlined, Icons.straighten),
  _NavDestination('/customers', 'Clientes', Icons.people_outline, Icons.people),
  _NavDestination('/cash', 'Caja', Icons.account_balance_wallet_outlined, Icons.account_balance_wallet),
  _NavDestination('/reports', 'Reportes', Icons.bar_chart_outlined, Icons.bar_chart),
  _NavDestination('/users', 'Usuarios', Icons.manage_accounts_outlined, Icons.manage_accounts),
  _NavDestination('/business', 'Negocio', Icons.store_outlined, Icons.store),
];

/// Shell de navegación persistente para las secciones principales del ERP.
///
/// Usa [NavigationRail] extendido en pantallas anchas (escritorio/web) y un
/// [Drawer] + [BottomNavigationBar] en pantallas angostas. Solo muestra las
/// secciones que el rol del usuario en sesión puede abrir.
class AppShell extends StatelessWidget {
  const AppShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  static const double _wideBreakpoint = 900;

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final user = auth.currentUser;

    // `branch` es la posición real de cada sección en el router.
    final visible = <({int branch, _NavDestination destination})>[
      for (var i = 0; i < _destinations.length; i++)
        if (user != null && canAccess(user, _destinations[i].path)) (branch: i, destination: _destinations[i]),
    ];
    // Al cerrar sesión el shell sigue montado un instante, ya sin usuario.
    if (visible.isEmpty) return const Scaffold();

    final selected = visible.indexWhere((v) => v.branch == navigationShell.currentIndex);
    final selectedIndex = selected < 0 ? 0 : selected;

    void onSelected(int visibleIndex) {
      final branch = visible[visibleIndex].branch;
      navigationShell.goBranch(branch, initialLocation: branch == navigationShell.currentIndex);
    }

    final userBadge = user == null
        ? const SizedBox.shrink()
        : _UserBadge(name: user.name, role: user.role.label, onLogout: auth.logout);

    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= _wideBreakpoint;
        if (isWide) {
          final extended = constraints.maxWidth >= 1200;
          return Scaffold(
            body: Row(
              children: [
                NavigationRail(
                  extended: extended,
                  selectedIndex: selectedIndex,
                  onDestinationSelected: onSelected,
                  leading: const Padding(
                    padding: EdgeInsets.symmetric(vertical: 16),
                    child: _BrandMark(),
                  ),
                  trailing: Expanded(
                    child: Align(
                      alignment: Alignment.bottomCenter,
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 16),
                        child: extended
                            ? userBadge
                            : IconButton(
                                tooltip: 'Cerrar sesión (${user?.name ?? ''})',
                                icon: const Icon(Icons.lock_outline),
                                onPressed: auth.logout,
                              ),
                      ),
                    ),
                  ),
                  destinations: [
                    for (final v in visible)
                      NavigationRailDestination(
                        icon: Icon(v.destination.icon),
                        selectedIcon: Icon(v.destination.selectedIcon),
                        label: Text(v.destination.label),
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
          appBar: AppBar(
            title: Text(visible[selectedIndex].destination.label),
            actions: [
              IconButton(tooltip: 'Cerrar sesión', icon: const Icon(Icons.lock_outline), onPressed: auth.logout),
            ],
          ),
          drawer: Drawer(
            child: SafeArea(
              child: ListView(
                children: [
                  const Padding(
                    padding: EdgeInsets.all(16),
                    child: _BrandMark(),
                  ),
                  for (var i = 0; i < visible.length; i++)
                    ListTile(
                      leading: Icon(
                        i == selectedIndex ? visible[i].destination.selectedIcon : visible[i].destination.icon,
                      ),
                      title: Text(visible[i].destination.label),
                      selected: i == selectedIndex,
                      onTap: () {
                        Navigator.of(context).pop();
                        onSelected(i);
                      },
                    ),
                  const Divider(),
                  Padding(padding: const EdgeInsets.all(16), child: userBadge),
                ],
              ),
            ),
          ),
          body: navigationShell,
          bottomNavigationBar: visible.length < 2
              ? null
              : NavigationBar(
                  selectedIndex: selectedIndex,
                  onDestinationSelected: onSelected,
                  destinations: [
                    for (final v in visible)
                      NavigationDestination(
                        icon: Icon(v.destination.icon),
                        selectedIcon: Icon(v.destination.selectedIcon),
                        label: v.destination.label,
                      ),
                  ],
                ),
        );
      },
    );
  }
}

/// Quién tiene la sesión abierta, con el botón para cerrarla.
class _UserBadge extends StatelessWidget {
  const _UserBadge({required this.name, required this.role, required this.onLogout});

  final String name;
  final String role;
  final VoidCallback onLogout;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(name, style: Theme.of(context).textTheme.titleSmall),
            Text(role, style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
        const SizedBox(width: 8),
        IconButton(tooltip: 'Cerrar sesión', icon: const Icon(Icons.lock_outline), onPressed: onLogout),
      ],
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
        Flexible(
          child: Text(
            context.watch<SettingsProvider>().businessName,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
          ),
        ),
      ],
    );
  }
}
