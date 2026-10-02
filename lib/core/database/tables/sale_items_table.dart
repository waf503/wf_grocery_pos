import 'package:drift/drift.dart';

import '../id_generator.dart';
import 'sales_table.dart';

/// Tabla `sale_items`: un renglón de una venta. Nombre, precio y costo son
/// una FOTO del momento de la venta, por eso `productId` NO es llave
/// foránea: si el producto se borra después del inventario, la venta
/// histórica queda intacta. El costo guardado permite calcular utilidad.
@TableIndex(name: 'idx_sale_items_sale_id', columns: {#saleId})
class SaleItemsTable extends Table {
  @override
  String get tableName => 'sale_items';

  TextColumn get id => text().clientDefault(() => generateId('i'))();
  TextColumn get saleId => text().references(SalesTable, #id)();
  TextColumn get productId => text().nullable()();
  TextColumn get productName => text()();
  // ignore: recursive_getters
  RealColumn get quantity => real().check(quantity.isBiggerThanValue(0))();
  IntColumn get unitPriceCents => integer()();
  IntColumn get unitCostCents => integer()();
  IntColumn get subtotalCents => integer()();

  @override
  Set<Column> get primaryKey => {id};
}
