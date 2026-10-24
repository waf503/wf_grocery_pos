import 'package:drift/drift.dart';

/// Tabla `settings`: datos del negocio guardados clave por clave (hoy el
/// nombre; mañana dirección, teléfono, pie del ticket...) sin tener que
/// cambiar el esquema cada vez.
class SettingsTable extends Table {
  @override
  String get tableName => 'settings';

  TextColumn get key => text()();
  TextColumn get value => text()();

  @override
  Set<Column> get primaryKey => {key};
}
