import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:wf_grocery_pos/core/database/app_database.dart';
import 'package:wf_grocery_pos/core/security/permissions.dart';
import 'package:wf_grocery_pos/core/security/pin_hasher.dart';
import 'package:wf_grocery_pos/features/auth/data/drift_user_repository.dart';
import 'package:wf_grocery_pos/features/auth/data/user_repository.dart';
import 'package:wf_grocery_pos/models/app_user.dart';
import 'package:wf_grocery_pos/state/auth_provider.dart';

void main() {
  // Pocas iteraciones: la seguridad del hash no es lo que se prueba aquí.
  const fastHasher = PinHasher(iterations: 5);

  group('PinHasher', () {
    test('el mismo PIN con la misma sal da el mismo hash; otra sal, otro hash', () {
      const hasher = PinHasher(iterations: 50);
      final salt = hasher.newSalt();
      expect(hasher.hash('1234', salt), hasher.hash('1234', salt));
      expect(hasher.hash('1234', salt), isNot(hasher.hash('1234', hasher.newSalt())));
      expect(hasher.hash('1234', salt), isNot(hasher.hash('1235', salt)));
    });

    test('verify acepta el PIN correcto y rechaza los demás', () {
      const hasher = PinHasher(iterations: 50);
      final salt = hasher.newSalt();
      final stored = hasher.hash('4321', salt);
      expect(hasher.verify('4321', salt, stored), isTrue);
      expect(hasher.verify('4322', salt, stored), isFalse);
      expect(hasher.verify('', salt, stored), isFalse);
    });

    test('coincide con el vector de prueba de PBKDF2-HMAC-SHA256 (RFC 7914)', () {
      // password="passwd", salt="salt", c=1, dkLen=32 (primer bloque).
      const hasher = PinHasher(iterations: 1);
      final salt = 'c2FsdA=='; // "salt"
      expect(
        hasher.hash('passwd', salt),
        // 55ac046e56e3089fec1691c22544b605f94185216dde0465e68b9d57c20dacbc
        'VawEblbjCJ_sFpHCJUS2BflBhSFt3gRl5oudV8INrLw=',
      );
    });
  });

  group('UserRepository', () {
    late AppDatabase db;
    late DriftUserRepository repo;

    setUp(() {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      repo = DriftUserRepository(db, hasher: fastHasher);
    });
    tearDown(() => db.close());

    test('crea usuarios y autentica solo con el PIN correcto', () async {
      final ana = await repo.create(name: ' Ana ', role: UserRole.cashier, pin: '1234');
      expect(ana.name, 'Ana');
      expect((await repo.authenticate(ana.id, '1234')).id, ana.id);
      await expectLater(repo.authenticate(ana.id, '9999'), throwsA(isA<InvalidCredentialsException>()));
      await expectLater(repo.authenticate('no-existe', '1234'), throwsA(isA<InvalidCredentialsException>()));
    });

    test('el PIN no se guarda en claro', () async {
      await repo.create(name: 'Ana', role: UserRole.admin, pin: '123456');
      final row = await db.select(db.usersTable).getSingle();
      expect(row.pinHash, isNot(contains('123456')));
      expect(row.pinSalt, isNotEmpty);
      expect(row.pinHash, isNot('123456'));
    });

    test('no admite dos usuarios con el mismo nombre (sin importar mayúsculas)', () async {
      await repo.create(name: 'Ana', role: UserRole.cashier, pin: '1234');
      await expectLater(
        repo.create(name: 'ANA', role: UserRole.cashier, pin: '4321'),
        throwsA(isA<DuplicateUserNameException>()),
      );
    });

    test('un usuario desactivado no puede entrar', () async {
      await repo.create(name: 'Jefe', role: UserRole.admin, pin: '1111');
      final ana = await repo.create(name: 'Ana', role: UserRole.cashier, pin: '1234');
      await repo.update(ana.id, active: false);
      await expectLater(repo.authenticate(ana.id, '1234'), throwsA(isA<InvalidCredentialsException>()));
    });

    test('siempre debe quedar un administrador activo', () async {
      final jefe = await repo.create(name: 'Jefe', role: UserRole.admin, pin: '1111');
      await expectLater(repo.update(jefe.id, active: false), throwsA(isA<LastAdminException>()));
      await expectLater(repo.update(jefe.id, role: UserRole.cashier), throwsA(isA<LastAdminException>()));

      // Con un segundo administrador ya se puede.
      final otro = await repo.create(name: 'Otro', role: UserRole.admin, pin: '2222');
      await repo.update(jefe.id, role: UserRole.cashier);
      expect((await repo.all()).firstWhere((u) => u.id == jefe.id).role, UserRole.cashier);
      await expectLater(repo.update(otro.id, active: false), throwsA(isA<LastAdminException>()));
    });

    test('eliminar un usuario lo quita y ya no puede entrar; el último admin no se elimina', () async {
      final jefe = await repo.create(name: 'Jefe', role: UserRole.admin, pin: '1111');
      final ana = await repo.create(name: 'Ana', role: UserRole.cashier, pin: '1234');

      await repo.delete(ana.id);
      expect((await repo.all()).map((u) => u.name), ['Jefe']);
      await expectLater(repo.authenticate(ana.id, '1234'), throwsA(isA<InvalidCredentialsException>()));

      await expectLater(repo.delete(jefe.id), throwsA(isA<LastAdminException>()));
      expect(await repo.all(), hasLength(1));

      // Con otro admin activo ya se puede; y el nombre liberado se puede reutilizar.
      await repo.create(name: 'Otro', role: UserRole.admin, pin: '2222');
      await repo.delete(jefe.id);
      await repo.create(name: 'Ana', role: UserRole.cashier, pin: '9999');
      expect((await repo.all()).map((u) => u.name), unorderedEquals(['Otro', 'Ana']));
    });

    test('cambiar el PIN invalida el anterior', () async {
      final ana = await repo.create(name: 'Ana', role: UserRole.cashier, pin: '1234');
      await repo.setPin(ana.id, '5678');
      await expectLater(repo.authenticate(ana.id, '1234'), throwsA(isA<InvalidCredentialsException>()));
      expect((await repo.authenticate(ana.id, '5678')).id, ana.id);
    });

    test('authenticateAnyAdmin solo reconoce PIN de administradores activos', () async {
      await repo.create(name: 'Jefe', role: UserRole.admin, pin: '1111');
      await repo.create(name: 'Ana', role: UserRole.cashier, pin: '2222');
      expect((await repo.authenticateAnyAdmin('1111'))?.name, 'Jefe');
      expect(await repo.authenticateAnyAdmin('2222'), isNull); // PIN de cajero
      expect(await repo.authenticateAnyAdmin('0000'), isNull);
    });
  });

  group('AuthProvider', () {
    late AppDatabase db;
    late DateTime now;
    late AuthProvider auth;

    setUp(() async {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      now = DateTime(2026, 1, 1, 9);
      auth = AuthProvider(DriftUserRepository(db, hasher: fastHasher), clock: () => now);
      await auth.load();
    });
    tearDown(() async {
      auth.dispose();
      await db.close();
    });

    test('sin usuarios pide la configuración inicial y el primer admin entra solo', () async {
      expect(auth.needsSetup, isTrue);
      expect(auth.isLoggedIn, isFalse);

      await auth.createFirstAdmin(name: 'Dueña', pin: '1234');

      expect(auth.needsSetup, isFalse);
      expect(auth.isLoggedIn, isTrue);
      expect(auth.isAdmin, isTrue);
      expect(auth.currentUser!.name, 'Dueña');
      // Ya no se puede volver a crear un "primer admin".
      await expectLater(auth.createFirstAdmin(name: 'Intruso', pin: '0000'), throwsStateError);
    });

    test('login, logout y PIN incorrecto', () async {
      await auth.createFirstAdmin(name: 'Dueña', pin: '1234');
      final ana = await auth.addUser(name: 'Ana', role: UserRole.cashier, pin: '4321');
      auth.logout();
      expect(auth.isLoggedIn, isFalse);

      await expectLater(auth.login(ana.id, '0000'), throwsA(isA<InvalidCredentialsException>()));
      expect(auth.isLoggedIn, isFalse);

      await auth.login(ana.id, '4321');
      expect(auth.currentUser!.name, 'Ana');
      expect(auth.isAdmin, isFalse);
    });

    test('tras 5 intentos fallidos se bloquea 30 s, aun con el PIN correcto', () async {
      await auth.createFirstAdmin(name: 'Dueña', pin: '1234');
      final ana = await auth.addUser(name: 'Ana', role: UserRole.cashier, pin: '4321');
      auth.logout();

      for (var i = 0; i < 4; i++) {
        await expectLater(auth.login(ana.id, '0000'), throwsA(isA<InvalidCredentialsException>()));
      }
      await expectLater(auth.login(ana.id, '0000'), throwsA(isA<LockedOutException>()));
      await expectLater(auth.login(ana.id, '4321'), throwsA(isA<LockedOutException>()));
      expect(auth.lockRemaining(ana.id), isNotNull);

      now = now.add(const Duration(seconds: 31));
      await auth.login(ana.id, '4321');
      expect(auth.isLoggedIn, isTrue);
    });

    test('el bloqueo de un usuario no afecta a otro', () async {
      await auth.createFirstAdmin(name: 'Dueña', pin: '1234');
      final ana = await auth.addUser(name: 'Ana', role: UserRole.cashier, pin: '4321');
      final luis = await auth.addUser(name: 'Luis', role: UserRole.cashier, pin: '5555');
      auth.logout();
      for (var i = 0; i < 5; i++) {
        await auth.login(ana.id, '0000').catchError((_) {});
      }
      await auth.login(luis.id, '5555');
      expect(auth.currentUser!.name, 'Luis');
    });

    test('autorizar con PIN de admin: acepta admins, rechaza cajeros y se bloquea', () async {
      await auth.createFirstAdmin(name: 'Dueña', pin: '1234');
      await auth.addUser(name: 'Ana', role: UserRole.cashier, pin: '4321');

      expect((await auth.authorizeWithAdminPin('1234')).name, 'Dueña');
      await expectLater(auth.authorizeWithAdminPin('4321'), throwsA(isA<InvalidCredentialsException>()));
      // El PIN de cajero ya contó como 1 intento fallido; con 4 más son 5.
      for (var i = 0; i < 4; i++) {
        try {
          await auth.authorizeWithAdminPin('0000');
        } catch (_) {}
      }
      await expectLater(auth.authorizeWithAdminPin('1234'), throwsA(isA<LockedOutException>()));
    });

    test('si el usuario en sesión se desactiva, se cierra su sesión', () async {
      await auth.createFirstAdmin(name: 'Dueña', pin: '1234');
      final ana = await auth.addUser(name: 'Ana', role: UserRole.cashier, pin: '4321');
      auth.logout();
      await auth.login(ana.id, '4321');

      await DriftUserRepository(db, hasher: fastHasher).update(ana.id, active: false);
      await auth.load();
      expect(auth.isLoggedIn, isFalse);
    });

    test('no se puede eliminar al usuario con la sesión abierta; a otro sí', () async {
      await auth.createFirstAdmin(name: 'Dueña', pin: '1234');
      final ana = await auth.addUser(name: 'Ana', role: UserRole.cashier, pin: '4321');

      await expectLater(auth.deleteUser(auth.currentUser!.id), throwsStateError);
      await auth.deleteUser(ana.id);
      expect(auth.users.map((u) => u.name), ['Dueña']);
    });

    test('restablecer el PIN levanta el bloqueo', () async {
      await auth.createFirstAdmin(name: 'Dueña', pin: '1234');
      final ana = await auth.addUser(name: 'Ana', role: UserRole.cashier, pin: '4321');
      auth.logout();
      for (var i = 0; i < 5; i++) {
        await auth.login(ana.id, '0000').catchError((_) {});
      }
      expect(auth.lockRemaining(ana.id), isNotNull);

      await auth.resetPin(ana.id, '7777');
      expect(auth.lockRemaining(ana.id), isNull);
      await auth.login(ana.id, '7777');
      expect(auth.isLoggedIn, isTrue);
    });
  });

  group('permisos', () {
    const admin = AppUser(id: 'a', name: 'A', role: UserRole.admin);
    const cashier = AppUser(id: 'c', name: 'C', role: UserRole.cashier);

    test('el admin entra a todo', () {
      for (final path in [...adminOnlyPaths, '/pos', '/sales', '/customers', '/cash']) {
        expect(canAccess(admin, path), isTrue, reason: path);
      }
    });

    test('el cajero solo cobra, ve ventas, clientes y caja', () {
      for (final path in ['/pos', '/sales', '/customers', '/cash']) {
        expect(canAccess(cashier, path), isTrue, reason: path);
      }
      for (final path in ['/dashboard', '/inventory', '/categories', '/units', '/reports', '/users']) {
        expect(canAccess(cashier, path), isFalse, reason: path);
      }
    });

    test('PIN válido: de 4 a 6 dígitos', () {
      expect(isValidPin('1234'), isTrue);
      expect(isValidPin('123456'), isTrue);
      expect(isValidPin('123'), isFalse);
      expect(isValidPin('1234567'), isFalse);
      expect(isValidPin('12a4'), isFalse);
      expect(isValidPin(''), isFalse);
    });
  });
}
