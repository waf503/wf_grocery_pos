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

  Future<void> root(String name, String description, String icon) async {
    final row = await db.into(db.categoriesTable).insertReturning(
          CategoriesTableCompanion.insert(
            name: name,
            description: Value(description),
            icon: Value(icon),
          ),
        );
    ids[name] = row.id;
  }

  await root('Abarrotes', 'Productos empacados de despensa: granos, enlatados, condimentos.', 'local_grocery_store');
  await root('Bebidas', 'Refrescos, aguas, jugos y bebidas en general.', 'local_drink');
  await root('Lácteos', 'Leche, quesos, yogures y derivados.', 'icecream');
  await root('Panadería', 'Pan, pasteles y productos de panadería.', 'bakery_dining');
  await root('A Granel', 'Productos vendidos por peso o cantidad suelta.', 'scale');
  await root('Frutas y Verduras', 'Productos frescos de frutas y verduras.', 'eco');
  await root('Limpieza', 'Productos de limpieza e higiene del hogar.', 'cleaning_services');
  await root('Botanas', 'Frituras, galletas y snacks.', 'local_pizza');

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
