import 'package:drift/drift.dart';

import '../id_generator.dart';
import 'categories_table.dart';

/// Tabla `products`: el CONCEPTO general de un producto (ej. "Coca-Cola"),
/// sin presentación. Cada presentación vendible (lata, 600ml, 2L...) vive
/// en [ProductVariantsTable], que es la que de verdad tiene precio y stock.
class ProductsTable extends Table {
  @override
  String get tableName => 'products';

  TextColumn get id => text().clientDefault(() => generateId('f'))();
  TextColumn get name => text()();
  TextColumn get categoryId => text().references(CategoriesTable, #id)();
  TextColumn get brand => text().nullable()();
  BoolColumn get active => boolean().withDefault(const Constant(true))();
  DateTimeColumn get createdAt =>
      dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}
