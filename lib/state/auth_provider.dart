import 'package:flutter/foundation.dart';

import '../features/auth/data/user_repository.dart';
import '../models/app_user.dart';

/// El usuario se pasó de intentos: debe esperar [remaining] antes de reintentar.
class LockedOutException implements Exception {
  LockedOutException(this.remaining);

  final Duration remaining;

  @override
  String toString() => 'Demasiados intentos. Espera ${remaining.inSeconds + 1} s';
}

/// Sesión y usuarios. Decide quién está dentro y qué puede hacer.
class AuthProvider extends ChangeNotifier {
  AuthProvider(
    this._repository, {
    DateTime Function()? clock,
    this.maxAttempts = 5,
    this.lockDuration = const Duration(seconds: 30),
  }) : _clock = clock ?? DateTime.now;

  final UserRepository _repository;
  final DateTime Function() _clock;

  /// Intentos fallidos seguidos antes del bloqueo temporal.
  final int maxAttempts;
  final Duration lockDuration;

  List<AppUser> _users = const [];
  AppUser? _current;
  bool _loaded = false;

  // Bloqueo por intentos fallidos: por clave (id de usuario, o 'admin-override').
  final Map<String, int> _failures = {};
  final Map<String, DateTime> _lockedUntil = {};

  bool get loaded => _loaded;
  List<AppUser> get users => _users;
  List<AppUser> get activeUsers => _users.where((u) => u.active).toList();

  /// Sin ningún usuario: es el primer arranque y hay que crear al admin.
  bool get needsSetup => _loaded && _users.isEmpty;

  AppUser? get currentUser => _current;
  bool get isLoggedIn => _current != null;
  bool get isAdmin => _current?.isAdmin ?? false;

  Future<void> load() async {
    _users = await _repository.all();
    _loaded = true;
    // Si el usuario en sesión se desactivó o cambió de rol, se refleja.
    if (_current != null) {
      final fresh = _users.where((u) => u.id == _current!.id && u.active);
      _current = fresh.isEmpty ? null : fresh.first;
    }
    notifyListeners();
  }

  /// Primer arranque: crea al administrador y entra con él.
  Future<void> createFirstAdmin({required String name, required String pin}) async {
    if (!needsSetup) throw StateError('Ya existe un usuario');
    final admin = await _repository.create(name: name, role: UserRole.admin, pin: pin);
    await load();
    _current = admin;
    notifyListeners();
  }

  Duration? _remainingLock(String key) {
    final until = _lockedUntil[key];
    if (until == null) return null;
    final left = until.difference(_clock());
    if (left <= Duration.zero) {
      _lockedUntil.remove(key);
      _failures.remove(key);
      return null;
    }
    return left;
  }

  /// Tiempo restante de bloqueo del usuario [userId], si lo hay.
  Duration? lockRemaining(String userId) => _remainingLock(userId);

  void _registerFailure(String key) {
    final count = (_failures[key] ?? 0) + 1;
    _failures[key] = count;
    if (count >= maxAttempts) _lockedUntil[key] = _clock().add(lockDuration);
  }

  /// Entra con el PIN. Lanza [InvalidCredentialsException] o [LockedOutException].
  Future<void> login(String userId, String pin) async {
    final locked = _remainingLock(userId);
    if (locked != null) throw LockedOutException(locked);
    try {
      _current = await _repository.authenticate(userId, pin);
    } on InvalidCredentialsException {
      _registerFailure(userId);
      final nowLocked = _remainingLock(userId);
      if (nowLocked != null) throw LockedOutException(nowLocked);
      rethrow;
    }
    _failures.remove(userId);
    notifyListeners();
  }

  void logout() {
    if (_current == null) return;
    _current = null;
    notifyListeners();
  }

  static const _overrideKey = 'admin-override';

  /// Autorización de un administrador para una acción de un cajero (anular una
  /// venta): devuelve el admin cuyo PIN coincide, o lanza
  /// [InvalidCredentialsException] / [LockedOutException].
  Future<AppUser> authorizeWithAdminPin(String pin) async {
    final locked = _remainingLock(_overrideKey);
    if (locked != null) throw LockedOutException(locked);
    final admin = await _repository.authenticateAnyAdmin(pin);
    if (admin == null) {
      _registerFailure(_overrideKey);
      final nowLocked = _remainingLock(_overrideKey);
      if (nowLocked != null) throw LockedOutException(nowLocked);
      throw InvalidCredentialsException();
    }
    _failures.remove(_overrideKey);
    return admin;
  }

  // ---- Administración de usuarios (solo el admin llega a estas pantallas) ----

  Future<AppUser> addUser({required String name, required UserRole role, required String pin}) async {
    final user = await _repository.create(name: name, role: role, pin: pin);
    await load();
    return user;
  }

  Future<void> updateUser(String id, {String? name, UserRole? role, bool? active}) async {
    await _repository.update(id, name: name, role: role, active: active);
    await load();
  }

  /// Elimina un usuario. No se puede eliminar al que tiene la sesión abierta.
  Future<void> deleteUser(String id) async {
    if (id == _current?.id) throw StateError('No puedes eliminar tu propio usuario');
    await _repository.delete(id);
    _failures.remove(id);
    _lockedUntil.remove(id);
    await load();
  }

  Future<void> resetPin(String id, String pin) async {
    await _repository.setPin(id, pin);
    _failures.remove(id);
    _lockedUntil.remove(id);
  }
}
