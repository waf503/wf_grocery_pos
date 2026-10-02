import 'package:go_router/go_router.dart';

import '../../features/categories/categories_screen.dart';
import '../../features/cash/cash_screen.dart';
import '../../features/customers/customers_screen.dart';
import '../../features/dashboard/dashboard_screen.dart';
import '../../features/inventory/inventory_screen.dart';
import '../../features/pos/pos_screen.dart';
import '../../features/reports/reports_screen.dart';
import '../../features/units/units_screen.dart';
import '../../shared/widgets/app_shell.dart';

final GoRouter appRouter = GoRouter(
  initialLocation: '/dashboard',
  routes: [
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
      ],
    ),
  ],
);
