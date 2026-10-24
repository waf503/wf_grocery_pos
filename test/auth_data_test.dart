import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:wf_grocery_pos/core/database/app_database.dart';
import 'package:wf_grocery_pos/core/security/pin_hasher.dart';
import 'package:wf_grocery_pos/features/auth/data/drift_user_repository.dart';
import 'package:wf_grocery_pos/features/cash/data/drift_cash_repository.dart';
import 'package:wf_grocery_pos/features/categories/data/category_seeder.dart';
import 'package:wf_grocery_pos/features/products/data/product_seeder.dart';
import 'package:wf_grocery_pos/features/sales/data/drift_sale_repository.dart';
import 'package:wf_grocery_pos/features/sales/data/sale_repository.dart';
import 'package:wf_grocery_pos/features/units/data/unit_seeder.dart';
import 'package:wf_grocery_pos/models/app_user.dart';
import 'package:wf_grocery_pos/models/sale.dart';

Future<AppDatabase> _seededDb([AppDatabase? db]) async {
  db ??= AppDatabase.forTesting(NativeDatabase.memory());
  final categoryIds = await seedCategoriesIfEmpty(db);
  final unitIds = await seedUnitsIfEmpty(db);
  await seedProductsIfEmpty(db, categoryIds, unitIds);
  return db;
}

SaleLine _line(ProductsTableData product) => SaleLine(
      productId: product.id,
      productName: product.name,
      quantity: 1,
      unitPriceCents: product.priceCents,
      unitCostCents: product.costCents,
    );

void main() {
  test('la venta guarda quién cobró y quién autorizó la anulación', () async {
    final db = await _seededDb();
    addTearDown(db.close);
    final product = (await db.select(db.productsTable).get()).first;
    final session = await DriftCashRepository(db).open(openingCents: 1000);
    final repo = DriftSaleRepository(db);

    final sale = await repo.registerSale(
      sessionId: session.id,
      lines: [_line(product)],
      paymentMethod: PaymentMethod.cash,
      cashierName: 'Ana',
    );
    expect(sale.cashierName, 'Ana');
    expect(sale.voidedBy, isNull);

    await repo.voidSale(saleId: sale.id, reason: 'Error', cashSessionId: session.id, voidedBy: 'Dueña');
    final voided = (await repo.watchBySession(session.id).first).single;
    expect(voided.isVoided, isTrue);
    expect(voided.cashierName, 'Ana');
    expect(voided.voidedBy, 'Dueña');
  });

  test('las ventas sin usuario (antiguas o de pruebas) siguen funcionando', () async {
    final db = await _seededDb();
    addTearDown(db.close);
    final product = (await db.select(db.productsTable).get()).first;
    final session = await DriftCashRepository(db).open(openingCents: 0);

    final sale = await DriftSaleRepository(db).registerSale(
      sessionId: session.id,
      lines: [_line(product)],
      paymentMethod: PaymentMethod.cash,
    );
    expect(sale.cashierName, isNull);
  });

  group('migración v17 → v18', () {
    late Directory tempDir;
    late File dbFile;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('wf_auth_test');
      dbFile = File(p.join(tempDir.path, 'test.sqlite'));
    });
    tearDown(() => tempDir.delete(recursive: true));

    test('conserva ventas y productos, y crea la tabla de usuarios vacía', () async {
      final seeded = await _seededDb(AppDatabase.forTesting(NativeDatabase(dbFile)));
      final product = (await seeded.select(seeded.productsTable).get()).first;
      final session = await DriftCashRepository(seeded).open(openingCents: 500);
      await DriftSaleRepository(seeded).registerSale(
        sessionId: session.id,
        lines: [_line(product)],
        paymentMethod: PaymentMethod.cash,
      );
      final productCount = (await seeded.select(seeded.productsTable).get()).length;

      await seeded.customStatement('DROP TABLE users');
      await seeded.customStatement('DROP TABLE settings');
      await seeded.customStatement('ALTER TABLE cash_sessions DROP COLUMN opened_by');
      await seeded.customStatement('ALTER TABLE cash_sessions DROP COLUMN closed_by');
      await seeded.customStatement('ALTER TABLE cash_movements DROP COLUMN created_by');
      await seeded.customStatement('ALTER TABLE customer_account_movements DROP COLUMN received_by');
      await seeded.customStatement('ALTER TABLE sales DROP COLUMN cashier_name');
      await seeded.customStatement('ALTER TABLE sales DROP COLUMN voided_by');
      await seeded.customStatement('PRAGMA user_version = 17');
      await seeded.close();

      final migrated = AppDatabase.forTesting(NativeDatabase(dbFile));
      addTearDown(migrated.close);
      expect((await migrated.select(migrated.productsTable).get()).length, productCount);
      final sales = await migrated.select(migrated.salesTable).get();
      expect(sales, hasLength(1));
      expect(sales.single.cashierName, isNull);
      expect(await migrated.select(migrated.usersTable).get(), isEmpty);

      // Ya se puede crear al administrador y entrar.
      final repo = DriftUserRepository(migrated, hasher: const PinHasher(iterations: 5));
      final admin = await repo.create(name: 'Dueña', role: UserRole.admin, pin: '1234');
      expect((await repo.authenticate(admin.id, '1234')).isAdmin, isTrue);
    });
  });
}
