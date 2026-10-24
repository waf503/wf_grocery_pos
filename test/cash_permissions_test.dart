import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

import 'package:wf_grocery_pos/core/database/app_database.dart';
import 'package:wf_grocery_pos/core/security/pin_hasher.dart';
import 'package:wf_grocery_pos/features/auth/data/drift_user_repository.dart';
import 'package:wf_grocery_pos/features/cash/cash_screen.dart';
import 'package:wf_grocery_pos/features/cash/data/drift_cash_repository.dart';
import 'package:wf_grocery_pos/features/sales/data/drift_sale_repository.dart';
import 'package:wf_grocery_pos/features/settings/data/settings_repository.dart';
import 'package:wf_grocery_pos/models/app_user.dart';
import 'package:wf_grocery_pos/models/cash_session.dart';
import 'package:wf_grocery_pos/state/auth_provider.dart';
import 'package:wf_grocery_pos/state/cash_provider.dart';
import 'package:wf_grocery_pos/state/sales_provider.dart';
import 'package:wf_grocery_pos/state/settings_provider.dart';

/// Las pruebas usan una fuente muy ancha: los desbordes de diseño no son lo
/// que se prueba aquí.
void _ignoreOverflow() {
  final original = FlutterError.onError;
  FlutterError.onError = (details) {
    if (details.exceptionAsString().contains('overflowed')) return;
    original?.call(details);
  };
  addTearDown(() => FlutterError.onError = original);
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 5; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pump(const Duration(milliseconds: 100));
  }
}

class _Harness {
  _Harness(this.db, this.auth, this.cash, this.settings, this.sales);

  final SalesProvider sales;

  final AppDatabase db;
  final AuthProvider auth;
  final CashProvider cash;
  final SettingsProvider settings;
}

_Harness? _current;

/// Cierra el árbol, suelta los providers y la base. Va al final de cada prueba:
/// Drift deja un temporizador al cancelar sus flujos y hay que dejarlo correr.
Future<void> _finish(WidgetTester tester) async {
  final h = _current;
  if (h == null) return;
  _current = null;
  await tester.pumpWidget(const SizedBox());
  h.cash.dispose();
  h.auth.dispose();
  h.settings.dispose();
  h.sales.dispose();
  await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
  await tester.pump(const Duration(seconds: 1));
  await tester.runAsync(h.db.close);
}

void _cashTest(String name, Future<void> Function(WidgetTester tester) body) {
  testWidgets(name, (tester) async {
    await body(tester);
    await _finish(tester);
  });
}

/// Pantalla de Caja con la sesión de un administrador ('Dueña', PIN 1234) o de
/// un cajero ('Ana', PIN 4321).
Future<_Harness> _mount(WidgetTester tester, {required bool asAdmin, bool openCash = true}) async {
  _ignoreOverflow();
  await tester.binding.setSurfaceSize(const Size(1400, 1000));
  addTearDown(() => tester.binding.setSurfaceSize(null));

  final db = AppDatabase.forTesting(NativeDatabase.memory());
  final auth = AuthProvider(DriftUserRepository(db, hasher: const PinHasher(iterations: 5)));
  final settings = SettingsProvider(DriftSettingsRepository(db));

  await tester.runAsync(() async {
    await auth.load();
    await settings.load();
    await auth.createFirstAdmin(name: 'Dueña', pin: '1234');
    final ana = await auth.addUser(name: 'Ana', role: UserRole.cashier, pin: '4321');
    if (!asAdmin) {
      auth.logout();
      await auth.login(ana.id, '4321');
    }
    if (openCash) {
      await DriftCashRepository(db).open(openingCents: 10000, openedBy: auth.currentUser!.name);
    }
  });

  final cash = CashProvider(DriftCashRepository(db));
  final sales = SalesProvider(DriftSaleRepository(db));

  await tester.pumpWidget(MultiProvider(
    providers: [
      ChangeNotifierProvider.value(value: auth),
      ChangeNotifierProvider.value(value: cash),
      ChangeNotifierProvider.value(value: settings),
      ChangeNotifierProvider.value(value: sales),
    ],
    child: const MaterialApp(home: Scaffold(body: CashScreen())),
  ));
  await _settle(tester);
  _current = _Harness(db, auth, cash, settings, sales);
  return _current!;
}

Future<void> _fillMovement(WidgetTester tester, String amount, String reason) async {
  final fields = find.byType(TextFormField);
  await tester.enterText(fields.at(0), amount);
  await tester.enterText(fields.at(1), reason);
  await tester.tap(find.text('Guardar'));
  await _settle(tester);
}

void main() {
  // La pantalla formatea fechas en español (la app lo hace al arrancar).
  setUpAll(() => initializeDateFormatting('es_MX'));

  group('lo que ve cada rol en Caja', () {
    _cashTest('el administrador ve el historial, el total en caja y las entradas/salidas', (tester) async {
      await _mount(tester, asAdmin: true);
      expect(find.text('Historial'), findsOneWidget);
      expect(find.text('Total en caja'), findsOneWidget);
      expect(find.text('Entradas / Salidas'), findsOneWidget);
    });

    _cashTest('el cajero NO ve el historial, ni el total en caja, ni las entradas/salidas', (tester) async {
      await _mount(tester, asAdmin: false);
      expect(find.text('Historial'), findsNothing);
      expect(find.text('Total en caja'), findsNothing);
      expect(find.text('Entradas / Salidas'), findsNothing);
      // Sí ve lo suyo: el fondo y las ventas del turno.
      expect(find.text('Fondo inicial'), findsOneWidget);
      expect(find.text('Total ventas'), findsOneWidget);
    });
  });

  group('cierre de caja', () {
    _cashTest('el cajero cierra a ciegas: campo vacío, sin esperado ni diferencia, y queda registrado quién cerró', (tester) async {
      final h = await _mount(tester, asAdmin: false);

      await tester.tap(find.text('Cerrar caja'));
      await tester.pumpAndSettle();
      expect(find.text('Cuenta el efectivo que hay en la caja y escribe el total.'), findsOneWidget);
      expect(tester.widget<TextFormField>(find.byType(TextFormField)).controller!.text, isEmpty);
      expect(find.descendant(of: find.byType(AlertDialog), matching: find.textContaining('Fondo')), findsNothing); // sin desglose

      await tester.enterText(find.byType(TextFormField), '95');
      await tester.pump();
      expect(find.textContaining('Faltan'), findsNothing); // no ve la diferencia
      await tester.tap(find.descendant(of: find.byType(AlertDialog), matching: find.text('Cerrar caja')).last);
      await _settle(tester);

      expect(find.text('Se registró el conteo. El administrador revisará el cuadre del turno.'), findsOneWidget);
      final closed = (await tester.runAsync(() => h.db.select(h.db.cashSessionsTable).getSingle()))!;
      expect(closed.closedBy, 'Ana');
      expect(closed.openedBy, 'Ana');
      expect(closed.closingCountedCents, 9500);
    });

    _cashTest('el administrador ve el desglose y la diferencia antes de cerrar', (tester) async {
      await _mount(tester, asAdmin: true);

      await tester.tap(find.text('Cerrar caja'));
      await tester.pumpAndSettle();
      expect(tester.widget<TextFormField>(find.byType(TextFormField)).controller!.text, '100.00');

      await tester.enterText(find.byType(TextFormField), '95');
      await tester.pump();
      expect(find.textContaining('Faltan'), findsOneWidget);
    });
  });

  group('retiros e ingresos', () {
    _cashTest('el cajero retira un monto pequeño sin autorización, y queda su nombre', (tester) async {
      final h = await _mount(tester, asAdmin: false);

      await tester.tap(find.text('Retiro'));
      await tester.pumpAndSettle();
      await _fillMovement(tester, '5', 'Pago de hielo');

      expect(find.text('Autorizar retiro'), findsNothing);
      final m = (await tester.runAsync(() => h.db.select(h.db.cashMovementsTable).getSingle()))!;
      expect(m.createdBy, 'Ana');
      expect(m.note, 'Pago de hielo');
      expect(m.amountCents, 500);
    });

    _cashTest('arriba del tope pide el PIN de un administrador; con uno incorrecto no se registra', (tester) async {
      final h = await _mount(tester, asAdmin: false);

      await tester.tap(find.text('Retiro'));
      await tester.pumpAndSettle();
      await _fillMovement(tester, '50', 'Pago a proveedor');
      expect(find.text('Autorizar retiro'), findsOneWidget);

      // El PIN de la propia cajera NO autoriza.
      await tester.enterText(find.byType(TextField), '4321');
      await tester.tap(find.text('Autorizar'));
      await _settle(tester);
      expect(find.text('PIN incorrecto'), findsOneWidget);
      expect((await tester.runAsync(() => h.db.select(h.db.cashMovementsTable).get()))!, isEmpty);

      // El del administrador sí.
      await tester.enterText(find.byType(TextField), '1234');
      await tester.tap(find.text('Autorizar'));
      await _settle(tester);
      final m = (await tester.runAsync(() => h.db.select(h.db.cashMovementsTable).getSingle()))!;
      expect(m.createdBy, 'Ana');
      expect(m.note, 'Pago a proveedor (autorizó Dueña)');
      expect(m.amountCents, 5000);
    });

    _cashTest('cancelar la autorización no registra nada', (tester) async {
      final h = await _mount(tester, asAdmin: false);
      await tester.tap(find.text('Ingreso'));
      await tester.pumpAndSettle();
      await _fillMovement(tester, '60', 'Cambio del banco');
      expect(find.text('Autorizar ingreso'), findsOneWidget);

      await tester.tap(find.text('Cancelar'));
      await _settle(tester);
      expect((await tester.runAsync(() => h.db.select(h.db.cashMovementsTable).get()))!, isEmpty);
    });

    _cashTest('el administrador no necesita autorización, sin importar el monto', (tester) async {
      final h = await _mount(tester, asAdmin: true);
      await tester.tap(find.text('Retiro'));
      await tester.pumpAndSettle();
      await _fillMovement(tester, '50', 'Depósito al banco');

      expect(find.text('Autorizar retiro'), findsNothing);
      final m = (await tester.runAsync(() => h.db.select(h.db.cashMovementsTable).getSingle()))!;
      expect(m.createdBy, 'Dueña');
      expect(m.note, 'Depósito al banco');
    });

    _cashTest('el tope es configurable: con 0 todo movimiento del cajero pide autorización', (tester) async {
      final h = await _mount(tester, asAdmin: false);
      await tester.runAsync(() => h.settings.setCashMovementLimitCents(0));

      await tester.tap(find.text('Retiro'));
      await tester.pumpAndSettle();
      await _fillMovement(tester, '1', 'Bolsas');
      expect(find.text('Autorizar retiro'), findsOneWidget);
    });
  });

  group('registro de quién', () {
    test('el turno guarda quién lo abrió y quién lo cerró, y el movimiento quién lo hizo', () async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      final repo = DriftCashRepository(db);

      final session = await repo.open(openingCents: 1000, openedBy: 'Ana');
      expect(session.openedBy, 'Ana');
      await repo.addMovement(
        sessionId: session.id,
        type: CashMovementType.deposit,
        amountCents: 200,
        note: 'Cambio',
        createdBy: 'Ana',
      );
      final closed = await repo.close(sessionId: session.id, countedCents: 1200, closedBy: 'Luis');

      expect(closed.openedBy, 'Ana');
      expect(closed.closedBy, 'Luis');
      expect(closed.movements.single.createdBy, 'Ana');
      expect(closed.differenceCents, 0);
    });

    test('un turno sin usuarios (antiguo) sigue funcionando', () async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      final repo = DriftCashRepository(db);
      final session = await repo.open(openingCents: 500);
      expect(session.openedBy, isNull);
      expect((await repo.close(sessionId: session.id, countedCents: 500)).closedBy, isNull);
    });

    test('el tope de retiros se guarda y vale 20 dólares por defecto', () async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      final settings = SettingsProvider(DriftSettingsRepository(db));
      addTearDown(settings.dispose);
      await settings.load();
      expect(settings.cashMovementLimitCents, 2000);

      await settings.setCashMovementLimitCents(500);
      final reloaded = SettingsProvider(DriftSettingsRepository(db));
      addTearDown(reloaded.dispose);
      await reloaded.load();
      expect(reloaded.cashMovementLimitCents, 500);
      expect(() => settings.setCashMovementLimitCents(-1), throwsArgumentError);
    });
  });

  test('migración v19 → v20: conserva el turno y agrega las columnas de quién', () async {
    final dir = await Directory.systemTemp.createTemp('wf_cash_audit_test');
    addTearDown(() => dir.delete(recursive: true));
    final file = File(p.join(dir.path, 'test.sqlite'));

    final seeded = AppDatabase.forTesting(NativeDatabase(file));
    final session = await DriftCashRepository(seeded).open(openingCents: 700);
    await DriftCashRepository(seeded).addMovement(
      sessionId: session.id,
      type: CashMovementType.deposit,
      amountCents: 100,
      note: 'Cambio',
    );
    await seeded.customStatement('ALTER TABLE cash_sessions DROP COLUMN opened_by');
    await seeded.customStatement('ALTER TABLE cash_sessions DROP COLUMN closed_by');
    await seeded.customStatement('ALTER TABLE cash_movements DROP COLUMN created_by');
    await seeded.customStatement('ALTER TABLE customer_account_movements DROP COLUMN received_by');
    await seeded.customStatement('PRAGMA user_version = 19');
    await seeded.close();

    final migrated = AppDatabase.forTesting(NativeDatabase(file));
    addTearDown(migrated.close);
    final repo = DriftCashRepository(migrated);
    final current = await repo.watchCurrent().first;
    expect(current!.openingCents, 700);
    expect(current.openedBy, isNull);
    expect(current.movements.single.createdBy, isNull);

    final closed = await repo.close(sessionId: current.id, countedCents: 800, closedBy: 'Ana');
    expect(closed.closedBy, 'Ana');
  });
}
