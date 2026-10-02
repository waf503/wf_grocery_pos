import 'package:drift/drift.dart';

import '../id_generator.dart';

/// Tabla `cash_sessions`: un turno de caja. Está abierta mientras `closedAt`
/// sea nulo; el repositorio garantiza que nunca haya más de una abierta.
/// Los montos van en centavos enteros (ver `core/money.dart`).
class CashSessionsTable extends Table {
  @override
  String get tableName => 'cash_sessions';

  TextColumn get id => text().clientDefault(() => generateId('s'))();
  DateTimeColumn get openedAt => dateTime()();
  DateTimeColumn get closedAt => dateTime().nullable()();
  // ignore: recursive_getters
  IntColumn get openingCents => integer().check(openingCents.isBiggerOrEqualValue(0))();
  IntColumn get closingCountedCents => integer().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}
