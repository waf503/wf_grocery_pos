import 'package:go_router/go_router.dart';

import '../../features/auth/login_screen.dart';
import '../../features/auth/setup_screen.dart';
import '../../features/auth/users_screen.dart';
import '../../features/categories/categories_screen.dart';
import '../../features/cash/cash_screen.dart';
import '../../features/customers/customers_screen.dart';
import '../../features/dashboard/dashboard_screen.dart';
import '../../features/inventory/inventory_screen.dart';
import '../../features/pos/pos_screen.dart';
import '../../features/reports/reports_screen.dart';
import '../../features/settings/business_screen.dart';
import '../../features/sales/sales_screen.dart';
import '../../features/units/units_screen.dart';
import '../../shared/widgets/app_shell.dart';
import '../../state/auth_provider.dart';
import '../security/permissions.dart';

/// El router depende de la sesión: sin usuarios se va a la configuración
/// inicial; sin sesión, al acceso con PIN; y un cajero no puede abrir (ni
/// escribiendo la ruta) las pantallas de administrador.
GoRouter createAppRouter(AuthProvider auth) {
  return GoRouter(
    initialLocation: '/dashboard',
    refreshListenable: auth,
    redirect: (context, state) {
      final location = state.uri.path;
      if (!auth.loaded) return null;
      if (auth.needsSetup) return location == '/setup' ? null : '/setup';
      final user = auth.currentUser;
      if (user == null) return location == '/login' ? null : '/login';
      if (location == '/login' || location == '/setup' || !canAccess(user, location)) {
        return homeFor(user);
      }
      return null;
    },
    routes: [
      GoRoute(path: '/setup', builder: (context, state) => const SetupScreen()),
      GoRoute(path: '/login', builder: (context, state) => const LoginScreen()),
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) => AppShell(navigationShell: navigationShell),
        branches: [
          StatefulShellBranch(routes: [
            GoRoute(path: '/dashboard', builder: (context, state) => const DashboardScreen()),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(path: '/pos', builder: (context, state) => const PosScreen()),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(path: '/sales', builder: (context, state) => const SalesScreen()),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(path: '/inventory', builder: (context, state) => const InventoryScreen()),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(path: '/categories', builder: (context, state) => const CategoriesScreen()),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(path: '/units', builder: (context, state) => const UnitsScreen()),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(path: '/customers', builder: (context, state) => const CustomersScreen()),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(path: '/cash', builder: (context, state) => const CashScreen()),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(path: '/reports', builder: (context, state) => const ReportsScreen()),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(path: '/users', builder: (context, state) => const UsersScreen()),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(path: '/business', builder: (context, state) => const BusinessScreen()),
          ]),
        ],
      ),
    ],
  );
}
