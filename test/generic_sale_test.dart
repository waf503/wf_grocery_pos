import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:wf_grocery_pos/core/database/app_database.dart';
import 'package:wf_grocery_pos/features/cash/data/drift_cash_repository.dart';
import 'package:wf_grocery_pos/features/categories/data/category_seeder.dart';
import 'package:wf_grocery_pos/features/products/data/product_seeder.dart';
import 'package:wf_grocery_pos/features/sales/data/drift_sale_repository.dart';
import 'package:wf_grocery_pos/features/sales/data/sale_repository.dart';
import 'package:wf_grocery_pos/features/units/data/unit_seeder.dart';
import 'package:wf_grocery_pos/models/sale.dart';
import 'package:wf_grocery_pos/state/pos_provider.dart';

void main() {
  test('el carrito acepta ventas genéricas como renglones independientes', () {
    final pos = PosProvider();
    pos.addGeneric(name: 'Varios', priceCents: 250);
    pos.addGeneric(name: 'Varios', priceCents: 100, quantity: 3);

    expect(pos.cart, hasLength(2)); // mismo nombre, renglones distintos
    expect(pos.cart.every((i) => i.product.isGeneric), isTrue);
    expect(pos.totalCents, 250 + 300);

    pos.incrementQuantity(pos.cart.first.product.id);
    expect(pos.totalCents, 500 + 300);
  });

  group('venta genérica en la base de datos', () {
    late AppDatabase db;
    late DriftCashRepository cash;
    late DriftSaleRepository sales;

    setUp(() async {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      final categoryIds = await seedCategoriesIfEmpty(db);
      final unitIds = await seedUnitsIfEmpty(db);
      await seedProductsIfEmpty(db, categoryIds, unitIds);
      cash = DriftCashRepository(db);
      sales = DriftSaleRepository(db);
    });

    tearDown(() => db.close());

    SaleLine generic(String name, int priceCents, double quantity) => SaleLine(
          productId: null,
          productName: name,
          quantity: quantity,
          unitPriceCents: priceCents,
          unitCostCents: 0,
        );

    test('se registra sin tocar existencias y mueve la caja si es efectivo', () async {
      final session = await cash.open(openingCents: 1000);
      final stockBefore = (await db.select(db.productsTable).get()).fold<double>(0, (s, p) => s + p.stock);

      final sale = await sales.registerSale(
        sessionId: session.id,
        lines: [generic('Varios', 250, 2)],
        paymentMethod: PaymentMethod.cash,
      );

      expect(sale.totalCents, 500);
      expect(sale.items.single.productId, isNull);
      expect(sale.items.single.productName, 'Varios');
      final stockAfter = (await db.select(db.productsTable).get()).fold<double>(0, (s, p) => s + p.stock);
      expect(stockAfter, stockBefore);
      expect((await cash.watchCurrent().first)!.expectedCents, 1500);
    });

    test('se puede mezclar con productos del inventario y anular sin error', () async {
      final session = await cash.open(openingCents: 0);
      final cola = await (db.select(db.productsTable)..where((r) => r.name.equals('Coca-Cola Lata 355ml'))).getSingle();

      final sale = await sales.registerSale(
        sessionId: session.id,
        lines: [
          SaleLine(
            productId: cola.id,
            productName: cola.name,
            quantity: 2,
            unitPriceCents: cola.priceCents,
            unitCostCents: cola.costCents,
          ),
          generic('Bolsa', 100, 1),
        ],
        paymentMethod: PaymentMethod.cash,
      );
      expect(sale.items, hasLength(2));
      expect((await (db.select(db.productsTable)..where((r) => r.id.equals(cola.id))).getSingle()).stock, cola.stock - 2);

      await sales.voidSale(saleId: sale.id, reason: 'x', cashSessionId: session.id);
      expect((await (db.select(db.productsTable)..where((r) => r.id.equals(cola.id))).getSingle()).stock, cola.stock);
      expect((await cash.watchCurrent().first)!.expectedCents, 0);
    });
  });
}
