import 'package:drift/drift.dart';

import '../../../models/sale.dart';
import '../id_generator.dart';
import 'cash_sessions_table.dart';

/// Tabla `sales`: el encabezado de cada venta. El detalle está en
/// `sale_items`. El total va en centavos enteros.
///
/// `customerId` NO es llave foránea a propósito: los clientes aún no están
/// en la base de datos. El `customerName` es una foto del nombre al momento
/// de la venta.
@TableIndex(name: 'idx_sales_created_at', columns: {#createdAt})
class SalesTable extends Table {
  @override
  String get tableName => 'sales';

  TextColumn get id => text().clientDefault(() => generateId('v'))();

  /// Folio consecutivo que se imprime en el recibo (V-000123).
  IntColumn get number => integer().unique()();

  TextColumn get sessionId => text().references(CashSessionsTable, #id)();
  TextColumn get customerId => text().nullable()();
  TextColumn get customerName => text().nullable()();
  TextColumn get paymentMethod => textEnum<PaymentMethod>()();
  // ignore: recursive_getters
  IntColumn get totalCents => integer().check(totalCents.isBiggerOrEqualValue(0))();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}
