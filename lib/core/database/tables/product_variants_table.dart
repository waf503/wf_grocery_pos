import 'package:drift/drift.dart';

import '../id_generator.dart';
import 'products_table.dart';

/// Tabla `product_variants`: la presentación vendible real (ej. "Lata
/// 355ml" de la familia "Coca-Cola"). Esta es la unidad que de verdad se
/// escanea en caja, tiene su propio precio/costo, y se cuenta en stock.
class ProductVariantsTable extends Table {
  @override
  String get tableName => 'product_variants';

  TextColumn get id => text().clientDefault(() => generateId('v'))();

  /// `.references(ProductsTable, #id)` declara la llave foránea — el
  /// equivalente a `$table->foreignId('product_id')->constrained()` de un
  /// migration de Laravel. El `#id` (con `#`) es un "Symbol" de Dart: le
  /// dice a Drift el NOMBRE del getter de columna al que apunta, sin tener
  /// que escribir el nombre real de columna SQL.
  TextColumn get productId => text().references(ProductsTable, #id)();

  TextColumn get presentation => text()();
  TextColumn get unit => text()();
  RealColumn get price => real()();
  RealColumn get cost => real()();
  RealColumn get stock => real().withDefault(const Constant(0))();
  RealColumn get minStock => real().withDefault(const Constant(5))();
  TextColumn get barcode => text().nullable()();
  BoolColumn get active => boolean().withDefault(const Constant(true))();
  DateTimeColumn get createdAt =>
      dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}
