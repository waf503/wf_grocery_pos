import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
import '../../../core/text/product_tags.dart';

/// Si la tabla `products` está vacía (primer arranque de la app en este
/// dispositivo), la llena con un catálogo de ejemplo. En corridas
/// posteriores no hace nada.
///
/// [categoryIds] es el mapa nombre → id que devuelve `seedCategoriesIfEmpty`
/// — las categorías deben sembrarse ANTES que los productos, porque cada
/// producto necesita un `categoryId` real que ya exista.
Future<void> seedProductsIfEmpty(
  AppDatabase db,
  Map<String, String> categoryIds,
  Map<String, String> unitIds,
) async {
  final existing = await db.select(db.productsTable).get();
  if (existing.isNotEmpty) return;

  ProductsTableCompanion product(
    String name,
    String categoryName, {
    String unit = 'Pieza',
    required double price,
    required double cost,
    required double stock,
    double minStock = 5,
  }) {
    return ProductsTableCompanion.insert(
      name: name,
      categoryId: categoryIds[categoryName]!,
      unitId: unitIds[unit]!,
      price: price,
      cost: cost,
      stock: Value(stock),
      minStock: Value(minStock),
      tags: Value(buildTags(name)),
    );
  }

  // "Gaseosas" es la subcategoría de "Bebidas" sembrada por
  // seedCategoriesIfEmpty — así el catálogo de ejemplo ya demuestra la
  // anidación desde el primer arranque.
  await db.batch((batch) {
    batch.insertAll(db.productsTable, [
      product('Coca-Cola Lata 355ml', 'Gaseosas', price: 12.0, cost: 8.0, stock: 60, minStock: 10),
      product('Coca-Cola Botella 600ml', 'Gaseosas', price: 18.0, cost: 13.0, stock: 40, minStock: 10),
      product('Coca-Cola Botella 2L', 'Gaseosas', price: 32.0, cost: 24.0, stock: 15),
      product('Arroz Morelos 1kg', 'Abarrotes', price: 32.5, cost: 24.0, stock: 40),
      product('Frijol Negro 1kg', 'Abarrotes', price: 34.0, cost: 26.5, stock: 35),
      product('Aceite Capullo 1L', 'Abarrotes', price: 48.0, cost: 38.0, stock: 3),
      product('Azúcar Estándar 1kg', 'Abarrotes', price: 28.0, cost: 21.0, stock: 50),
      product('Agua Ciel 1L', 'Bebidas', price: 12.0, cost: 8.0, stock: 4, minStock: 10),
      product('Leche Lala 1L', 'Lácteos', price: 26.0, cost: 20.0, stock: 24),
      product('Huevo Blanco Granel', 'Lácteos', unit: 'Kilogramo', price: 42.0, cost: 34.0, stock: 18),
      product('Bolillo', 'Panadería', price: 3.0, cost: 1.5, stock: 80),
      product('Pan de Caja Bimbo Grande', 'Panadería', price: 44.0, cost: 34.0, stock: 2),
      product('Jabón para Trastes', 'Limpieza', price: 22.0, cost: 15.0, stock: 30),
      product('Papel Higiénico 4 rollos', 'Limpieza', unit: 'Paquete', price: 45.0, cost: 33.0, stock: 20),
      product('Sabritas Original', 'Botanas', price: 17.0, cost: 12.0, stock: 45),
      product('Galletas Marías', 'Botanas', price: 15.0, cost: 10.0, stock: 38),
      product('Plátano Granel', 'Frutas y Verduras', unit: 'Kilogramo', price: 16.0, cost: 10.0, stock: 25),
      product('Jitomate Granel', 'Frutas y Verduras', unit: 'Kilogramo', price: 22.0, cost: 15.0, stock: 20),
    ]);
  });
}
