import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';

/// Si la tabla `categories` está vacía, la llena con categorías genéricas
/// de una tienda de abarrotes — incluyendo una subcategoría ("Gaseosas"
/// dentro de "Bebidas") para demostrar la anidación desde el primer momento.
/// Devuelve un mapa nombre → id, para que `seedProductsIfEmpty` pueda
/// referenciar el id real de cada categoría al crear los productos.
Future<Map<String, String>> seedCategoriesIfEmpty(AppDatabase db) async {
  final existing = await db.select(db.categoriesTable).get();
  if (existing.isNotEmpty) {
    return {for (final row in existing) row.name: row.id};
  }

  final ids = <String, String>{};

  Future<void> root(String name, String description, String icon, int color) async {
    final row = await db.into(db.categoriesTable).insertReturning(
          CategoriesTableCompanion.insert(
            name: name,
            description: Value(description),
            icon: Value(icon),
            color: Value(color),
          ),
        );
    ids[name] = row.id;
  }

  await root('Abarrotes', 'Productos empacados de despensa: granos, enlatados, condimentos.', 'local_grocery_store', 0xFFFB8C00);
  await root('Bebidas', 'Refrescos, aguas, jugos y bebidas en general.', 'local_drink', 0xFF1E88E5);
  await root('Lácteos', 'Leche, quesos, yogures y derivados.', 'icecream', 0xFF00ACC1);
  await root('Panadería', 'Pan, pasteles y productos de panadería.', 'bakery_dining', 0xFF6D4C41);
  await root('A Granel', 'Productos vendidos por peso o cantidad suelta.', 'scale', 0xFF546E7A);
  await root('Frutas y Verduras', 'Productos frescos de frutas y verduras.', 'eco', 0xFF43A047);
  await root('Limpieza', 'Productos de limpieza e higiene del hogar.', 'cleaning_services', 0xFF00897B);
  await root('Botanas', 'Frituras, galletas y snacks.', 'local_pizza', 0xFFE53935);

  final gaseosas = await db.into(db.categoriesTable).insertReturning(
        CategoriesTableCompanion.insert(
          name: 'Gaseosas',
          description: const Value('Refrescos carbonatados.'),
          parentId: Value(ids['Bebidas']),
          icon: const Value('local_bar'),
        ),
      );
  ids['Gaseosas'] = gaseosas.id;

  return ids;
}
