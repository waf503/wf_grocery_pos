import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:wf_grocery_pos/core/database/app_database.dart';
import 'package:wf_grocery_pos/features/cash/data/drift_cash_repository.dart';
import 'package:wf_grocery_pos/features/categories/data/category_seeder.dart';
import 'package:wf_grocery_pos/features/customers/data/drift_customer_repository.dart';
import 'package:wf_grocery_pos/features/products/data/product_seeder.dart';
import 'package:wf_grocery_pos/features/sales/data/drift_sale_repository.dart';
import 'package:wf_grocery_pos/features/sales/data/sale_repository.dart';
import 'package:wf_grocery_pos/features/units/data/unit_seeder.dart';
import 'package:wf_grocery_pos/models/cash_session.dart';
import 'package:wf_grocery_pos/models/customer.dart';
import 'package:wf_grocery_pos/models/sale.dart';

/// Deja una base con un cliente que debe $4.00 (venta a fiado) y una caja abierta.
Future<({AppDatabase db, String sessionId, String customerId})> _debtor([AppDatabase? existing]) async {
  final db = existing ?? AppDatabase.forTesting(NativeDatabase.memory());
  final categoryIds = await seedCategoriesIfEmpty(db);
  final unitIds = await seedUnitsIfEmpty(db);
  await seedProductsIfEmpty(db, categoryIds, unitIds);
  final product = (await db.select(db.productsTable).get()).first;
  final session = await DriftCashRepository(db).open(openingCents: 1000);
  final customers = DriftCustomerRepository(db);
  await customers.add(name: 'Carmen');
  final carmen = await db.select(db.customersTable).getSingle();
  await DriftSaleRepository(db).registerSale(
    sessionId: session.id,
    lines: [
      SaleLine(
        productId: product.id,
        productName: product.name,
        quantity: 1,
        unitPriceCents: 400,
        unitCostCents: 100,
        fixedSubtotalCents: 400,
      ),
    ],
    paymentMethod: PaymentMethod.credit,
    customerId: carmen.id,
  );
  return (db: db, sessionId: session.id, customerId: carmen.id);
}

void main() {
  test('el abono guarda quién lo recibió, en el estado de cuenta y en la caja', () async {
    final d = await _debtor();
    addTearDown(d.db.close);
    final customers = DriftCustomerRepository(d.db);

    await customers.registerPayment(
      customerId: d.customerId,
      amountCents: 150,
      cashSessionId: d.sessionId,
      receivedBy: 'Ana',
    );

    final statement = await customers.watchMovements(d.customerId).first;
    final payment = statement.singleWhere((m) => m.type == CustomerMovementType.payment);
    expect(payment.receivedBy, 'Ana');
    // Los cargos no llevan "recibió".
    expect(statement.singleWhere((m) => m.type == CustomerMovementType.charge).receivedBy, isNull);

    final session = (await DriftCashRepository(d.db).watchCurrent().first)!;
    final cashMovement = session.movements.singleWhere((m) => m.type == CashMovementType.customerPayment);
    expect(cashMovement.createdBy, 'Ana');
    expect(cashMovement.note, 'Abono de Carmen');
  });

  test('un abono sin usuario (antiguo o de pruebas) sigue funcionando', () async {
    final d = await _debtor();
    addTearDown(d.db.close);
    final customers = DriftCustomerRepository(d.db);

    await customers.registerPayment(customerId: d.customerId, amountCents: 100, cashSessionId: d.sessionId);
    final payment = (await customers.watchMovements(d.customerId).first)
        .singleWhere((m) => m.type == CustomerMovementType.payment);
    expect(payment.receivedBy, isNull);
  });

  test('un abono fuera de caja (transferencia) también guarda quién lo recibió', () async {
    final d = await _debtor();
    addTearDown(d.db.close);
    final customers = DriftCustomerRepository(d.db);

    await customers.registerPayment(customerId: d.customerId, amountCents: 100, receivedBy: 'Luis');
    final payment = (await customers.watchMovements(d.customerId).first)
        .singleWhere((m) => m.type == CustomerMovementType.payment);
    expect(payment.receivedBy, 'Luis');
    // No entró efectivo a la caja.
    final session = (await DriftCashRepository(d.db).watchCurrent().first)!;
    expect(session.movements.where((m) => m.type == CashMovementType.customerPayment), isEmpty);
  });

  test('migración v20 → v21: conserva los abonos y agrega la columna de quién', () async {
    final dir = await Directory.systemTemp.createTemp('wf_payment_who_test');
    addTearDown(() => dir.delete(recursive: true));
    final file = File(p.join(dir.path, 'test.sqlite'));

    final seeded = AppDatabase.forTesting(NativeDatabase(file));
    final d = await _debtor(seeded);
    await DriftCustomerRepository(seeded).registerPayment(
      customerId: d.customerId,
      amountCents: 100,
      cashSessionId: d.sessionId,
      receivedBy: 'Ana',
    );
    await seeded.customStatement('ALTER TABLE customer_account_movements DROP COLUMN received_by');
    await seeded.customStatement('PRAGMA user_version = 20');
    await seeded.close();

    final migrated = AppDatabase.forTesting(NativeDatabase(file));
    addTearDown(migrated.close);
    final customers = DriftCustomerRepository(migrated);
    final statement = await customers.watchMovements(d.customerId).first;
    expect(statement.where((m) => m.type == CustomerMovementType.payment), hasLength(1));
    expect(statement.every((m) => m.receivedBy == null), isTrue);

    // Y ya se pueden registrar abonos con nombre.
    await customers.registerPayment(customerId: d.customerId, amountCents: 50, receivedBy: 'Luis');
    final after = await customers.watchMovements(d.customerId).first;
    expect(after.where((m) => m.receivedBy == 'Luis'), hasLength(1));
  });
}
