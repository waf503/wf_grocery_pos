import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:wf_grocery_pos/core/database/app_database.dart';
import 'package:wf_grocery_pos/features/cash/data/cash_repository.dart';
import 'package:wf_grocery_pos/features/cash/data/drift_cash_repository.dart';
import 'package:wf_grocery_pos/features/categories/data/category_seeder.dart';
import 'package:wf_grocery_pos/features/customers/data/drift_customer_repository.dart';
import 'package:wf_grocery_pos/features/products/data/product_seeder.dart';
import 'package:wf_grocery_pos/features/sales/data/drift_sale_repository.dart';
import 'package:wf_grocery_pos/features/sales/data/sale_repository.dart';
import 'package:wf_grocery_pos/features/units/data/unit_seeder.dart';
import 'package:wf_grocery_pos/models/cash_session.dart';
import 'package:wf_grocery_pos/models/sale.dart';

Future<AppDatabase> _seededDb([AppDatabase? db]) async {
  db ??= AppDatabase.forTesting(NativeDatabase.memory());
  final categoryIds = await seedCategoriesIfEmpty(db);
  final unitIds = await seedUnitsIfEmpty(db);
  await seedProductsIfEmpty(db, categoryIds, unitIds);
  return db;
}

SaleLine _line(ProductsTableData product, double quantity) => SaleLine(
      productId: product.id,
      productName: product.name,
      quantity: quantity,
      unitPriceCents: product.priceCents,
      unitCostCents: product.costCents,
    );

void main() {
  group('caja registradora', () {
    late AppDatabase db;
    late DriftCashRepository cash;
    late DriftSaleRepository sales;
    late CashSession session;
    late ProductsTableData cola;

    setUp(() async {
      db = await _seededDb();
      cash = DriftCashRepository(db);
      sales = DriftSaleRepository(db);
      session = await cash.open(openingCents: 10000);
      cola = await (db.select(db.productsTable)..where((r) => r.name.equals('Coca-Cola Lata 355ml'))).getSingle();
    });

    tearDown(() => db.close());

    test('al cerrar devuelve el turno con esperado, contado y diferencia', () async {
      await sales.registerSale(sessionId: session.id, lines: [_line(cola, 2)], paymentMethod: PaymentMethod.cash);
      final expected = 10000 + cola.priceCents * 2;

      final closed = await cash.close(sessionId: session.id, countedCents: expected - 150);

      expect(closed.isOpen, isFalse);
      expect(closed.expectedCents, expected);
      expect(closed.closingCountedCents, expected - 150);
      expect(closed.differenceCents, -150); // faltante
      expect(await cash.watchCurrent().first, isNull);
    });

    test('cerrar una caja ya cerrada falla', () async {
      await cash.close(sessionId: session.id, countedCents: 10000);
      await expectLater(
        cash.close(sessionId: session.id, countedCents: 10000),
        throwsA(isA<CashSessionNotOpenException>()),
      );
    });

    test('el historial lista los turnos cerrados, del más reciente al más antiguo', () async {
      var now = DateTime(2025, 1, 1, 8);
      final repo = DriftCashRepository(db, clock: () => now);
      now = DateTime(2025, 1, 1, 20);
      await repo.close(sessionId: session.id, countedCents: 10000);
      now = DateTime(2025, 2, 1, 8);
      final second = await repo.open(openingCents: 5000);
      now = DateTime(2025, 2, 1, 20);
      await repo.close(sessionId: second.id, countedCents: 5000);
      final open = await cash.open(openingCents: 100); // un turno abierto no aparece

      final history = await cash.watchClosed().first;
      expect(history.map((s) => s.id), [second.id, session.id]);
      expect(history.any((s) => s.id == open.id), isFalse);
    });

    test('las ventas del turno incluyen todos los métodos y las anuladas quedan marcadas', () async {
      await db.into(db.customersTable).insert(CustomersTableCompanion.insert(id: const Value('c1'), name: 'Ana'));
      await sales.registerSale(sessionId: session.id, lines: [_line(cola, 1)], paymentMethod: PaymentMethod.cash);
      final card = await sales.registerSale(
        sessionId: session.id,
        lines: [_line(cola, 1)],
        paymentMethod: PaymentMethod.card,
      );
      await sales.registerSale(
        sessionId: session.id,
        lines: [_line(cola, 2)],
        paymentMethod: PaymentMethod.credit,
        customerId: 'c1',
      );
      await sales.voidSale(saleId: card.id, reason: 'error');

      // Una venta de OTRO turno no debe aparecer.
      await cash.close(sessionId: session.id, countedCents: 0);
      final other = await cash.open(openingCents: 0);
      await sales.registerSale(sessionId: other.id, lines: [_line(cola, 1)], paymentMethod: PaymentMethod.cash);

      final list = await sales.watchBySession(session.id).first;
      expect(list.map((s) => s.paymentMethod).toSet(), {PaymentMethod.credit, PaymentMethod.card, PaymentMethod.cash});
      expect(list.where((s) => s.isVoided).single.id, card.id);
      expect(await sales.watchBySession(other.id).first, hasLength(1));
    });

    test('abonos y anulaciones tienen su propio tipo y mantienen el esperado correcto', () async {
      await db.into(db.customersTable).insert(CustomersTableCompanion.insert(id: const Value('c1'), name: 'Ana'));
      await sales.registerSale(
        sessionId: session.id,
        lines: [_line(cola, 2)],
        paymentMethod: PaymentMethod.credit,
        customerId: 'c1',
      );
      await DriftCustomerRepository(db).registerPayment(
        customerId: 'c1',
        amountCents: 300,
        cashSessionId: session.id,
      );
      final cashSale = await sales.registerSale(
        sessionId: session.id,
        lines: [_line(cola, 1)],
        paymentMethod: PaymentMethod.cash,
      );
      await sales.voidSale(saleId: cashSale.id, reason: 'x', cashSessionId: session.id);

      final current = (await cash.watchCurrent().first)!;
      expect(current.customerPaymentsCents, 300);
      expect(current.voidsCents, cashSale.totalCents);
      expect(current.depositsCents, 0);
      expect(current.withdrawalsCents, 0);
      expect(current.expectedCents, 10000 + 300); // la venta en efectivo se anuló
    });

    test('un retiro no puede exceder el efectivo en caja', () async {
      await expectLater(
        cash.addMovement(
          sessionId: session.id,
          type: CashMovementType.withdrawal,
          amountCents: 10001,
          note: 'de más',
        ),
        throwsA(isA<InsufficientCashException>()),
      );
      await cash.addMovement(
        sessionId: session.id,
        type: CashMovementType.withdrawal,
        amountCents: 10000,
        note: 'todo',
      );
      expect((await cash.watchCurrent().first)!.expectedCents, 0);
    });

    test('solo ingresos y retiros se registran como movimiento manual', () async {
      expect(
        () => cash.addMovement(
          sessionId: session.id,
          type: CashMovementType.saleVoid,
          amountCents: 100,
          note: 'x',
        ),
        throwsArgumentError,
      );
    });
  });

  group('migración v11 → v12', () {
    late Directory tempDir;
    late File dbFile;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('wf_cash_test');
      dbFile = File(p.join(tempDir.path, 'test.sqlite'));
    });

    tearDown(() => tempDir.delete(recursive: true));

    test('reclasifica abonos y anulaciones antiguos sin tocar ingresos/retiros manuales', () async {
      final seeded = await _seededDb(AppDatabase.forTesting(NativeDatabase(dbFile)));
      final session = await DriftCashRepository(seeded).open(openingCents: 0);
      final seconds = DateTime(2025, 1, 1).millisecondsSinceEpoch ~/ 1000;
      Future<void> insert(String type, String note) => seeded.customStatement(
            'INSERT INTO cash_movements (id, session_id, type, amount_cents, note, created_at) '
            "VALUES ('m_$note', '${session.id}', '$type', 100, '$note', $seconds)",
          );
      await insert('deposit', 'Abono de Ana');
      await insert('withdrawal', 'Anulación V-000001');
      await insert('deposit', 'Cambio inicial');
      await insert('withdrawal', 'Pago a proveedor');
      await seeded.customStatement('PRAGMA user_version = 11');
      await seeded.close();

      final migrated = AppDatabase.forTesting(NativeDatabase(dbFile));
      addTearDown(migrated.close);
      final rows = await migrated.select(migrated.cashMovementsTable).get();
      final typeByNote = {for (final r in rows) r.note: r.type};
      expect(typeByNote['Abono de Ana'], CashMovementType.customerPayment);
      expect(typeByNote['Anulación V-000001'], CashMovementType.saleVoid);
      expect(typeByNote['Cambio inicial'], CashMovementType.deposit);
      expect(typeByNote['Pago a proveedor'], CashMovementType.withdrawal);
    });
  });
}
