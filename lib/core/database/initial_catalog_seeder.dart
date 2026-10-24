import 'package:drift/drift.dart';

import 'app_database.dart';

/// Catálogo con el que ARRANCA una instalación nueva: solo categorías y
/// unidades de medida. **No se siembra ningún producto**: el inventario de la
/// tienda empieza vacío y se llena escaneando o desde la pantalla Inventario.
///
/// Si las tablas ya tienen datos (una tienda que ya trabaja) no se toca nada:
/// cada función solo actúa cuando su tabla está vacía.
///
/// (Los seeders de `features/*/data/*_seeder.dart`, con catálogo de ejemplo,
/// quedan solo para las pruebas automáticas.)
Future<void> seedInitialCatalogIfEmpty(AppDatabase db) async {
  await seedInitialCategoriesIfEmpty(db);
  await seedInitialUnitsIfEmpty(db);
}

class _CategorySeed {
  const _CategorySeed(this.name, this.description, this.icon, this.color, {this.parent});

  final String name;
  final String description;
  final String icon;

  /// Color ARGB propio; nulo = hereda el de su categoría padre.
  final int? color;
  final String? parent;
}

/// Orden en que aparecen en el POS. Una subcategoría va después de su padre.
const _categories = [
  _CategorySeed(
    'Abarrotes',
    'Productos empacados de despensa: granos, enlatados, condimentos.',
    'local_grocery_store',
    0xFFFB8C00,
  ),
  _CategorySeed('Bebidas', 'Refrescos, aguas, jugos y bebidas en general.', 'local_drink', 0xFF1E88E5),
  _CategorySeed('Gaseosas', 'Refrescos carbonatados.', 'local_bar', null, parent: 'Bebidas'),
  _CategorySeed('Lácteos', 'Leche, quesos, yogures y derivados.', 'icecream', 0xFF00ACC1),
  _CategorySeed('Panadería', 'Pan, pasteles y productos de panadería.', 'bakery_dining', 0xFF6D4C41),
  _CategorySeed('A Granel', 'Productos vendidos por peso o cantidad suelta.', 'scale', 0xFF546E7A),
  _CategorySeed('Frutas y Verduras', 'Productos frescos de frutas y verduras.', 'eco', 0xFF43A047),
  _CategorySeed('Golosinas', 'Frituras, churros, galletas y snacks.', 'cookie', 0xFFE53935),
  _CategorySeed('Limpieza', 'Productos de limpieza e higiene del hogar.', 'cleaning_services', 0xFF00897B),
  _CategorySeed(
    'Higiene y Belleza',
    'Desodorantes, pasta de diente, cepillos, cremas, presto barba.',
    'soap',
    0xFF8E24AA,
  ),
  _CategorySeed('Farmacia', 'Pastillas, botiquín, primeros auxilios, etc.', 'medication', 0xFF37474F),
  _CategorySeed('Alcohol y Tabaco', 'Cervezas, cubatas, cigarros.', 'liquor', 0xFF6D4C41),
];

/// Crea las categorías si la tabla está vacía. Devuelve un mapa nombre → id.
Future<Map<String, String>> seedInitialCategoriesIfEmpty(AppDatabase db) async {
  final existing = await db.select(db.categoriesTable).get();
  if (existing.isNotEmpty) return {for (final row in existing) row.name: row.id};

  final ids = <String, String>{};
  for (final seed in _categories) {
    final row = await db.into(db.categoriesTable).insertReturning(
          CategoriesTableCompanion.insert(
            name: seed.name,
            description: Value(seed.description),
            icon: Value(seed.icon),
            color: Value(seed.color),
            parentId: Value(seed.parent == null ? null : ids[seed.parent]),
          ),
        );
    ids[seed.name] = row.id;
  }
  return ids;
}

class _UnitSeed {
  const _UnitSeed(this.name, this.abbreviation, {this.decimals = false});

  final String name;
  final String abbreviation;

  /// Si se vende por peso o medida (admite decimales, de media en media).
  final bool decimals;
}

const _units = [
  _UnitSeed('Unidad', 'U.'),
  _UnitSeed('Paquete', 'paq'),
  _UnitSeed('Libra', 'lb', decimals: true),
  _UnitSeed('Kilogramo', 'kg', decimals: true),
  _UnitSeed('Litro', 'L', decimals: true),
];

/// Crea las unidades de medida si la tabla está vacía. Devuelve nombre → id.
Future<Map<String, String>> seedInitialUnitsIfEmpty(AppDatabase db) async {
  final existing = await db.select(db.unitsTable).get();
  if (existing.isNotEmpty) return {for (final row in existing) row.name: row.id};

  final ids = <String, String>{};
  for (final seed in _units) {
    final row = await db.into(db.unitsTable).insertReturning(
          UnitsTableCompanion.insert(
            name: seed.name,
            abbreviation: Value(seed.abbreviation),
            allowsDecimals: Value(seed.decimals),
            // Lo que se vende por peso se vende de media en media (media libra...).
            saleStep: Value(seed.decimals ? 0.5 : 1),
          ),
        );
    ids[seed.name] = row.id;
  }
  return ids;
}
