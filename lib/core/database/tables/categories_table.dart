import 'package:drift/drift.dart';

import '../id_generator.dart';

/// Tabla `categories`, con capacidad de anidación: `parentId` apunta a OTRA
/// fila de esta MISMA tabla (autoreferencia). Así "Gaseosas" puede tener a
/// "Bebidas" como padre, y "Bebidas" puede no tener padre (categoría raíz).
class CategoriesTable extends Table {
  @override
  String get tableName => 'categories';

  TextColumn get id => text().clientDefault(() => generateId('c'))();
  TextColumn get name => text()();
  TextColumn get description => text().nullable()();

  /// El identificador del ícono elegido (ej. 'local_drink'), NO el
  /// `IconData` en sí — eso no es serializable. El mapeo id → ícono real
  /// vive en `category_icon_options.dart`.
  TextColumn get icon => text().nullable()();

  /// Color de la categoría como entero ARGB (ej. 0xFF43A047). Si es nulo, la
  /// categoría hereda el de su categoría padre.
  IntColumn get color => integer().nullable()();

  /// `.references(CategoriesTable, #id)` — la tabla se referencia A SÍ
  /// MISMA. Es lo mismo que en Laravel harías con
  /// `$table->foreignId('parent_id')->nullable()->constrained('categories')`.
  TextColumn get parentId =>
      text().nullable().references(CategoriesTable, #id)();

  BoolColumn get active => boolean().withDefault(const Constant(true))();
  DateTimeColumn get createdAt =>
      dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}
