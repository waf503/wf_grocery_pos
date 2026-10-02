import 'package:drift/drift.dart';

import '../../../models/cash_session.dart';
import '../id_generator.dart';
import 'cash_sessions_table.dart';
import 'sales_table.dart';

/// Tabla `cash_movements`: cada entrada o salida de EFECTIVO de una sesión
/// de caja. Las ventas en efectivo generan un movimiento `sale` (enlazado
/// por `saleId`); los ingresos y retiros manuales no tienen venta. Las
/// ventas con tarjeta o fiado no tocan el efectivo y no generan movimiento.
@TableIndex(name: 'idx_cash_movements_session_id', columns: {#sessionId})
class CashMovementsTable extends Table {
  @override
  String get tableName => 'cash_movements';

  TextColumn get id => text().clientDefault(() => generateId('m'))();
  TextColumn get sessionId => text().references(CashSessionsTable, #id)();
  TextColumn get type => textEnum<CashMovementType>()();
  // ignore: recursive_getters
  IntColumn get amountCents => integer().check(amountCents.isBiggerThanValue(0))();
  TextColumn get note => text()();
  DateTimeColumn get createdAt => dateTime()();
  TextColumn get saleId => text().nullable().references(SalesTable, #id)();

  @override
  Set<Column> get primaryKey => {id};
}
