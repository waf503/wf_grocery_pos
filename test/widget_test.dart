import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:wf_grocery_pos/app.dart';
import 'package:wf_grocery_pos/core/database/app_database.dart';
import 'package:wf_grocery_pos/core/security/pin_hasher.dart';
import 'package:wf_grocery_pos/features/auth/data/drift_user_repository.dart';
import 'package:wf_grocery_pos/models/app_user.dart';

/// Las pruebas usan una fuente muy ancha: los desbordes de diseño que produce
/// no son fallos de lo que se prueba aquí.
void _ignoreOverflow() {
  final original = FlutterError.onError;
  FlutterError.onError = (details) {
    if (details.exceptionAsString().contains('overflowed')) return;
    original?.call(details);
  };
  addTearDown(() => FlutterError.onError = original);
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 60)));
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// Cierra el árbol de widgets (cancela el temporizador de inactividad y suelta
/// la base) antes de que termine la prueba.
Future<void> _teardown(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
  await tester.pump(const Duration(seconds: 1));
}

Future<AppDatabase> _mount(WidgetTester tester, {List<(String, UserRole, String)> users = const []}) async {
  _ignoreOverflow();
  await tester.binding.setSurfaceSize(const Size(1400, 900));
  addTearDown(() => tester.binding.setSurfaceSize(null));

  final database = AppDatabase.forTesting(NativeDatabase.memory());
  await tester.runAsync(() async {
    final repo = DriftUserRepository(database, hasher: const PinHasher(iterations: 5));
    for (final (name, role, pin) in users) {
      await repo.create(name: name, role: role, pin: pin);
    }
  });
  await tester.pumpWidget(GroceryPosApp(database: database, pinHasher: const PinHasher(iterations: 5)));
  await _settle(tester);
  return database;
}

Future<void> _enterPin(WidgetTester tester, String pin) async {
  await tester.enterText(find.byType(TextField).first, pin);
  await tester.pump();
  await tester.tap(find.text('Entrar'));
  await _settle(tester);
}

void main() {
  testWidgets('primer arranque: pide crear al administrador y entra al inicio', (tester) async {
    final database = await _mount(tester);
    addTearDown(database.close);

    expect(find.text('Configuración inicial'), findsOneWidget);
    expect(find.text('Punto de Venta'), findsNothing); // sin sesión no hay menú

    final fields = find.byType(TextField);
    await tester.enterText(fields.at(0), 'Abarrotes Doña Rosa');
    await tester.enterText(fields.at(1), 'Dueña');
    await tester.enterText(fields.at(2), '1234');
    await tester.enterText(fields.at(3), '1234');
    await tester.tap(find.text('Crear y entrar'));
    await _settle(tester);

    // El admin entra al inicio y ve todo el menú, incluidos usuarios y negocio.
    expect(find.text('Punto de Venta'), findsWidgets);
    expect(find.text('Inventario'), findsWidgets);
    expect(find.text('Usuarios'), findsWidgets);
    expect(find.text('Negocio'), findsWidgets);
    // El menú lleva el nombre que se escribió, no el de fábrica.
    expect(find.text('Abarrotes Doña Rosa'), findsWidgets);
    expect(find.text('Mi Tienda'), findsNothing);
    await _teardown(tester);
  });

  testWidgets('la configuración inicial rechaza PIN distintos', (tester) async {
    final database = await _mount(tester);
    addTearDown(database.close);

    final fields = find.byType(TextField);
    await tester.enterText(fields.at(0), 'Mi Negocio');
    await tester.enterText(fields.at(1), 'Dueña');
    await tester.enterText(fields.at(2), '1234');
    await tester.enterText(fields.at(3), '4321');
    await tester.tap(find.text('Crear y entrar'));
    await _settle(tester);

    expect(find.text('Los PIN no coinciden'), findsOneWidget);
    expect(find.text('Configuración inicial'), findsOneWidget);
    await _teardown(tester);
  });

  testWidgets('la configuración inicial exige el nombre del negocio', (tester) async {
    final database = await _mount(tester);
    addTearDown(database.close);

    final fields = find.byType(TextField);
    await tester.enterText(fields.at(1), 'Dueña');
    await tester.enterText(fields.at(2), '1234');
    await tester.enterText(fields.at(3), '1234');
    await tester.tap(find.text('Crear y entrar'));
    await _settle(tester);

    expect(find.text('Escribe el nombre de tu negocio'), findsOneWidget);
    expect(find.text('Configuración inicial'), findsOneWidget);
    await _teardown(tester);
  });

  testWidgets('con usuarios, pide el PIN; uno incorrecto no entra', (tester) async {
    final database = await _mount(tester, users: [('Dueña', UserRole.admin, '1234')]);
    addTearDown(database.close);

    expect(find.text('Escribe tu PIN'), findsOneWidget); // un solo usuario: ya está elegido
    await _enterPin(tester, '0000');
    expect(find.text('PIN incorrecto'), findsOneWidget);
    expect(find.text('Punto de Venta'), findsNothing);

    await _enterPin(tester, '1234');
    expect(find.text('Punto de Venta'), findsWidgets);
    await _teardown(tester);
  });

  testWidgets('el cajero solo ve cobrar, ventas, clientes y caja y empieza en el punto de venta', (tester) async {
    final database = await _mount(tester, users: [
      ('Dueña', UserRole.admin, '1234'),
      ('Ana', UserRole.cashier, '4321'),
    ]);
    addTearDown(database.close);

    await tester.tap(find.textContaining('Ana'));
    await tester.pump();
    await _enterPin(tester, '4321');

    for (final visible in ['Punto de Venta', 'Ventas', 'Clientes', 'Caja']) {
      expect(find.text(visible), findsWidgets, reason: visible);
    }
    for (final hidden in ['Inicio', 'Inventario', 'Categorías', 'Unidades', 'Reportes', 'Usuarios', 'Negocio']) {
      expect(find.text(hidden), findsNothing, reason: hidden);
    }
    await _teardown(tester);
  });

  testWidgets('un cajero no entra a una pantalla de administrador ni escribiendo la ruta', (tester) async {
    final database = await _mount(tester, users: [
      ('Dueña', UserRole.admin, '1234'),
      ('Ana', UserRole.cashier, '4321'),
    ]);
    addTearDown(database.close);
    await tester.tap(find.textContaining('Ana'));
    await tester.pump();
    await _enterPin(tester, '4321');

    final router = GoRouter.of(tester.element(find.byType(Scaffold).first));
    for (final path in ['/users', '/business', '/inventory', '/dashboard', '/reports']) {
      router.go(path);
      await _settle(tester);
      expect(router.state.uri.path, '/pos', reason: path);
    }
    await _teardown(tester);
  });

  testWidgets('sin sesión, cualquier ruta lleva al acceso con PIN', (tester) async {
    final database = await _mount(tester, users: [('Dueña', UserRole.admin, '1234')]);
    addTearDown(database.close);

    final router = GoRouter.of(tester.element(find.byType(Scaffold).first));
    router.go('/inventory');
    await _settle(tester);
    expect(router.state.uri.path, '/login');
    expect(find.text('Escribe tu PIN'), findsOneWidget);
    await _teardown(tester);
  });

  testWidgets('cerrar sesión regresa al acceso con PIN', (tester) async {
    final database = await _mount(tester, users: [('Dueña', UserRole.admin, '1234')]);
    addTearDown(database.close);
    await _enterPin(tester, '1234');
    expect(find.text('Punto de Venta'), findsWidgets);

    await tester.tap(find.byTooltip('Cerrar sesión').first);
    await _settle(tester);

    expect(find.text('Escribe tu PIN'), findsOneWidget);
    expect(find.text('Punto de Venta'), findsNothing);
    await _teardown(tester);
  });

  testWidgets('la sesión se bloquea sola tras un rato sin actividad', (tester) async {
    _ignoreOverflow();
    await tester.binding.setSurfaceSize(const Size(1400, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    await tester.runAsync(() => DriftUserRepository(database, hasher: const PinHasher(iterations: 5))
        .create(name: 'Dueña', role: UserRole.admin, pin: '1234'));
    await tester.pumpWidget(GroceryPosApp(
      database: database,
      idleLockAfter: const Duration(seconds: 30),
      pinHasher: const PinHasher(iterations: 5),
    ));
    await _settle(tester);
    await _enterPin(tester, '1234');
    expect(find.text('Punto de Venta'), findsWidgets);

    await tester.pump(const Duration(seconds: 31));
    await _settle(tester);

    expect(find.text('Escribe tu PIN'), findsOneWidget);
    await _teardown(tester);
  });
}
