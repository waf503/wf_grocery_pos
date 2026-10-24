import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:wf_grocery_pos/core/database/app_database.dart';
import 'package:wf_grocery_pos/features/cash/data/drift_cash_repository.dart';
import 'package:wf_grocery_pos/features/categories/data/category_seeder.dart';
import 'package:wf_grocery_pos/features/pos/widgets/quantity_dialog.dart';
import 'package:wf_grocery_pos/features/products/data/product_seeder.dart';
import 'package:wf_grocery_pos/features/sales/data/drift_sale_repository.dart';
import 'package:wf_grocery_pos/features/sales/data/sale_repository.dart';
import 'package:wf_grocery_pos/features/units/data/unit_seeder.dart';
import 'package:wf_grocery_pos/models/product.dart';
import 'package:wf_grocery_pos/models/sale.dart';
import 'package:wf_grocery_pos/state/pos_provider.dart';

Product _papa({double step = 0.5}) => Product(
      id: 'papa',
      name: 'Papa',
      categoryId: 'c',
      category: 'Verduras',
      unitId: 'u',
      unit: 'lb',
      allowsDecimals: true,
      quantityStep: step,
      priceCents: 49,
      costCents: 30,
      stock: 20,
      createdAt: DateTime(2025),
      updatedAt: DateTime(2025),
    );

Product _gaseosa() => Product(
      id: 'cola',
      name: 'Gaseosa',
      categoryId: 'c',
      category: 'Bebidas',
      unitId: 'u2',
      unit: 'pz',
      priceCents: 100,
      costCents: 60,
      stock: 20,
      createdAt: DateTime(2025),
      updatedAt: DateTime(2025),
    );

Future<AppDatabase> _seededDb([AppDatabase? db]) async {
  db ??= AppDatabase.forTesting(NativeDatabase.memory());
  final categoryIds = await seedCategoriesIfEmpty(db);
  final unitIds = await seedUnitsIfEmpty(db);
  await seedProductsIfEmpty(db, categoryIds, unitIds);
  return db;
}

void main() {
  group('carrito con productos por peso', () {
    test('un producto por libra se vende de media en media y la pieza de 1 en 1', () {
      final pos = PosProvider();
      pos.addProduct(_papa());
      expect(pos.cart.single.quantity, 0.5);

      pos.incrementQuantity('papa');
      expect(pos.cart.single.quantity, 1.0);
      pos.incrementQuantity('papa');
      expect(pos.cart.single.quantity, 1.5);
      pos.decrementQuantity('papa');
      expect(pos.cart.single.quantity, 1.0);

      pos.addProduct(_gaseosa());
      pos.incrementQuantity('cola');
      expect(pos.cart.last.quantity, 2.0);
      expect(pos.itemCount, 3.0);
    });

    test('bajar de la mínima media libra quita el renglón', () {
      final pos = PosProvider();
      pos.addProduct(_papa());
      pos.decrementQuantity('papa');
      expect(pos.isEmpty, isTrue);
    });

    test('se puede fijar una cantidad exacta y el subtotal redondea al centavo', () {
      final pos = PosProvider();
      pos.addProduct(_papa(), quantity: 1);
      pos.setQuantity('papa', 2.5);

      // 49 centavos x 2.5 lb = 122.5 -> 123, igual que lo que guarda la venta.
      expect(pos.cart.single.subtotalCents, 123);
      expect(
        SaleLine(
          productId: 'papa',
          productName: 'Papa',
          quantity: 2.5,
          unitPriceCents: 49,
          unitCostCents: 30,
        ).subtotalCents,
        pos.cart.single.subtotalCents,
      );
      expect(pos.totalCents, 123);

      pos.setQuantity('papa', 0);
      expect(pos.isEmpty, isTrue);
    });

    test('isMultipleOfStep acepta múltiplos y tolera el punto flotante', () {
      expect(isMultipleOfStep(1.5, 0.5), isTrue);
      expect(isMultipleOfStep(0.3, 0.5), isFalse);
      expect(isMultipleOfStep(0.75, 0.25), isTrue);
      expect(isMultipleOfStep(0.7, 0.1), isTrue); // 0.7 / 0.1 = 6.999999...
      expect(isMultipleOfStep(2, 1), isTrue);
    });
  });

  group('venta por peso en la base de datos', () {
    late AppDatabase db;

    setUp(() async => db = await _seededDb());
    tearDown(() => db.close());

    test('las unidades con decimales se siembran de media en media', () async {
      final units = await db.select(db.unitsTable).get();
      final byName = {for (final u in units) u.name: u.saleStep};
      expect(byName['Libra'], 0.5);
      expect(byName['Kilogramo'], 0.5);
      expect(byName['Pieza'], 1);
    });

    test('vender 2.5 lb descuenta 2.5 del stock; vender más de lo que hay falla sin guardar nada', () async {
      final categoryId = (await db.select(db.categoriesTable).get()).first.id;
      final libra = await (db.select(db.unitsTable)..where((u) => u.name.equals('Libra'))).getSingle();
      await db.into(db.productsTable).insert(
            ProductsTableCompanion.insert(
              id: const Value('papa'),
              name: 'Papa',
              categoryId: categoryId,
              unitId: libra.id,
              priceCents: 49,
              costCents: 30,
              stock: const Value(10),
            ),
          );
      final session = await DriftCashRepository(db).open(openingCents: 0);
      final sales = DriftSaleRepository(db);
      SaleLine line(double q) => SaleLine(
            productId: 'papa',
            productName: 'Papa',
            quantity: q,
            unitPriceCents: 49,
            unitCostCents: 30,
          );

      final sale = await sales.registerSale(
        sessionId: session.id,
        lines: [line(2.5)],
        paymentMethod: PaymentMethod.cash,
      );
      expect(sale.totalCents, 123);
      expect(sale.items.single.quantity, 2.5);
      var papa = await (db.select(db.productsTable)..where((r) => r.id.equals('papa'))).getSingle();
      expect(papa.stock, 7.5);

      await expectLater(
        sales.registerSale(sessionId: session.id, lines: [line(8)], paymentMethod: PaymentMethod.cash),
        throwsA(isA<InsufficientStockException>()),
      );
      papa = await (db.select(db.productsTable)..where((r) => r.id.equals('papa'))).getSingle();
      expect(papa.stock, 7.5);

      // Anular devuelve las libras al stock.
      await sales.voidSale(saleId: sale.id, reason: 'x', cashSessionId: session.id);
      papa = await (db.select(db.productsTable)..where((r) => r.id.equals('papa'))).getSingle();
      expect(papa.stock, 10);
    });
  });

  group('migración v12 → v13', () {
    late Directory tempDir;
    late File dbFile;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('wf_bulk_test');
      dbFile = File(p.join(tempDir.path, 'test.sqlite'));
    });

    tearDown(() => tempDir.delete(recursive: true));

    test('las unidades con decimales pasan a venderse de media en media', () async {
      final seeded = await _seededDb(AppDatabase.forTesting(NativeDatabase(dbFile)));
      await seeded.customStatement('ALTER TABLE units DROP COLUMN sale_step');
      await seeded.customStatement('DROP TABLE product_images');
      await seeded.customStatement('DROP TABLE catalog_items');
      await seeded.customStatement('ALTER TABLE products DROP COLUMN has_image');
      await seeded.customStatement('ALTER TABLE sales DROP COLUMN tendered_cents');
      await seeded.customStatement('ALTER TABLE sales DROP COLUMN change_cents');
      await seeded.customStatement('DROP TABLE product_combos');
      await seeded.customStatement('ALTER TABLE products DROP COLUMN base_product_id');
      await seeded.customStatement('ALTER TABLE products DROP COLUMN units_per_pack');
      await seeded.customStatement('ALTER TABLE sale_items DROP COLUMN stock_product_id');
      await seeded.customStatement('ALTER TABLE sale_items DROP COLUMN stock_quantity');
      await seeded.customStatement('DROP TABLE users');
      await seeded.customStatement('DROP TABLE settings');
      await seeded.customStatement('ALTER TABLE cash_sessions DROP COLUMN opened_by');
      await seeded.customStatement('ALTER TABLE cash_sessions DROP COLUMN closed_by');
      await seeded.customStatement('ALTER TABLE cash_movements DROP COLUMN created_by');
      await seeded.customStatement('ALTER TABLE customer_account_movements DROP COLUMN received_by');
      await seeded.customStatement('ALTER TABLE sales DROP COLUMN cashier_name');
      await seeded.customStatement('ALTER TABLE sales DROP COLUMN voided_by');
      await seeded.customStatement('PRAGMA user_version = 12');
      await seeded.close();

      final migrated = AppDatabase.forTesting(NativeDatabase(dbFile));
      addTearDown(migrated.close);
      final units = await migrated.select(migrated.unitsTable).get();
      final byName = {for (final u in units) u.name: u.saleStep};
      expect(byName['Libra'], 0.5);
      expect(byName['Pieza'], 1);
    });
  });
}
