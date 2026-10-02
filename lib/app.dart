import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'core/database/app_database.dart';
import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'features/cash/data/drift_cash_repository.dart';
import 'features/categories/data/drift_category_repository.dart';
import 'features/products/data/drift_product_repository.dart';
import 'features/sales/data/drift_sale_repository.dart';
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
      // Los providers respaldados por la base de datos van con `lazy: false`:
      // por defecto Provider los crea hasta la PRIMERA vez que alguien los
      // lee, y su primera lectura de la base de datos es asíncrona. Así, un
      // `context.read<UnitProvider>()` hecho al abrir un diálogo encontraba la
      // lista vacía (el bug de "Falta crear una unidad"). Creados al arrancar,
      // ya tienen sus datos cuando el usuario llega a la pantalla.
      providers: [
        ChangeNotifierProvider(
          lazy: false,
          create: (_) => CategoryProvider(DriftCategoryRepository(database)),
        ),
        ChangeNotifierProvider(
          lazy: false,
          create: (_) => UnitProvider(DriftUnitRepository(database)),
        ),
        ChangeNotifierProvider(
          lazy: false,
          create: (_) => InventoryProvider(DriftProductRepository(database)),
        ),
        ChangeNotifierProvider(create: (_) => CustomerProvider()),
        ChangeNotifierProvider(
          lazy: false,
          create: (_) => SalesProvider(DriftSaleRepository(database)),
        ),
        ChangeNotifierProvider(
          lazy: false,
          create: (_) => CashProvider(DriftCashRepository(database)),
        ),
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
