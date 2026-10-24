import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:wf_grocery_pos/core/database/app_database.dart';
import 'package:wf_grocery_pos/core/security/pin_hasher.dart';
import 'package:wf_grocery_pos/features/auth/data/drift_user_repository.dart';
import 'package:wf_grocery_pos/features/auth/users_screen.dart';
import 'package:wf_grocery_pos/features/auth/widgets/admin_pin_dialog.dart';
import 'package:wf_grocery_pos/models/app_user.dart';
import 'package:wf_grocery_pos/state/auth_provider.dart';

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 4; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 40)));
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<AuthProvider> _auth(WidgetTester tester) async {
  final db = AppDatabase.forTesting(NativeDatabase.memory());
  addTearDown(db.close);
  final auth = AuthProvider(DriftUserRepository(db, hasher: const PinHasher(iterations: 5)));
  addTearDown(auth.dispose);
  await tester.runAsync(() async {
    await auth.load();
    await auth.createFirstAdmin(name: 'Dueña', pin: '1234');
    await auth.addUser(name: 'Ana', role: UserRole.cashier, pin: '4321');
  });
  return auth;
}

Widget _host(AuthProvider auth, Widget home) => ChangeNotifierProvider<AuthProvider>.value(
      value: auth,
      child: MaterialApp(home: Scaffold(body: home)),
    );

void main() {
  group('PIN de administrador (autorizar anulaciones)', () {
    late AppUser? result;
    var closed = false;

    Future<void> open(WidgetTester tester, AuthProvider auth) async {
      result = null;
      closed = false;
      await tester.pumpWidget(_host(
        auth,
        Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              result = await showAdminPinDialog(context);
              closed = true;
            },
            child: const Text('abrir'),
          ),
        ),
      ));
      await tester.tap(find.text('abrir'));
      await tester.pumpAndSettle();
    }

    Future<void> submit(WidgetTester tester, String pin) async {
      await tester.enterText(find.byType(TextField), pin);
      await tester.tap(find.text('Autorizar'));
      await _settle(tester);
    }

    testWidgets('con el PIN de un admin se autoriza y devuelve quién fue', (tester) async {
      final auth = await _auth(tester);
      await open(tester, auth);
      await submit(tester, '1234');
      expect(closed, isTrue);
      expect(result?.name, 'Dueña');
    });

    testWidgets('el PIN de un cajero o uno equivocado NO autoriza', (tester) async {
      final auth = await _auth(tester);
      await open(tester, auth);

      await submit(tester, '4321'); // PIN del cajero Ana
      expect(find.text('PIN incorrecto'), findsOneWidget);
      expect(closed, isFalse);

      await submit(tester, '0000');
      expect(find.text('PIN incorrecto'), findsOneWidget);
      expect(closed, isFalse);
    });

    testWidgets('Cancelar no autoriza nada', (tester) async {
      final auth = await _auth(tester);
      await open(tester, auth);
      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();
      expect(closed, isTrue);
      expect(result, isNull);
    });
  });

  group('pantalla de usuarios', () {
    testWidgets('el admin crea un cajero y luego lo desactiva', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1000, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final auth = await _auth(tester);
      await tester.pumpWidget(_host(auth, const UsersScreen()));
      await tester.pump();

      expect(find.text('Dueña (tú)'), findsOneWidget);
      expect(find.text('Ana'), findsOneWidget);

      await tester.tap(find.text('Nuevo usuario'));
      await tester.pumpAndSettle();
      final fields = find.byType(TextField);
      await tester.enterText(fields.at(0), 'Luis');
      await tester.enterText(fields.at(1), '5555');
      await tester.enterText(fields.at(2), '5555');
      await tester.tap(find.text('Crear'));
      await _settle(tester);
      expect(find.text('Luis'), findsOneWidget);
      expect(auth.users.map((u) => u.name), contains('Luis'));

      // El propio admin no tiene botón para desactivarse.
      expect(find.byTooltip('Desactivar'), findsNWidgets(2)); // Ana y Luis
      await tester.tap(find.byTooltip('Desactivar').last);
      await _settle(tester);
      expect(auth.users.firstWhere((u) => u.name == 'Luis').active, isFalse);
      expect(find.byTooltip('Reactivar'), findsOneWidget);
      await tester.pump(const Duration(seconds: 4)); // la alerta se retira sola
    });

    testWidgets('el admin elimina a un cajero (con confirmación) y no puede eliminarse a sí mismo', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1000, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final auth = await _auth(tester);
      await tester.pumpWidget(_host(auth, const UsersScreen()));
      await tester.pump();

      // Solo Ana tiene botón de eliminar: la sesión es de Dueña.
      expect(find.byTooltip('Eliminar'), findsOneWidget);

      // Cancelar no elimina.
      await tester.tap(find.byTooltip('Eliminar'));
      await tester.pumpAndSettle();
      expect(find.text('¿Eliminar a Ana?'), findsOneWidget);
      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();
      expect(auth.users.map((u) => u.name), contains('Ana'));

      // Confirmar sí.
      await tester.tap(find.byTooltip('Eliminar'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Eliminar'));
      await _settle(tester);
      expect(auth.users.map((u) => u.name), ['Dueña']);
      expect(find.text('Ana'), findsNothing);
      await tester.pump(const Duration(seconds: 4)); // la alerta se retira sola
    });

    testWidgets('PIN corto o que no coincide no crea el usuario', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1000, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final auth = await _auth(tester);
      await tester.pumpWidget(_host(auth, const UsersScreen()));
      await tester.tap(find.text('Nuevo usuario'));
      await tester.pumpAndSettle();

      final fields = find.byType(TextField);
      await tester.enterText(fields.at(0), 'Luis');
      await tester.enterText(fields.at(1), '12');
      await tester.enterText(fields.at(2), '12');
      await tester.tap(find.text('Crear'));
      await tester.pump();
      expect(find.text('El PIN debe tener de 4 a 6 dígitos'), findsOneWidget);

      await tester.enterText(fields.at(1), '1234');
      await tester.enterText(fields.at(2), '4321');
      await tester.tap(find.text('Crear'));
      await tester.pump();
      expect(find.text('Los PIN no coinciden'), findsOneWidget);
      expect(auth.users.map((u) => u.name), isNot(contains('Luis')));
    });
  });
}
