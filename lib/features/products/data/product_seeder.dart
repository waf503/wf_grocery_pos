import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';

/// Si la tabla `products` está vacía (primer arranque de la app en este
/// dispositivo), la llena con un catálogo de ejemplo — incluyendo una
/// familia con varias presentaciones (Coca-Cola), para demostrar el
/// patrón Producto → Variante. En corridas posteriores no hace nada.
///
/// [categoryIds] es el mapa nombre → id que devuelve `seedCategoriesIfEmpty`
/// — las categorías deben sembrarse ANTES que los productos, porque cada
/// producto necesita un `categoryId` real que ya exista.
Future<void> seedProductsIfEmpty(AppDatabase db, Map<String, String> categoryIds) async {
  final existing = await db.select(db.productsTable).get();
  if (existing.isNotEmpty) return;

  Future<void> family(
    String name,
    String categoryName,
    List<({String presentation, String unit, double price, double cost, double stock, double minStock})> variants,
  ) async {
    final row = await db.into(db.productsTable).insertReturning(
          ProductsTableCompanion.insert(name: name, categoryId: categoryIds[categoryName]!),
        );
    await db.batch((batch) {
      batch.insertAll(
        db.productVariantsTable,
        [
          for (final v in variants)
            ProductVariantsTableCompanion.insert(
              productId: row.id,
              presentation: v.presentation,
              unit: v.unit,
              price: v.price,
              cost: v.cost,
              stock: Value(v.stock),
              minStock: Value(v.minStock),
            ),
        ],
      );
    });
  }

  // "Gaseosas" es la subcategoría de "Bebidas" sembrada por
  // seedCategoriesIfEmpty — así el catálogo de ejemplo ya demuestra la
  // anidación desde el primer arranque.
  await family('Coca-Cola', 'Gaseosas', [
    (presentation: 'Lata 355ml', unit: 'pieza', price: 12.0, cost: 8.0, stock: 60, minStock: 10),
    (presentation: 'Botella 600ml', unit: 'pieza', price: 18.0, cost: 13.0, stock: 40, minStock: 10),
    (presentation: 'Botella 2L', unit: 'pieza', price: 32.0, cost: 24.0, stock: 15, minStock: 5),
  ]);

  await family('Arroz Morelos', 'Abarrotes', [
    (presentation: '1kg', unit: 'pieza', price: 32.5, cost: 24.0, stock: 40, minStock: 5),
  ]);
  await family('Frijol Negro', 'Abarrotes', [
    (presentation: '1kg', unit: 'pieza', price: 34.0, cost: 26.5, stock: 35, minStock: 5),
  ]);
  await family('Aceite Capullo', 'Abarrotes', [
    (presentation: '1L', unit: 'pieza', price: 48.0, cost: 38.0, stock: 3, minStock: 5),
  ]);
  await family('Azúcar Estándar', 'Abarrotes', [
    (presentation: '1kg', unit: 'pieza', price: 28.0, cost: 21.0, stock: 50, minStock: 5),
  ]);
  await family('Agua Ciel', 'Bebidas', [
    (presentation: '1L', unit: 'pieza', price: 12.0, cost: 8.0, stock: 4, minStock: 10),
  ]);
  await family('Leche Lala', 'Lácteos', [
    (presentation: '1L', unit: 'pieza', price: 26.0, cost: 20.0, stock: 24, minStock: 5),
  ]);
  await family('Huevo Blanco', 'Lácteos', [
    (presentation: 'Granel', unit: 'kg', price: 42.0, cost: 34.0, stock: 18, minStock: 5),
  ]);
  await family('Bolillo', 'Panadería', [
    (presentation: 'Pieza', unit: 'pieza', price: 3.0, cost: 1.5, stock: 80, minStock: 5),
  ]);
  await family('Pan de Caja Bimbo', 'Panadería', [
    (presentation: 'Grande', unit: 'pieza', price: 44.0, cost: 34.0, stock: 2, minStock: 5),
  ]);
  await family('Jabón para Trastes', 'Limpieza', [
    (presentation: 'Botella', unit: 'pieza', price: 22.0, cost: 15.0, stock: 30, minStock: 5),
  ]);
  await family('Papel Higiénico', 'Limpieza', [
    (presentation: '4 rollos', unit: 'paquete', price: 45.0, cost: 33.0, stock: 20, minStock: 5),
  ]);
  await family('Sabritas Original', 'Botanas', [
    (presentation: 'Pieza', unit: 'pieza', price: 17.0, cost: 12.0, stock: 45, minStock: 5),
  ]);
  await family('Galletas Marías', 'Botanas', [
    (presentation: 'Paquete', unit: 'pieza', price: 15.0, cost: 10.0, stock: 38, minStock: 5),
  ]);
  await family('Plátano', 'Frutas y Verduras', [
    (presentation: 'Granel', unit: 'kg', price: 16.0, cost: 10.0, stock: 25, minStock: 5),
  ]);
  await family('Jitomate', 'Frutas y Verduras', [
    (presentation: 'Granel', unit: 'kg', price: 22.0, cost: 15.0, stock: 20, minStock: 5),
  ]);
}
