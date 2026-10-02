import 'package:drift/drift.dart';

import '../id_generator.dart';
import 'categories_table.dart';
import 'units_table.dart';

/// Tabla `products`: un producto vendible, plana y desnormalizada. El
/// nombre ya incluye la presentación ("Coca-Cola Lata 355ml"); no hay
/// familias ni variantes.
///
/// `tags` guarda las palabras del nombre (más etiquetas extra) en minúsculas
/// y sin acentos, separadas por espacios — se usa para sugerir nombres de
/// productos ya ingresados mientras el usuario escribe.
class ProductsTable extends Table {
  @override
  String get tableName => 'products';

  TextColumn get id => text().clientDefault(() => generateId('p'))();
  TextColumn get name => text()();
  TextColumn get categoryId => text().references(CategoriesTable, #id)();
  TextColumn get unitId => text().references(UnitsTable, #id)();
  RealColumn get price => real()();
  RealColumn get cost => real()();
  RealColumn get stock => real().withDefault(const Constant(0))();
  RealColumn get minStock => real().withDefault(const Constant(5))();
  TextColumn get barcode => text().nullable()();
  TextColumn get tags => text().withDefault(const Constant(''))();
  BoolColumn get active => boolean().withDefault(const Constant(true))();
  DateTimeColumn get createdAt =>
      dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}
