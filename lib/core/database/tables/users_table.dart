import 'package:drift/drift.dart';

import '../../../models/app_user.dart';
import '../id_generator.dart';

/// Tabla `users`: quién puede entrar al sistema. El PIN NO se guarda: solo su
/// hash con sal (ver `core/security/pin_hasher.dart`). Se puede eliminar un
/// usuario: las ventas no lo referencian, guardan una foto de su nombre.
class UsersTable extends Table {
  @override
  String get tableName => 'users';

  TextColumn get id => text().clientDefault(() => generateId('u'))();
  TextColumn get name => text()();
  TextColumn get role => textEnum<UserRole>()();
  TextColumn get pinHash => text()();
  TextColumn get pinSalt => text()();
  BoolColumn get active => boolean().withDefault(const Constant(true))();
  DateTimeColumn get createdAt => dateTime().clientDefault(() => DateTime.now())();

  @override
  Set<Column> get primaryKey => {id};
}
