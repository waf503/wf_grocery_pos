import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';

import 'package:wf_grocery_pos/core/database/app_database.dart';
import 'package:wf_grocery_pos/features/cash/data/drift_cash_repository.dart';
import 'package:wf_grocery_pos/features/categories/data/category_seeder.dart';
import 'package:wf_grocery_pos/features/categories/data/drift_category_repository.dart';
import 'package:wf_grocery_pos/features/inventory/inventory_screen.dart';
import 'package:wf_grocery_pos/features/products/data/drift_product_repository.dart';
import 'package:wf_grocery_pos/features/sales/data/drift_sale_repository.dart';
import 'package:wf_grocery_pos/features/sales/data/sale_repository.dart';
import 'package:wf_grocery_pos/features/units/data/drift_unit_repository.dart';
import 'package:wf_grocery_pos/features/units/data/unit_seeder.dart';
import 'package:wf_grocery_pos/models/product.dart';
import 'package:wf_grocery_pos/models/product_combo.dart';
import 'package:wf_grocery_pos/models/sale.dart';
import 'package:wf_grocery_pos/state/category_provider.dart';
import 'package:wf_grocery_pos/state/inventory_provider.dart';
import 'package:wf_grocery_pos/state/unit_provider.dart';

void main() {
  setUpAll(() => initializeDateFormatting('es_MX'));

  group('el base es el PAQUETE y el cigarro suelto viene dentro (relación inversa)', () {
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

      // El producto se creó como "Paquete" con 10 paquetes en existencia (costo $24).
      baseId = await products.add(
        ProductsTableCompanion.insert(
          name: 'Paquete de 200 cigarros',
          categoryId: categories.values.first,
          unitId: units['Paquete']!,
          priceCents: 3000,
          costCents: 2400,
          stock: const Value(10),
          minStock: const Value(2),
        ),
      );
      sessionId = (await cash.open(openingCents: 0)).id;
    });

    tearDown(() => db.close());

    /// El usuario agrega "Cigarro suelto: el paquete trae 200 de éste".
    Future<void> addLooseCigarette({int stockScale = 200}) {
      return products.savePresentations(
        baseId,
        const [PresentationDraft(name: 'Cigarro suelto', unitsPerPack: 1, priceCents: 15)],
        baseUnitsPerPack: 200,
        stockScale: stockScale.toDouble(),
      );
    }

    Future<Product> byName(String name) async =>
        (await products.watchAll().first).firstWhere((p) => p.name == name);

    SaleLine line(Product p, double quantity) => SaleLine(
          productId: p.id,
          productName: p.name,
          quantity: quantity,
          unitPriceCents: p.priceCents,
          unitCostCents: p.costCents,
        );

    Future<double> pool() async => (await db.select(db.productsTable).get()).firstWhere((r) => r.id == baseId).stock;

    test('las existencias que estaban en paquetes pasan a cigarros y todo sigue cuadrando', () async {
      await addLooseCigarette();

      expect(await pool(), 2000); // 10 paquetes = 2,000 cigarros
      final pack = await byName('Paquete de 200 cigarros');
      final cigar = await byName('Cigarro suelto');
      expect(pack.unitsPerPack, 200);
      expect(pack.isPresentation, isFalse); // sigue siendo el producto base
      expect(pack.stock, 10); // lo que se ve en paquetes
      expect(pack.poolUnits, 2000);
      expect(cigar.isPresentation, isTrue);
      expect(cigar.unitsPerPack, 1);
      expect(cigar.stock, 2000); // lo que se ve en cigarros
      expect(pack.minStock, 2); // el mínimo (2 paquetes) también se convierte
      expect(cigar.minStock, 400);
    });

    test(r'el costo del cigarro sale del costo del paquete: $24 ÷ 200 = 12¢', () async {
      await addLooseCigarette();
      expect((await byName('Cigarro suelto')).costCents, 12);
      expect((await byName('Paquete de 200 cigarros')).costCents, 2400); // no cambia
    });

    test('vender cigarros sueltos y paquetes descuenta del mismo pool', () async {
      await addLooseCigarette();
      final pack = await byName('Paquete de 200 cigarros');
      final cigar = await byName('Cigarro suelto');

      await sales.registerSale(
        sessionId: sessionId,
        lines: [line(cigar, 3), line(pack, 2)],
        paymentMethod: PaymentMethod.cash,
      );
      expect(await pool(), 2000 - 3 - 400);
      // 1,597 cigarros: 7 paquetes completos y 197 sueltos sobrando.
      expect((await byName('Paquete de 200 cigarros')).stock, 7);
      expect((await byName('Cigarro suelto')).stock, 1597);
    });

    test('un paquete solo se puede vender si quedan 200 cigarros completos', () async {
      await addLooseCigarette();
      await (db.update(db.productsTable)..where((r) => r.id.equals(baseId)))
          .write(const ProductsTableCompanion(stock: Value(150)));
      final pack = await byName('Paquete de 200 cigarros');
      expect(pack.stock, 0);

      await expectLater(
        sales.registerSale(sessionId: sessionId, lines: [line(pack, 1)], paymentMethod: PaymentMethod.cash),
        throwsA(isA<InsufficientStockException>().having((e) => e.available, 'disponibles', 0)),
      );
      // Pero los 150 cigarros sí se pueden vender sueltos.
      final cigar = await byName('Cigarro suelto');
      await sales.registerSale(sessionId: sessionId, lines: [line(cigar, 150)], paymentMethod: PaymentMethod.cash);
      expect(await pool(), 0);
    });

    test('anular devuelve al pool exactamente lo que se descontó', () async {
      await addLooseCigarette();
      final pack = await byName('Paquete de 200 cigarros');
      final cigar = await byName('Cigarro suelto');
      final sale = await sales.registerSale(
        sessionId: sessionId,
        lines: [line(cigar, 5), line(pack, 1)],
        paymentMethod: PaymentMethod.cash,
      );
      expect(await pool(), 2000 - 205);

      await sales.voidSale(saleId: sale.id, reason: 'x', cashSessionId: sessionId);
      expect(await pool(), 2000);
    });

    test('una venta hecha ANTES de agregar el cigarro se anula bien aunque la unidad haya cambiado', () async {
      // Se venden 3 paquetes cuando el pool todavía se medía en paquetes.
      final pack = await byName('Paquete de 200 cigarros');
      final sale = await sales.registerSale(
        sessionId: sessionId,
        lines: [line(pack, 3)],
        paymentMethod: PaymentMethod.cash,
      );
      expect(await pool(), 7);

      // Después se agrega el cigarro suelto: el pool pasa a cigarros (×200).
      await addLooseCigarette();
      expect(await pool(), 1400);

      // Anular la venta vieja devuelve 3 paquetes = 600 cigarros, no 3 cigarros.
      await sales.voidSale(saleId: sale.id, reason: 'x', cashSessionId: sessionId);
      expect(await pool(), 2000);
    });

    test('también las ventas muy antiguas, sin dato de dónde se descontó', () async {
      final pack = await byName('Paquete de 200 cigarros');
      final sale = await sales.registerSale(
        sessionId: sessionId,
        lines: [line(pack, 2)],
        paymentMethod: PaymentMethod.cash,
      );
      await db.customStatement('UPDATE sale_items SET stock_product_id = NULL, stock_quantity = NULL');

      await addLooseCigarette();
      await sales.voidSale(saleId: sale.id, reason: 'x', cashSessionId: sessionId);
      expect(await pool(), 2000);
    });

    test('quitar el cigarro suelto devuelve las existencias a paquetes', () async {
      await addLooseCigarette();
      await products.savePresentations(baseId, const [], baseUnitsPerPack: 1, stockScale: 1 / 200);
      expect(await pool(), 10);
      expect((await products.watchAll().first).single.unitsPerPack, 1);
    });

    test('el costo escrito en el paquete se reparte hacia el cigarro (por tamaño)', () async {
      await addLooseCigarette();
      await products.setCostFromPresentation(baseId, 2500); // llegó a $25 el paquete
      // $25 ÷ 200 = 12.5¢ por cigarro (se redondea a 13¢); el paquete queda exacto.
      expect((await byName('Cigarro suelto')).costCents, 13);
      expect((await byName('Paquete de 200 cigarros')).costCents, 2500);

      await products.setCostFromPresentation((await byName('Cigarro suelto')).id, 10); // 10¢ el cigarro
      expect((await byName('Paquete de 200 cigarros')).costCents, 2000);
    });

    test('agregar inventario por paquetes suma 200 cigarros por paquete', () async {
      await addLooseCigarette();
      final provider = InventoryProvider(products);
      addTearDown(provider.dispose);
      await Future<void>.delayed(const Duration(milliseconds: 200));

      final pack = provider.products.firstWhere((p) => p.name == 'Paquete de 200 cigarros');
      final added = await provider.addStock(pack, 5, costCents: 2600);
      expect(added, 1000);
      expect(await pool(), 3000);
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(provider.products.firstWhere((p) => p.name == 'Cigarro suelto').costCents, 13); // 26 ÷ 200
    });
  });

  group('flujo completo en pantalla: crear el paquete, agregarle el cigarro suelto y abastecer', () {
    void ignoreOverflow() {
      final original = FlutterError.onError;
      FlutterError.onError = (details) {
        if (details.exceptionAsString().contains('overflowed')) return;
        original?.call(details);
      };
      addTearDown(() => FlutterError.onError = original);
    }

    Future<void> settle(WidgetTester tester) async {
      for (var i = 0; i < 6; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 60)));
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    Future<void> teardown(WidgetTester tester) async {
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump(const Duration(seconds: 1));
    }

    testWidgets('el paquete es el base, se le agrega el cigarro suelto (200 por paquete) y se abastece por paquetes',
        (tester) async {
      ignoreOverflow();
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      late final String baseId;
      await tester.runAsync(() async {
        final categories = await seedCategoriesIfEmpty(db);
        final units = await seedUnitsIfEmpty(db);
        baseId = await DriftProductRepository(db).add(
          ProductsTableCompanion.insert(
            name: 'Paquete de cigarros',
            categoryId: categories.values.first,
            unitId: units['Paquete']!,
            priceCents: 3000,
            costCents: 0, // sin costo ni existencias: aún no se sabe
          ),
        );
      });

      await tester.binding.setSurfaceSize(const Size(1500, 2200));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider(lazy: false, create: (_) => CategoryProvider(DriftCategoryRepository(db))),
            ChangeNotifierProvider(lazy: false, create: (_) => UnitProvider(DriftUnitRepository(db))),
            ChangeNotifierProvider(lazy: false, create: (_) => InventoryProvider(DriftProductRepository(db))),
          ],
          child: const MaterialApp(home: Scaffold(body: InventoryScreen())),
        ),
      );
      await settle(tester);

      Future<List<ProductsTableData>> rows() async =>
          (await tester.runAsync(() => db.select(db.productsTable).get()))!;

      // 1) Agregar presentación desde la fila del paquete: el cigarro suelto viene dentro.
      await tester.tap(find.byTooltip('Agregar presentación'));
      await tester.pumpAndSettle();
      await tester.enterText(find.widgetWithText(TextFormField, 'Nombre de la presentación'), 'Cigarro suelto');
      await tester.ensureVisible(find.text('Viene dentro de'));
      await tester.tap(find.text('Viene dentro de'));
      await tester.pumpAndSettle();
      await tester.enterText(find.widgetWithText(TextFormField, 'Trae'), '200');
      await tester.enterText(find.widgetWithText(TextFormField, 'Precio de venta').last, '0.15');
      await tester.pump();
      expect(find.text('1 Paquete de cigarros trae 200 de Cigarro suelto'), findsOneWidget);
      expect(find.text('Equivale a 1 unidad mínima del grupo'), findsOneWidget);

      await tester.ensureVisible(find.text('Guardar'));
      await tester.tap(find.text('Guardar'));
      await settle(tester);

      var all = await rows();
      final pack = all.firstWhere((r) => r.id == baseId);
      final loose = all.firstWhere((r) => r.name == 'Cigarro suelto');
      expect(pack.unitsPerPack, 200); // el paquete vale 200 cigarros
      expect(loose.unitsPerPack, 1);
      expect(loose.baseProductId, baseId); // el paquete sigue siendo el base
      expect(loose.priceCents, 15);

      // 2) Llegan 5 paquetes: desde la fila del paquete se esperan paquetes.
      // Filas por nombre: "Cigarro suelto" y "Paquete de cigarros".
      await tester.tap(find.byTooltip('Agregar inventario').at(1));
      await tester.pumpAndSettle();
      expect(tester.widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'Paquete de cigarros')).selected, isTrue);
      await tester.enterText(find.byType(TextFormField).first, '5');
      await tester.pump();
      expect(find.text('Se agregan 1000 u'), findsOneWidget);
      await tester.tap(find.text('Agregar'));
      await settle(tester);

      all = await rows();
      expect(all.firstWhere((r) => r.id == baseId).stock, 1000); // 5 paquetes = 1,000 cigarros

      // 3) Y desde la fila del cigarro suelto se esperan cigarros.
      await tester.tap(find.byTooltip('Agregar inventario').at(0));
      await tester.pumpAndSettle();
      expect(tester.widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'Cigarro suelto')).selected, isTrue);
      await tester.enterText(find.byType(TextFormField).first, '30');
      await tester.pump();
      expect(find.text('Hay 1000 u → quedarán 1030 u'), findsOneWidget);
      await tester.tap(find.text('Agregar'));
      await settle(tester);
      all = await rows();
      expect(all.firstWhere((r) => r.id == baseId).stock, 1030);

      await teardown(tester);
    });
  });
}
