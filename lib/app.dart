import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';

import 'core/database/app_database.dart';
import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'features/cash/data/drift_cash_repository.dart';
import 'features/catalog/data/drift_catalog_repository.dart';
import 'features/catalog/data/open_facts_client.dart';
import 'features/catalog/data/product_lookup_service.dart';
import 'features/catalog/data/vtex_retail_client.dart';
import 'features/categories/data/drift_category_repository.dart';
import 'features/customers/data/drift_customer_repository.dart';
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
        ChangeNotifierProvider(
          lazy: false,
          create: (_) => CustomerProvider(DriftCustomerRepository(database)),
        ),
        ChangeNotifierProvider(
          lazy: false,
          create: (_) => SalesProvider(DriftSaleRepository(database)),
        ),
        ChangeNotifierProvider(
          lazy: false,
          create: (_) => CashProvider(DriftCashRepository(database)),
        ),
        ChangeNotifierProvider(create: (_) => PosProvider()),
        Provider<ProductLookupService>(
          create: (_) => ProductLookupService(
            DriftCatalogRepository(database),
            // Primero las bases abiertas; si no conocen el código, el
            // catálogo de la tienda en línea (que sí tiene productos locales).
            ChainedLookup([OpenFactsClient(), VtexRetailClient()]),
          ),
          dispose: (_, service) => service.dispose(),
        ),
      ],
      child: MaterialApp.router(
        title: 'Mi Tienda POS',
        debugShowCheckedModeBanner: false,
        // Textos de los componentes de Material (selector de fechas, etc.) en español.
        locale: const Locale('es', 'MX'),
        supportedLocales: const [Locale('es', 'MX'), Locale('es')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        theme: AppTheme.light(),
        routerConfig: appRouter,
      ),
    );
  }
}
