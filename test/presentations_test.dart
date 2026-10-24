import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:wf_grocery_pos/core/database/app_database.dart';
import 'package:wf_grocery_pos/core/pricing.dart';
import 'package:wf_grocery_pos/features/cash/data/drift_cash_repository.dart';
import 'package:wf_grocery_pos/features/categories/data/category_seeder.dart';
import 'package:wf_grocery_pos/features/products/data/drift_product_repository.dart';
import 'package:wf_grocery_pos/features/sales/data/drift_sale_repository.dart';
import 'package:wf_grocery_pos/features/sales/data/sale_repository.dart';
import 'package:wf_grocery_pos/features/units/data/unit_seeder.dart';
import 'package:wf_grocery_pos/models/cart_item.dart';
import 'package:wf_grocery_pos/models/product.dart';
import 'package:wf_grocery_pos/models/product_combo.dart';
import 'package:wf_grocery_pos/models/sale.dart';

const _unit = 10; // un cigarro suelto: 10 centavos
const _pack = 175; // una cajetilla: $1.75
const _carton = 3000; // el paquete de 20 cajetillas: $30.00

void main() {
  group('combos: precio por cantidad', () {
    const twoFor25 = [ProductCombo(quantity: 2, priceCents: 25)];

    test('2 bolsas de agua a 15¢ por 25¢: cada par se cobra como combo, el resto suelto', () {
      int total(double q) => comboSubtotalCents(quantity: q, unitPriceCents: 15, combos: twoFor25);
      expect(total(1), 15); // sin combo
      expect(total(2), 25); // el combo
      expect(total(3), 40); // combo + 1 suelta
      expect(total(4), 50); // dos combos
      expect(total(5), 65);
      expect(comboSavingsCents(quantity: 4, unitPriceCents: 15, combos: twoFor25), 10); // 60 - 50
    });

    test('con varios combos elige siempre la forma más barata (aunque no sea la más grande)', () {
      const combos = [
        ProductCombo(quantity: 2, priceCents: 25),
        ProductCombo(quantity: 5, priceCents: 60),
      ];
      int total(double q) => comboSubtotalCents(quantity: q, unitPriceCents: 15, combos: combos);
      expect(total(5), 60); // el de 5 gana a 2+2+1 (65)
      expect(total(7), 85); // 5 + 2 = 60 + 25
      expect(total(10), 120); // 5 + 5
    });

    test('un combo que no conviene nunca se usa', () {
      const bad = [ProductCombo(quantity: 2, priceCents: 40)]; // más caro que 2 sueltas (30)
      expect(comboSubtotalCents(quantity: 2, unitPriceCents: 15, combos: bad), 30);
    });

    test('sin combos o con cantidades por peso es simplemente cantidad × precio', () {
      expect(comboSubtotalCents(quantity: 3, unitPriceCents: 15, combos: const []), 45);
      expect(comboSubtotalCents(quantity: 2.5, unitPriceCents: 49, combos: twoFor25), 123);
    });

    test('el renglón del carrito aplica los combos del producto', () {
      final agua = Product(
        id: 'agua',
        name: 'Bolsa de agua',
        categoryId: 'c',
        category: 'Bebidas',
        unitId: 'u',
        unit: 'u',
        priceCents: 15,
        costCents: 8,
        stock: 100,
        createdAt: DateTime(2025),
        updatedAt: DateTime(2025),
        combos: twoFor25,
      );
      final item = CartItem(product: agua, quantity: 5);
      expect(item.subtotalCents, 65);
      expect(item.savingsCents, 10); // 75 - 65
    });
  });

  group('presentaciones: un solo pool de existencias', () {
    late AppDatabase db;
    late DriftProductRepository products;
    late DriftSaleRepository sales;
    late DriftCashRepository cash;
    late String baseId;
    late String sessionId;

    setUp(() async {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      final categories = await seedCategoriesIfEmpty(db);
      final units = await seedUnitsIfEmpty(db);
      products = DriftProductRepository(db);
      sales = DriftSaleRepository(db);
      cash = DriftCashRepository(db);

      // 20 paquetes × 20 cajetillas × 20 unidades = 8,000 cigarros.
      baseId = await products.add(
        ProductsTableCompanion.insert(
          name: 'Cigarro suelto',
          categoryId: categories.values.first,
          unitId: units['Pieza']!,
          priceCents: _unit,
          costCents: 6,
          stock: const Value(8000),
          minStock: const Value(400),
        ),
      );
      await products.savePresentations(baseId, const [
        PresentationDraft(name: 'Cajetilla de 20 cigarros', unitsPerPack: 20, priceCents: _pack, barcode: '7501000000001'),
        PresentationDraft(name: 'Paquete de 20 cajetillas', unitsPerPack: 400, priceCents: _carton),
      ]);
      sessionId = (await cash.open(openingCents: 0)).id;
    });

    tearDown(() => db.close());

    Future<Product> byName(String name) async =>
        (await products.watchAll().first).firstWhere((p) => p.name == name);

    SaleLine line(Product p, double quantity) => SaleLine(
          productId: p.id,
          productName: p.name,
          quantity: quantity,
          unitPriceCents: p.priceCents,
          unitCostCents: p.costCents,
          fixedSubtotalCents: CartItem(product: p, quantity: quantity).subtotalCents,
        );

    Future<double> poolStock() async => (await byName('Cigarro suelto')).stock;

    test('cada presentación sale como un producto aparte, con sus existencias derivadas del base', () async {
      final all = await products.watchAll().first;
      expect(all, hasLength(3));

      final unit = all.firstWhere((p) => p.name == 'Cigarro suelto');
      final box = all.firstWhere((p) => p.name == 'Cajetilla de 20 cigarros');
      final carton = all.firstWhere((p) => p.name == 'Paquete de 20 cajetillas');

      expect(unit.isPresentation, isFalse);
      expect(unit.stock, 8000);
      expect(box.isPresentation, isTrue);
      expect(box.baseProductId, baseId);
      expect(box.unitsPerPack, 20);
      expect(box.stock, 400); // 8000 / 20
      expect(carton.stock, 20); // 8000 / 400
      expect(box.priceCents, _pack);
      expect(box.barcode, '7501000000001');
      expect(box.costCents, 120); // 20 × 6¢: costo calculado del base
      expect(box.minStock, 20); // el mínimo también se deriva (400 / 20)
      expect(box.poolId, baseId);
      expect(box.poolFactor, 20);
    });

    test('las existencias salen redondeadas hacia abajo: solo cuentan presentaciones completas', () async {
      await (db.update(db.productsTable)..where((r) => r.id.equals(baseId)))
          .write(const ProductsTableCompanion(stock: Value(125))); // 6 cajetillas y 5 sueltos
      expect((await byName('Cajetilla de 20 cigarros')).stock, 6);
      expect((await byName('Paquete de 20 cajetillas')).stock, 0);
    });

    test('vender una cajetilla descuenta 20 unidades del pool que comparten todas', () async {
      final box = await byName('Cajetilla de 20 cigarros');
      final sale = await sales.registerSale(
        sessionId: sessionId,
        lines: [line(box, 2)],
        paymentMethod: PaymentMethod.cash,
      );
      expect(sale.totalCents, 2 * _pack);
      expect(await poolStock(), 8000 - 40);
      // Y lo ve cualquier presentación: 7,960 / 20 = 398 cajetillas.
      expect((await byName('Cajetilla de 20 cigarros')).stock, 398);

      final item = (await db.select(db.saleItemsTable).get()).single;
      expect(item.stockProductId, baseId);
      expect(item.stockQuantity, 40);
      expect(item.quantity, 2); // lo vendido, en cajetillas
    });

    test('unidades, cajetillas y paquetes en la misma venta suman contra el mismo pool', () async {
      final unit = await byName('Cigarro suelto');
      final box = await byName('Cajetilla de 20 cigarros');
      final carton = await byName('Paquete de 20 cajetillas');
      await sales.registerSale(
        sessionId: sessionId,
        lines: [line(unit, 3), line(box, 1), line(carton, 1)],
        paymentMethod: PaymentMethod.cash,
      );
      expect(await poolStock(), 8000 - 3 - 20 - 400);
    });

    test('si entre todas las presentaciones piden más de lo que hay, falla sin guardar nada', () async {
      await (db.update(db.productsTable)..where((r) => r.id.equals(baseId)))
          .write(const ProductsTableCompanion(stock: Value(30)));
      final unit = await byName('Cigarro suelto');
      final box = await byName('Cajetilla de 20 cigarros');

      // Solo hay 30: una cajetilla (20) sí, pero con 15 sueltas ya son 35.
      await expectLater(
        sales.registerSale(
          sessionId: sessionId,
          lines: [line(box, 1), line(unit, 15)],
          paymentMethod: PaymentMethod.cash,
        ),
        throwsA(isA<InsufficientStockException>()),
      );
      expect(await poolStock(), 30);
      expect(await sales.watchBetween(DateTime(2000)).first, isEmpty);
    });

    test('el aviso de existencias insuficientes habla en la presentación que se quería vender', () async {
      await (db.update(db.productsTable)..where((r) => r.id.equals(baseId)))
          .write(const ProductsTableCompanion(stock: Value(50))); // 2 cajetillas y 10 sueltos
      final box = await byName('Cajetilla de 20 cigarros');
      await expectLater(
        sales.registerSale(
          sessionId: sessionId,
          lines: [line(box, 3)],
          paymentMethod: PaymentMethod.cash,
        ),
        throwsA(isA<InsufficientStockException>().having((e) => e.available, 'disponibles', 2)),
      );
    });

    test('anular la venta devuelve al pool exactamente lo que se descontó', () async {
      final unit = await byName('Cigarro suelto');
      final carton = await byName('Paquete de 20 cajetillas');
      final sale = await sales.registerSale(
        sessionId: sessionId,
        lines: [line(unit, 5), line(carton, 2)],
        paymentMethod: PaymentMethod.cash,
      );
      expect(await poolStock(), 8000 - 5 - 800);

      await sales.voidSale(saleId: sale.id, reason: 'x', cashSessionId: sessionId);
      expect(await poolStock(), 8000);
    });

    test('anular devuelve lo correcto aunque la presentación se haya borrado después', () async {
      final box = await byName('Cajetilla de 20 cigarros');
      final sale = await sales.registerSale(
        sessionId: sessionId,
        lines: [line(box, 1)],
        paymentMethod: PaymentMethod.cash,
      );
      await products.savePresentations(baseId, const []); // se borran las presentaciones
      await sales.voidSale(saleId: sale.id, reason: 'x', cashSessionId: sessionId);
      expect(await poolStock(), 8000); // se devolvieron las 20 unidades al base
    });

    test('las ventas anteriores a las presentaciones se anulan como siempre', () async {
      final unit = await byName('Cigarro suelto');
      final sale = await sales.registerSale(
        sessionId: sessionId,
        lines: [line(unit, 4)],
        paymentMethod: PaymentMethod.cash,
      );
      // Se simula una venta antigua: sin los datos nuevos del renglón.
      await db.customStatement('UPDATE sale_items SET stock_product_id = NULL, stock_quantity = NULL');
      await sales.voidSale(saleId: sale.id, reason: 'x', cashSessionId: sessionId);
      expect(await poolStock(), 8000);
    });

    test('guardar de nuevo las presentaciones actualiza las existentes, crea nuevas y borra las que faltan', () async {
      final box = await byName('Cajetilla de 20 cigarros');
      await products.savePresentations(baseId, [
        PresentationDraft(
          id: box.id,
          name: 'Cajetilla (renombrada)',
          unitsPerPack: 20,
          priceCents: 180,
          costCents: 100,
        ),
        const PresentationDraft(name: 'Media cajetilla', unitsPerPack: 10, priceCents: 90),
      ]);

      final all = await products.watchAll().first;
      expect(all.map((p) => p.name).toSet(), {'Cigarro suelto', 'Cajetilla (renombrada)', 'Media cajetilla'});
      final renamed = all.firstWhere((p) => p.name == 'Cajetilla (renombrada)');
      expect(renamed.id, box.id); // misma presentación, no un duplicado
      expect(renamed.priceCents, 180);
      expect(renamed.costCents, 100);
      expect(all.firstWhere((p) => p.name == 'Media cajetilla').stock, 800);
    });

    test('borrar el producto base borra también sus presentaciones y combos', () async {
      final box = await byName('Cajetilla de 20 cigarros');
      await products.setCombos(box.id, const [ProductCombo(quantity: 2, priceCents: 330)]);

      await products.delete(baseId);
      expect(await products.watchAll().first, isEmpty);
      expect(await db.select(db.productCombosTable).get(), isEmpty);
    });

    test('borrar solo una presentación no toca el producto base ni sus existencias', () async {
      final box = await byName('Cajetilla de 20 cigarros');
      await products.delete(box.id);
      final names = (await products.watchAll().first).map((p) => p.name).toSet();
      expect(names, {'Cigarro suelto', 'Paquete de 20 cajetillas'});
      expect(await poolStock(), 8000);
    });

    test('los combos se guardan por producto y se cargan junto con él', () async {
      final unit = await byName('Cigarro suelto');
      await products.setCombos(unit.id, const [
        ProductCombo(quantity: 5, priceCents: 40),
        ProductCombo(quantity: 2, priceCents: 18),
      ]);
      final loaded = await byName('Cigarro suelto');
      expect(loaded.combos, const [
        ProductCombo(quantity: 2, priceCents: 18),
        ProductCombo(quantity: 5, priceCents: 40),
      ]); // ordenados por cantidad

      await products.setCombos(unit.id, const []);
      expect((await byName('Cigarro suelto')).combos, isEmpty);
    });

    test('una venta con combo cobra el precio del combo y lo guarda', () async {
      final unit = await byName('Cigarro suelto');
      await products.setCombos(unit.id, const [ProductCombo(quantity: 3, priceCents: 25)]);
      final withCombo = await byName('Cigarro suelto');

      final sale = await sales.registerSale(
        sessionId: sessionId,
        lines: [line(withCombo, 4)], // 3 por 25¢ + 1 suelto de 10¢
        paymentMethod: PaymentMethod.cash,
      );
      expect(sale.totalCents, 35);
      expect(sale.items.single.subtotalCents, 35);
      expect(sale.items.single.unitPriceCents, _unit); // el precio de lista queda como foto
      expect(await poolStock(), 7996);
    });
  });

  group('migración v16 → v17', () {
    late Directory tempDir;
    late File dbFile;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('wf_pack_test');
      dbFile = File(p.join(tempDir.path, 'test.sqlite'));
    });

    tearDown(() => tempDir.delete(recursive: true));

    test('los productos y ventas existentes se conservan y se pueden usar presentaciones', () async {
      final seeded = AppDatabase.forTesting(NativeDatabase(dbFile));
      final categories = await seedCategoriesIfEmpty(seeded);
      final units = await seedUnitsIfEmpty(seeded);
      final repo = DriftProductRepository(seeded);
      final id = await repo.add(
        ProductsTableCompanion.insert(
          name: 'Cigarro',
          categoryId: categories.values.first,
          unitId: units['Pieza']!,
          priceCents: 10,
          costCents: 6,
          stock: const Value(100),
        ),
      );
      final session = await DriftCashRepository(seeded).open(openingCents: 0);
      await DriftSaleRepository(seeded).registerSale(
        sessionId: session.id,
        lines: [SaleLine(productId: id, productName: 'Cigarro', quantity: 2, unitPriceCents: 10, unitCostCents: 6)],
        paymentMethod: PaymentMethod.cash,
      );
      await seeded.customStatement('DROP TABLE product_combos');
      await seeded.customStatement('ALTER TABLE products DROP COLUMN base_product_id');
      await seeded.customStatement('ALTER TABLE products DROP COLUMN units_per_pack');
      await seeded.customStatement('ALTER TABLE sale_items DROP COLUMN stock_product_id');
      await seeded.customStatement('ALTER TABLE sale_items DROP COLUMN stock_quantity');
      await seeded.customStatement('PRAGMA user_version = 16');
      await seeded.close();

      final migrated = AppDatabase.forTesting(NativeDatabase(dbFile));
      addTearDown(migrated.close);
      final migratedRepo = DriftProductRepository(migrated);
      final cigarro = (await migratedRepo.watchAll().first).single;
      expect(cigarro.stock, 98);
      expect(cigarro.isPresentation, isFalse);
      expect(cigarro.unitsPerPack, 1);
      expect(cigarro.combos, isEmpty);

      // La venta anterior sigue ahí (sin datos de pool) y se puede anular.
      final history = await DriftSaleRepository(migrated).watchBetween(DateTime(2000)).first;
      expect(history.single.items.single.productName, 'Cigarro');
      await DriftSaleRepository(migrated).voidSale(
        saleId: history.single.id,
        reason: 'x',
        cashSessionId: session.id,
      );
      expect((await migratedRepo.watchAll().first).single.stock, 100);

      // Y ya se pueden crear presentaciones y combos.
      await migratedRepo.savePresentations(cigarro.id, const [
        PresentationDraft(name: 'Cajetilla', unitsPerPack: 20, priceCents: 175),
      ]);
      expect((await migratedRepo.watchAll().first).firstWhere((p) => p.name == 'Cajetilla').stock, 5);
    });
  });
}
