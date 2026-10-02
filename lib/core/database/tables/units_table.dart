import 'package:drift/drift.dart';

import '../id_generator.dart';

/// Tabla `units`: las unidades de medida con las que se cuenta y vende un
/// producto (pieza, kg, libra, litro, paquete...). Cada tienda puede crear
/// las suyas desde la sección "Unidades".
class UnitsTable extends Table {
  @override
  String get tableName => 'units';

  TextColumn get id => text().clientDefault(() => generateId('u'))();

  /// Nombre completo, ej. "Kilogramo".
  TextColumn get name => text()();

  /// Forma corta que se muestra junto a las cantidades, ej. "kg". Si es
  /// nula se muestra el nombre completo.
  TextColumn get abbreviation => text().nullable()();

  /// Si la unidad admite cantidades fraccionarias (1.5 kg, 0.25 lb). Las
  /// unidades "por pieza" no: no se puede tener 2.5 gaseosas.
  BoolColumn get allowsDecimals => boolean().withDefault(const Constant(false))();

  BoolColumn get active => boolean().withDefault(const Constant(true))();
  DateTimeColumn get createdAt =>
      dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}
