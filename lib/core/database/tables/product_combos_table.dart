import 'package:drift/drift.dart';

import '../id_generator.dart';
import 'products_table.dart';

/// Tabla `product_combos`: promociones por cantidad de un producto o
/// presentación, ej. "2 por $0.25" cuando una unidad cuesta $0.15. Al vender
/// N unidades, el POS usa las combinaciones que más le convengan al cliente
/// (ver `core/pricing.dart`). Un producto puede tener varias (2x, 5x...).
///
/// Al borrar el producto se borran sus combos (`onDelete: cascade`).
@TableIndex(name: 'idx_product_combos_product_id', columns: {#productId})
class ProductCombosTable extends Table {
  @override
  String get tableName => 'product_combos';

  TextColumn get id => text().clientDefault(() => generateId('o'))();
  TextColumn get productId =>
      text().references(ProductsTable, #id, onDelete: KeyAction.cascade)();

  /// Cuántas unidades lleva el combo (2 o más).
  // ignore: recursive_getters
  IntColumn get quantity => integer().check(quantity.isBiggerOrEqualValue(2))();

  /// Precio de TODO el combo, en centavos (no por unidad).
  // ignore: recursive_getters
  IntColumn get priceCents => integer().check(priceCents.isBiggerThanValue(0))();

  @override
  Set<Column> get primaryKey => {id};
}
