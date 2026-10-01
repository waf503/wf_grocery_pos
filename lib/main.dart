import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'app.dart';
import 'core/database/app_database.dart';
import 'features/categories/data/category_seeder.dart';
import 'features/products/data/product_seeder.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('es_MX');

  final database = AppDatabase();
  final categoryIds = await seedCategoriesIfEmpty(database);
  await seedProductsIfEmpty(database, categoryIds);

  runApp(GroceryPosApp(database: database));
}
