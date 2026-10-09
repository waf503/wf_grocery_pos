import 'package:drift/drift.dart';

import '../../../models/customer.dart';
import '../id_generator.dart';
import 'customers_table.dart';

/// Tabla `customer_account_movements`: el estado de cuenta del fiado. Cada
/// renglón es un cargo (venta a crédito), un abono o la reversa de un cargo
/// (venta anulada). `amountCents` siempre es positivo; el tipo decide si
/// suma o resta al saldo. `saleId` NO es llave foránea, igual que en
/// `sale_items`: el historial no debe depender de otras tablas.
@TableIndex(name: 'idx_customer_movements_customer_id', columns: {#customerId})
class CustomerMovementsTable extends Table {
  @override
  String get tableName => 'customer_account_movements';

  TextColumn get id => text().clientDefault(() => generateId('k'))();
  TextColumn get customerId => text().references(CustomersTable, #id)();
  TextColumn get type => textEnum<CustomerMovementType>()();
  // ignore: recursive_getters
  IntColumn get amountCents => integer().check(amountCents.isBiggerThanValue(0))();
  TextColumn get saleId => text().nullable()();
  TextColumn get note => text()();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}
