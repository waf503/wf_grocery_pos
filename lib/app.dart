import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'core/database/app_database.dart';
import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'features/categories/data/drift_category_repository.dart';
import 'features/products/data/drift_product_repository.dart';
import 'features/units/data/drift_unit_repository.dart';
import 'state/cash_provider.dart';
import 'state/category_provider.dart';
import 'state/customer_provider.dart';
import 'state/inventory_provider.dart';
import 'state/pos_provider.dart';
import 'state/sales_provider.dart';
import 'state/unit_provider.dart';

class GroceryPosApp extends StatelessWidget {
  const GroceryPosApp({super.key, required this.database});

  final AppDatabase database;

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(
          create: (_) => CategoryProvider(DriftCategoryRepository(database)),
        ),
        ChangeNotifierProvider(
          create: (_) => UnitProvider(DriftUnitRepository(database)),
        ),
        ChangeNotifierProvider(
          create: (_) =>
              InventoryProvider(DriftProductRepository(database)),
        ),
        ChangeNotifierProvider(create: (_) => CustomerProvider()),
        ChangeNotifierProvider(create: (_) => SalesProvider()),
        ChangeNotifierProvider(create: (_) => CashProvider()),
        ChangeNotifierProvider(create: (_) => PosProvider()),
      ],
      child: MaterialApp.router(
        title: 'Mi Tienda POS',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(),
        routerConfig: appRouter,
      ),
    );
  }
}
