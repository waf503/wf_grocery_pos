import '../../../models/app_user.dart';

/// El PIN que se escribió no es correcto, o el usuario no existe / está inactivo.
class InvalidCredentialsException implements Exception {
  @override
  String toString() => 'PIN incorrecto';
}

/// Cambio que dejaría al sistema sin ningún administrador activo.
class LastAdminException implements Exception {
  @override
  String toString() => 'Debe quedar al menos un administrador activo';
}

class DuplicateUserNameException implements Exception {
  @override
  String toString() => 'Ya existe un usuario con ese nombre';
}

abstract class UserRepository {
  Future<List<AppUser>> all();

  Future<AppUser> create({required String name, required UserRole role, required String pin});

  /// Cambia nombre, rol y/o estado. Lanza [LastAdminException] si dejaría al
  /// sistema sin administradores activos.
  Future<AppUser> update(String id, {String? name, UserRole? role, bool? active});

  /// Elimina al usuario. Las ventas que cobró conservan su nombre. Lanza
  /// [LastAdminException] si era el único administrador activo.
  Future<void> delete(String id);

  Future<void> setPin(String id, String pin);

  /// Devuelve el usuario si el PIN es correcto y está activo; si no, lanza
  /// [InvalidCredentialsException].
  Future<AppUser> authenticate(String id, String pin);

  /// Devuelve el administrador activo cuyo PIN coincide, o null.
  Future<AppUser?> authenticateAnyAdmin(String pin);
}
