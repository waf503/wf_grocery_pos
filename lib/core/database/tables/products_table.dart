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
  // Precio de venta y costo en centavos enteros (ver `core/money.dart`).
  // ignore: recursive_getters
  IntColumn get priceCents => integer().check(priceCents.isBiggerOrEqualValue(0))();
  // ignore: recursive_getters
  IntColumn get costCents => integer().check(costCents.isBiggerOrEqualValue(0))();
  RealColumn get stock => real().withDefault(const Constant(0))();
  RealColumn get minStock => real().withDefault(const Constant(5))();
  TextColumn get barcode => text().nullable()();
  TextColumn get tags => text().withDefault(const Constant(''))();
  BoolColumn get active => boolean().withDefault(const Constant(true))();
  DateTimeColumn get createdAt =>
      dateTime().withDefault(currentDateAndTime)();

  /// Última vez que se editó el producto. Nulo = nunca se ha editado (se
  /// muestra la fecha de creación).
  DateTimeColumn get updatedAt => dateTime().nullable()();

  /// `true` si el producto tiene miniatura en `product_images`. Se guarda aquí
  /// para saber si hay que pedirla sin consultar esa tabla por cada producto.
  BoolColumn get hasImage => boolean().withDefault(const Constant(false))();

  /// Si es una PRESENTACIÓN (ej. "Cajetilla de 20") de otro producto, el id de
  /// ese producto base. Las presentaciones NO tienen existencias propias:
  /// descuentan del producto base, que las lleva en su unidad más pequeña.
  /// Nulo en un producto normal o en el producto base.
  TextColumn get baseProductId => text().nullable()();

  /// Cuántas unidades del producto base contiene esta presentación (ya
  /// multiplicado: un paquete de 20 cajetillas de 20 es 400). 1 en productos
  /// normales.
  RealColumn get unitsPerPack => real().withDefault(const Constant(1))();

  @override
  Set<Column> get primaryKey => {id};
}
