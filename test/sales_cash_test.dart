import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:wf_grocery_pos/core/database/app_database.dart';
import 'package:wf_grocery_pos/core/format/formatters.dart';
import 'package:wf_grocery_pos/core/money.dart';
import 'package:wf_grocery_pos/features/cash/data/cash_repository.dart';
import 'package:wf_grocery_pos/features/cash/data/drift_cash_repository.dart';
import 'package:wf_grocery_pos/features/categories/data/category_seeder.dart';
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

/// Devuelve la tabla `products` al formato de antes de la v9: precio y costo
/// como decimales (REAL) en vez de centavos, para simular una base vieja.
Future<void> _revertProductsToDecimalPrices(AppDatabase db) async {
  await db.customStatement('''
    CREATE TABLE products_old AS
    SELECT id, name, category_id, unit_id,
           CAST(price_cents AS REAL) / 100 AS price,
           CAST(cost_cents AS REAL) / 100 AS cost,
           stock, min_stock, barcode, tags, active, created_at
    FROM products
  ''');
  await db.customStatement('DROP TABLE products');
  await db.customStatement('ALTER TABLE products_old RENAME TO products');
}

void main() {
  group('dinero en centavos', () {
    test('convierte sin el error de punto flotante', () {
      expect(toCents(0.1 + 0.2), 30);
      expect(toCents(19.99), 1999);
      expect(toCents(32.5), 3250);
      expect(fromCents(1999), 19.99);
    });

    test('formatQuantity quita el .0 sobrante', () {
      expect(formatQuantity(3), '3');
      expect(formatQuantity(1.5), '1.5');
      expect(formatQuantity(0.25), '0.25');
    });
  });

  group('venta transaccional', () {
    late AppDatabase db;
    late DriftCashRepository cash;
    late DriftSaleRepository sales;
    late CashSession session;

    setUp(() async {
      db = await _seededDb();
      cash = DriftCashRepository(db);
      sales = DriftSaleRepository(db);
      session = await cash.open(openingCents: toCents(100));
    });

    tearDown(() => db.close());

    test('descuenta existencias, numera consecutivo y mueve la caja si es efectivo', () async {
      final cola = await _product(db, 'Coca-Cola Lata 355ml'); // 12.00, stock 60
      final arroz = await _product(db, 'Arroz Morelos 1kg'); // 32.50, stock 40

      final first = await sales.registerSale(
        sessionId: session.id,
        lines: [_line(cola, 2), _line(arroz, 1)],
        paymentMethod: PaymentMethod.cash,
      );
      final second = await sales.registerSale(
        sessionId: session.id,
        lines: [_line(cola, 1)],
        paymentMethod: PaymentMethod.cash,
      );

      expect(first.number, 1);
      expect(second.number, 2);
      expect(first.receiptNumber, 'V-000001');
      expect(first.totalCents, 5650); // 2 x 12.00 + 32.50
      expect(first.items.length, 2);

      expect((await _product(db, 'Coca-Cola Lata 355ml')).stock, 57);
      expect((await _product(db, 'Arroz Morelos 1kg')).stock, 39);

      final current = await cash.watchCurrent().first;
      expect(current!.salesCents, 5650 + 1200);
      expect(current.expectedCents, 10000 + 5650 + 1200);
    });

    test('las ventas con tarjeta o fiado no mueven el efectivo de la caja', () async {
      final cola = await _product(db, 'Coca-Cola Lata 355ml');
      await sales.registerSale(
        sessionId: session.id,
        lines: [_line(cola, 1)],
        paymentMethod: PaymentMethod.card,
      );
      await sales.registerSale(
        sessionId: session.id,
        lines: [_line(cola, 1)],
        paymentMethod: PaymentMethod.credit,
        customerId: 'c2',
        customerName: 'Doña Carmen Ruiz',
      );

      final current = await cash.watchCurrent().first;
      expect(current!.movements, isEmpty);
      expect(current.expectedCents, 10000);
      expect((await _product(db, 'Coca-Cola Lata 355ml')).stock, 58); // el stock sí baja
    });

    test('sin existencias suficientes no se guarda NADA (rollback completo)', () async {
      final cola = await _product(db, 'Coca-Cola Lata 355ml'); // stock 60
      final aceite = await _product(db, 'Aceite Capullo 1L'); // stock 3

      await expectLater(
        sales.registerSale(
          sessionId: session.id,
          lines: [_line(cola, 5), _line(aceite, 4)], // el segundo no alcanza
          paymentMethod: PaymentMethod.cash,
        ),
        throwsA(isA<InsufficientStockException>()),
      );

      expect(await db.select(db.salesTable).get(), isEmpty);
      expect(await db.select(db.saleItemsTable).get(), isEmpty);
      expect(await db.select(db.cashMovementsTable).get(), isEmpty);
      expect((await _product(db, 'Coca-Cola Lata 355ml')).stock, 60);
      expect((await _product(db, 'Aceite Capullo 1L')).stock, 3);
    });

    test('un mismo producto repetido en la venta se valida por el total', () async {
      final aceite = await _product(db, 'Aceite Capullo 1L'); // stock 3
      await expectLater(
        sales.registerSale(
          sessionId: session.id,
          lines: [_line(aceite, 2), _line(aceite, 2)],
          paymentMethod: PaymentMethod.cash,
        ),
        throwsA(isA<InsufficientStockException>()),
      );
    });

    test('no se vende con la caja cerrada', () async {
      final cola = await _product(db, 'Coca-Cola Lata 355ml');
      await cash.close(sessionId: session.id, countedCents: 10000);

      await expectLater(
        sales.registerSale(
          sessionId: session.id,
          lines: [_line(cola, 1)],
          paymentMethod: PaymentMethod.cash,
        ),
        throwsA(isA<CashSessionClosedException>()),
      );
      expect((await _product(db, 'Coca-Cola Lata 355ml')).stock, 60);
    });

    test('la venta conserva la foto del precio aunque el producto cambie o se borre', () async {
      final cola = await _product(db, 'Coca-Cola Lata 355ml');
      final sale = await sales.registerSale(
        sessionId: session.id,
        lines: [_line(cola, 2)],
        paymentMethod: PaymentMethod.cash,
      );

      await (db.delete(db.productsTable)..where((row) => row.id.equals(cola.id))).go();

      final history = await sales.watchSince(DateTime(2000)).first;
      final saved = history.single;
      expect(saved.id, sale.id);
      expect(saved.items.single.productName, 'Coca-Cola Lata 355ml');
      expect(saved.items.single.unitPriceCents, 1200);
      expect(saved.items.single.unitCostCents, 800);
    });

    test('ingresos y retiros ajustan el monto esperado', () async {
      await cash.addMovement(
        sessionId: session.id,
        type: CashMovementType.deposit,
        amountCents: 2500,
        note: 'Cambio',
      );
      await cash.addMovement(
        sessionId: session.id,
        type: CashMovementType.withdrawal,
        amountCents: 1000,
        note: 'Pago proveedor',
      );
      final current = await cash.watchCurrent().first;
      expect(current!.expectedCents, 10000 + 2500 - 1000);
    });

    test('solo puede haber una caja abierta', () async {
      await expectLater(cash.open(openingCents: 0), throwsA(isA<CashSessionAlreadyOpenException>()));
    });
  });

  group('persistencia', () {
    late Directory tempDir;
    late File dbFile;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('wf_sales_cash_test');
      dbFile = File(p.join(tempDir.path, 'test.sqlite'));
    });

    tearDown(() => tempDir.delete(recursive: true));

    test('la caja abierta y sus ventas sobreviven a cerrar y reabrir la app', () async {
      final first = await _seededDb(AppDatabase.forTesting(NativeDatabase(dbFile)));
      final cola = await _product(first, 'Coca-Cola Lata 355ml');
      final session = await DriftCashRepository(first).open(openingCents: 5000);
      await DriftSaleRepository(first).registerSale(
        sessionId: session.id,
        lines: [_line(cola, 3)],
        paymentMethod: PaymentMethod.cash,
      );
      await first.close();

      final second = AppDatabase.forTesting(NativeDatabase(dbFile));
      addTearDown(second.close);
      final current = await DriftCashRepository(second).watchCurrent().first;
      final history = await DriftSaleRepository(second).watchSince(DateTime(2000)).first;

      expect(current, isNotNull);
      expect(current!.id, session.id);
      expect(current.expectedCents, 5000 + 3600);
      expect(history.single.number, 1);
      expect((await _product(second, 'Coca-Cola Lata 355ml')).stock, 57);
    });

    test('migrar de la v7 a la v8 conserva el inventario y crea las tablas de ventas', () async {
      // 1. Una base "ya existente" con productos.
      final seeded = await _seededDb(AppDatabase.forTesting(NativeDatabase(dbFile)));
      final productCount = (await seeded.select(seeded.productsTable).get()).length;

      // 2. La devolvemos al estado de la v7: sin tablas de ventas/caja.
      await _revertProductsToDecimalPrices(seeded);
      for (final table in ['cash_movements', 'sale_items', 'sales', 'cash_sessions']) {
        await seeded.customStatement('DROP TABLE $table');
      }
      await seeded.customStatement('PRAGMA user_version = 7');
      await seeded.close();

      // 3. Al abrirla con el código actual se ejecuta la migración.
      final migrated = AppDatabase.forTesting(NativeDatabase(dbFile));
      addTearDown(migrated.close);
      final products = await migrated.select(migrated.productsTable).get();
      expect(products.length, productCount);

      final session = await DriftCashRepository(migrated).open(openingCents: 1000);
      final cola = await _product(migrated, 'Coca-Cola Lata 355ml');
      final sale = await DriftSaleRepository(migrated).registerSale(
        sessionId: session.id,
        lines: [_line(cola, 1)],
        paymentMethod: PaymentMethod.cash,
      );
      expect(sale.number, 1);
    });

    test('migrar de la v8 a la v9 convierte precio y costo de decimales a centavos', () async {
      // 1. Una base v8: la tabla de productos con price/cost decimales (REAL).
      final seeded = await _seededDb(AppDatabase.forTesting(NativeDatabase(dbFile)));
      final count = (await seeded.select(seeded.productsTable).get()).length;
      await _revertProductsToDecimalPrices(seeded);
      // Un precio con el clásico error de punto flotante: 19.99 * 100 = 1998.9999...
      await seeded.customStatement(
        "UPDATE products SET price = 19.99, cost = 12.5 WHERE name = 'Bolillo'",
      );
      await seeded.customStatement('PRAGMA user_version = 8');
      await seeded.close();

      // 2. Al abrirla con el código actual se ejecuta la migración.
      final migrated = AppDatabase.forTesting(NativeDatabase(dbFile));
      addTearDown(migrated.close);
      final products = await migrated.select(migrated.productsTable).get();
      expect(products.length, count);

      final bolillo = await _product(migrated, 'Bolillo');
      expect(bolillo.priceCents, 1999);
      expect(bolillo.costCents, 1250);
      final arroz = await _product(migrated, 'Arroz Morelos 1kg');
      expect(arroz.priceCents, 3250);
      expect(arroz.stock, 40);
    });
  });
}
