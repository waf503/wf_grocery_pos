import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:wf_grocery_pos/core/database/app_database.dart';
import 'package:wf_grocery_pos/core/money.dart';
import 'package:wf_grocery_pos/features/cash/data/drift_cash_repository.dart';
import 'package:wf_grocery_pos/features/categories/data/category_seeder.dart';
import 'package:wf_grocery_pos/features/customers/data/customer_repository.dart';
import 'package:wf_grocery_pos/features/customers/data/drift_customer_repository.dart';
import 'package:wf_grocery_pos/features/products/data/product_seeder.dart';
import 'package:wf_grocery_pos/features/sales/data/drift_sale_repository.dart';
import 'package:wf_grocery_pos/features/sales/data/sale_repository.dart';
import 'package:wf_grocery_pos/features/units/data/unit_seeder.dart';
import 'package:wf_grocery_pos/models/cash_session.dart';
import 'package:wf_grocery_pos/models/customer.dart';
import 'package:wf_grocery_pos/models/sale.dart';

Future<AppDatabase> _seededDb([AppDatabase? db]) async {
  db ??= AppDatabase.forTesting(NativeDatabase.memory());
  final categoryIds = await seedCategoriesIfEmpty(db);
  final unitIds = await seedUnitsIfEmpty(db);
  await seedProductsIfEmpty(db, categoryIds, unitIds);
  return db;
}

Future<ProductsTableData> _product(AppDatabase db, String name) {
  return (db.select(db.productsTable)..where((row) => row.name.equals(name))).getSingle();
}

SaleLine _line(ProductsTableData product, double quantity) => SaleLine(
      productId: product.id,
      productName: product.name,
      quantity: quantity,
      unitPriceCents: product.priceCents,
      unitCostCents: product.costCents,
    );

void main() {
  group('clientes, fiado y anulación', () {
    late AppDatabase db;
    late DriftCashRepository cash;
    late DriftSaleRepository sales;
    late DriftCustomerRepository customers;
    late CashSession session;
    late ProductsTableData cola;

    Future<Customer> carmen() async {
      await customers.add(name: 'Doña Carmen', phone: '7000-0000');
      return (await customers.watchAll().first).single;
    }

    Future<int> balanceOf(String id) async =>
        (await customers.watchAll().first).firstWhere((c) => c.id == id).balanceCents;

    setUp(() async {
      db = await _seededDb();
      cash = DriftCashRepository(db);
      sales = DriftSaleRepository(db);
      customers = DriftCustomerRepository(db);
      session = await cash.open(openingCents: toCents(100));
      cola = await _product(db, 'Coca-Cola Lata 355ml');
    });

    tearDown(() => db.close());

    test('una venta a crédito carga el saldo del cliente y no mueve la caja', () async {
      final carmenRow = await carmen();
      final sale = await sales.registerSale(
        sessionId: session.id,
        lines: [_line(cola, 2)],
        paymentMethod: PaymentMethod.credit,
        customerId: carmenRow.id,
      );

      expect(await balanceOf(carmenRow.id), sale.totalCents);
      expect(sale.customerName, 'Doña Carmen');
      final current = await cash.watchCurrent().first;
      expect(current!.expectedCents, 10000);
    });

    test('el fiado sin cliente registrado se rechaza y no guarda nada', () async {
      await expectLater(
        sales.registerSale(
          sessionId: session.id,
          lines: [_line(cola, 1)],
          paymentMethod: PaymentMethod.credit,
        ),
        throwsA(isA<CreditRequiresCustomerException>()),
      );
      expect(await sales.watchBetween(DateTime(2000)).first, isEmpty);
      expect((await _product(db, cola.name)).stock, cola.stock);
    });

    test('un abono en efectivo baja el saldo y entra a la caja; no puede exceder la deuda', () async {
      final c = await carmen();
      final sale = await sales.registerSale(
        sessionId: session.id,
        lines: [_line(cola, 2)],
        paymentMethod: PaymentMethod.credit,
        customerId: c.id,
      );

      await customers.registerPayment(customerId: c.id, amountCents: 500, cashSessionId: session.id);
      expect(await balanceOf(c.id), sale.totalCents - 500);
      expect((await cash.watchCurrent().first)!.expectedCents, 10000 + 500);

      await expectLater(
        customers.registerPayment(customerId: c.id, amountCents: sale.totalCents),
        throwsA(isA<PaymentExceedsBalanceException>()),
      );
      expect(await balanceOf(c.id), sale.totalCents - 500);

      final statement = await customers.watchMovements(c.id).first;
      expect(statement.map((m) => m.type), containsAll([CustomerMovementType.charge, CustomerMovementType.payment]));
    });

    test('no se elimina un cliente con deuda; uno saldado sí, y sus ventas se conservan', () async {
      final c = await carmen();
      final sale = await sales.registerSale(
        sessionId: session.id,
        lines: [_line(cola, 1)],
        paymentMethod: PaymentMethod.credit,
        customerId: c.id,
      );
      expect(await customers.delete(c.id), DeleteCustomerResult.hasBalance);

      await customers.registerPayment(customerId: c.id, amountCents: sale.totalCents);
      expect(await customers.delete(c.id), DeleteCustomerResult.deleted);
      expect(await customers.watchAll().first, isEmpty);

      final history = await sales.watchBetween(DateTime(2000)).first;
      expect(history.single.customerName, 'Doña Carmen');
    });

    test('anular una venta en efectivo devuelve stock y saca el dinero de la caja', () async {
      final sale = await sales.registerSale(
        sessionId: session.id,
        lines: [_line(cola, 3)],
        paymentMethod: PaymentMethod.cash,
      );
      expect((await _product(db, cola.name)).stock, cola.stock - 3);
      expect((await cash.watchCurrent().first)!.expectedCents, 10000 + sale.totalCents);

      await sales.voidSale(saleId: sale.id, reason: 'Error de cobro', cashSessionId: session.id);

      expect((await _product(db, cola.name)).stock, cola.stock);
      expect((await cash.watchCurrent().first)!.expectedCents, 10000);
      final voided = (await sales.watchBetween(DateTime(2000)).first).single;
      expect(voided.isVoided, isTrue);
      expect(voided.voidReason, 'Error de cobro');
      expect(voided.voidedAt, isNotNull);
    });

    test('anular una venta en efectivo exige caja abierta y no cambia nada si falla', () async {
      final sale = await sales.registerSale(
        sessionId: session.id,
        lines: [_line(cola, 1)],
        paymentMethod: PaymentMethod.cash,
      );
      await expectLater(
        sales.voidSale(saleId: sale.id, reason: 'x'),
        throwsA(isA<CashSessionClosedException>()),
      );
      expect((await sales.watchBetween(DateTime(2000)).first).single.isVoided, isFalse);
      expect((await _product(db, cola.name)).stock, cola.stock - 1);
    });

    test('anular una venta a crédito revierte la deuda; no se anula dos veces', () async {
      final c = await carmen();
      final sale = await sales.registerSale(
        sessionId: session.id,
        lines: [_line(cola, 2)],
        paymentMethod: PaymentMethod.credit,
        customerId: c.id,
      );
      await sales.voidSale(saleId: sale.id, reason: 'Cliente se arrepintió');

      expect(await balanceOf(c.id), 0);
      expect((await cash.watchCurrent().first)!.expectedCents, 10000);
      await expectLater(
        sales.voidSale(saleId: sale.id, reason: 'otra vez'),
        throwsA(isA<SaleAlreadyVoidedException>()),
      );
    });

    test('watchBetween filtra por rango [desde, hasta) y permite consultar fechas antiguas', () async {
      var now = DateTime(2025, 3, 10, 9);
      final dated = DriftSaleRepository(db, clock: () => now);
      for (final day in [DateTime(2025, 3, 10, 9), DateTime(2025, 3, 11, 18), DateTime(2025, 3, 12, 8)]) {
        now = day;
        await dated.registerSale(
          sessionId: session.id,
          lines: [_line(cola, 1)],
          paymentMethod: PaymentMethod.card,
        );
      }

      // Día 11 completo: de 11/mar 00:00 a 12/mar 00:00 (excluido).
      final oneDay = await dated.watchBetween(DateTime(2025, 3, 11), to: DateTime(2025, 3, 12)).first;
      expect(oneDay.map((s) => s.number), [2]);

      final range = await dated.watchBetween(DateTime(2025, 3, 10), to: DateTime(2025, 3, 13)).first;
      expect(range.map((s) => s.number), [3, 2, 1]);

      expect(await dated.watchBetween(DateTime(2025, 3, 10)).first, hasLength(3));
    });

    test('anular una venta cuyo producto ya se borró no falla', () async {
      final sale = await sales.registerSale(
        sessionId: session.id,
        lines: [_line(cola, 1)],
        paymentMethod: PaymentMethod.card,
      );
      await (db.delete(db.productsTable)..where((row) => row.id.equals(cola.id))).go();
      await sales.voidSale(saleId: sale.id, reason: 'Devolución');
      expect((await sales.watchBetween(DateTime(2000)).first).single.isVoided, isTrue);
    });
  });

  group('migración v9 → v10', () {
    late Directory tempDir;
    late File dbFile;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('wf_customers_test');
      dbFile = File(p.join(tempDir.path, 'test.sqlite'));
    });

    tearDown(() => tempDir.delete(recursive: true));

    test('conserva las ventas existentes como vigentes y crea las tablas de clientes', () async {
      final seeded = await _seededDb(AppDatabase.forTesting(NativeDatabase(dbFile)));
      final cola = await _product(seeded, 'Coca-Cola Lata 355ml');
      final session = await DriftCashRepository(seeded).open(openingCents: 1000);
      await DriftSaleRepository(seeded).registerSale(
        sessionId: session.id,
        lines: [_line(cola, 2)],
        paymentMethod: PaymentMethod.cash,
      );

      // Se devuelve la base al estado de la v9: sin tablas de clientes ni
      // columnas de anulación en `sales`.
      await seeded.customStatement('DROP TABLE customer_account_movements');
      await seeded.customStatement('DROP TABLE customers');
      await seeded.customStatement('ALTER TABLE sales DROP COLUMN status');
      await seeded.customStatement('ALTER TABLE sales DROP COLUMN voided_at');
      await seeded.customStatement('ALTER TABLE sales DROP COLUMN void_reason');
      await seeded.customStatement('ALTER TABLE products DROP COLUMN updated_at');
      await seeded.customStatement('PRAGMA user_version = 9');
      await seeded.close();

      final migrated = AppDatabase.forTesting(NativeDatabase(dbFile));
      addTearDown(migrated.close);
      final history = await DriftSaleRepository(migrated).watchBetween(DateTime(2000)).first;
      expect(history.single.isVoided, isFalse);
      expect(history.single.number, 1);

      final customers = DriftCustomerRepository(migrated);
      await customers.add(name: 'Don Rafael');
      expect((await customers.watchAll().first).single.balanceCents, 0);
    });
  });
}
