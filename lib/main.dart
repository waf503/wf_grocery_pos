import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'app.dart';
import 'core/database/app_database.dart';
import 'core/database/initial_catalog_seeder.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('es_MX');

  final database = AppDatabase();
  // Categorías y unidades básicas para poder registrar productos desde el
  // primer día. Los productos NO se siembran: el inventario de una tienda
  // real empieza vacío (el catálogo de ejemplo solo se usa en las pruebas).
  await seedInitialCatalogIfEmpty(database);

  runApp(GroceryPosApp(database: database));
}
