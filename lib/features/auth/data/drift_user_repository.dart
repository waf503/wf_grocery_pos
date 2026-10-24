import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
import '../../../core/security/pin_hasher.dart';
import '../../../models/app_user.dart';
import 'user_repository.dart';

class DriftUserRepository implements UserRepository {
  DriftUserRepository(this._db, {this._hasher = const PinHasher()});

  final AppDatabase _db;
  final PinHasher _hasher;

  AppUser _toModel(UsersTableData row) =>
      AppUser(id: row.id, name: row.name, role: row.role, active: row.active);

  @override
  Future<List<AppUser>> all() async {
    final rows = await (_db.select(_db.usersTable)
          ..orderBy([(u) => OrderingTerm.asc(u.createdAt), (u) => OrderingTerm.asc(u.name)]))
        .get();
    return rows.map(_toModel).toList();
  }

  Future<void> _ensureNameFree(String name, {String? exceptId}) async {
    final rows = await _db.select(_db.usersTable).get();
    final taken = rows.any(
      (u) => u.id != exceptId && u.name.trim().toLowerCase() == name.trim().toLowerCase(),
    );
    if (taken) throw DuplicateUserNameException();
  }

  @override
  Future<AppUser> create({required String name, required UserRole role, required String pin}) {
    return _db.transaction(() async {
      await _ensureNameFree(name);
      final salt = _hasher.newSalt();
      final row = await _db.into(_db.usersTable).insertReturning(
            UsersTableCompanion.insert(
              name: name.trim(),
              role: role,
              pinHash: _hasher.hash(pin, salt),
              pinSalt: salt,
            ),
          );
      return _toModel(row);
    });
  }

  @override
  Future<AppUser> update(String id, {String? name, UserRole? role, bool? active}) {
    return _db.transaction(() async {
      final current = await (_db.select(_db.usersTable)..where((u) => u.id.equals(id))).getSingle();
      if (name != null) await _ensureNameFree(name, exceptId: id);

      final newRole = role ?? current.role;
      final newActive = active ?? current.active;
      final losesAdmin = current.role == UserRole.admin &&
          current.active &&
          (newRole != UserRole.admin || !newActive);
      if (losesAdmin) {
        final others = await (_db.select(_db.usersTable)
              ..where((u) =>
                  u.id.equals(id).not() & u.role.equals(UserRole.admin.name) & u.active.equals(true)))
            .get();
        if (others.isEmpty) throw LastAdminException();
      }

      await (_db.update(_db.usersTable)..where((u) => u.id.equals(id))).write(
        UsersTableCompanion(
          name: Value(name?.trim() ?? current.name),
          role: Value(newRole),
          active: Value(newActive),
        ),
      );
      final row = await (_db.select(_db.usersTable)..where((u) => u.id.equals(id))).getSingle();
      return _toModel(row);
    });
  }

  @override
  Future<void> delete(String id) {
    return _db.transaction(() async {
      final current = await (_db.select(_db.usersTable)..where((u) => u.id.equals(id))).getSingleOrNull();
      if (current == null) return;
      if (current.role == UserRole.admin && current.active) {
        final others = await (_db.select(_db.usersTable)
              ..where((u) =>
                  u.id.equals(id).not() & u.role.equals(UserRole.admin.name) & u.active.equals(true)))
            .get();
        if (others.isEmpty) throw LastAdminException();
      }
      await (_db.delete(_db.usersTable)..where((u) => u.id.equals(id))).go();
    });
  }

  @override
  Future<void> setPin(String id, String pin) async {
    final salt = _hasher.newSalt();
    await (_db.update(_db.usersTable)..where((u) => u.id.equals(id))).write(
      UsersTableCompanion(pinHash: Value(_hasher.hash(pin, salt)), pinSalt: Value(salt)),
    );
  }

  @override
  Future<AppUser> authenticate(String id, String pin) async {
    final row = await (_db.select(_db.usersTable)..where((u) => u.id.equals(id))).getSingleOrNull();
    if (row == null || !row.active || !_hasher.verify(pin, row.pinSalt, row.pinHash)) {
      throw InvalidCredentialsException();
    }
    return _toModel(row);
  }

  @override
  Future<AppUser?> authenticateAnyAdmin(String pin) async {
    final admins = await (_db.select(_db.usersTable)
          ..where((u) => u.role.equals(UserRole.admin.name) & u.active.equals(true)))
        .get();
    for (final row in admins) {
      if (_hasher.verify(pin, row.pinSalt, row.pinHash)) return _toModel(row);
    }
    return null;
  }
}
