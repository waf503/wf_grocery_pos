import 'package:drift/drift.dart';

import '../id_generator.dart';

/// Tabla `customers`. El saldo NO se guarda aquí: se calcula sumando los
/// movimientos de `customer_account_movements`, así nunca puede quedar
/// desfasado respecto al historial.
class CustomersTable extends Table {
  @override
  String get tableName => 'customers';

  TextColumn get id => text().clientDefault(() => generateId('c'))();
  TextColumn get name => text()();
  TextColumn get phone => text().nullable()();
  TextColumn get email => text().nullable()();
  DateTimeColumn get createdAt => dateTime().clientDefault(() => DateTime.now())();

  @override
  Set<Column> get primaryKey => {id};
}
