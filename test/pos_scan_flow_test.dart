import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:image/image.dart' as img;
import 'package:provider/provider.dart';

import 'package:wf_grocery_pos/core/database/app_database.dart';
import 'package:wf_grocery_pos/features/cash/data/drift_cash_repository.dart';
import 'package:wf_grocery_pos/features/categories/data/category_seeder.dart';
import 'package:wf_grocery_pos/features/categories/data/drift_category_repository.dart';
import 'package:wf_grocery_pos/features/customers/data/drift_customer_repository.dart';
import 'package:wf_grocery_pos/features/pos/pos_screen.dart';
import 'package:wf_grocery_pos/features/products/data/drift_product_repository.dart';
import 'package:wf_grocery_pos/features/sales/data/drift_sale_repository.dart';
import 'package:wf_grocery_pos/features/units/data/drift_unit_repository.dart';
import 'package:wf_grocery_pos/features/units/data/unit_seeder.dart';
import 'package:wf_grocery_pos/state/cash_provider.dart';
import 'package:wf_grocery_pos/state/category_provider.dart';
import 'package:wf_grocery_pos/state/customer_provider.dart';
import 'package:wf_grocery_pos/state/inventory_provider.dart';
import 'package:wf_grocery_pos/state/pos_provider.dart';
import 'package:wf_grocery_pos/state/sales_provider.dart';
import 'package:wf_grocery_pos/state/unit_provider.dart';

/// Las pruebas usan una fuente de prueba muy ancha: los desbordes de diseño
/// que produce no son fallos del flujo que se prueba aquí, así que se ignoran.
void _ignoreOverflow() {
  final original = FlutterError.onError;
  FlutterError.onError = (details) {
    if (details.exceptionAsString().contains('overflowed')) return;
    original?.call(details);
  };
  addTearDown(() => FlutterError.onError = original);
}

/// La base de la última pantalla montada (para comprobar qué se guardó).
AppDatabase? _db;

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 60)));
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _teardown(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
  await tester.pump(const Duration(seconds: 1));
}

/// Monta el POS con una base en memoria que tiene una Oreo (pieza, 49 en
/// stock, código 7702133009037) y una papa por libra.
Future<PosProvider> _mountPos(WidgetTester tester, {bool withImages = false, bool withPacks = false, bool withInverse = false}) async {
  _ignoreOverflow();
  final db = AppDatabase.forTesting(NativeDatabase.memory());
  _db = db;
  await tester.runAsync(() async {
    final categories = await seedCategoriesIfEmpty(db);
    final units = await seedUnitsIfEmpty(db);
    final photo = Uint8List.fromList(img.encodeJpg(img.Image(width: 300, height: 300), quality: 80));
    Future<void> product(String id, String name, String barcode, String unit, double stock) async {
      await db.into(db.productsTable).insert(
            ProductsTableCompanion.insert(
              id: Value(id),
              name: name,
              categoryId: categories.values.first,
              unitId: units[unit]!,
              priceCents: 35,
              costCents: 20,
              stock: Value(stock),
              barcode: Value(barcode),
              hasImage: Value(withImages),
            ),
          );
      if (withImages) {
        await db.into(db.productImagesTable).insert(ProductImagesTableCompanion.insert(productId: id, bytes: photo));
      }
    }
    await product('oreo', 'Galleta Oreo 54 g', '7702133009037', 'Pieza', 49);
    await product('papa', 'Papa', '2100000000011', 'Libra', 20);
    if (withInverse) {
      // El PAQUETE es el producto base (vale 200 cigarros) y el cigarro suelto viene
      // dentro. El pool son 410 cigarros: 2 paquetes completos y 10 sueltos.
      await db.into(db.productsTable).insert(
            ProductsTableCompanion.insert(
              id: const Value('paq'),
              name: 'Paquete de 200 cigarros',
              categoryId: categories.values.first,
              unitId: units['Paquete']!,
              priceCents: 3000,
              costCents: 2400,
              stock: const Value(410),
              barcode: const Value('7501000000009'),
              unitsPerPack: const Value(200),
            ),
          );
      await db.into(db.productsTable).insert(
            ProductsTableCompanion.insert(
              id: const Value('cig'),
              name: 'Cigarro suelto',
              categoryId: categories.values.first,
              unitId: units['Paquete']!,
              priceCents: 15,
              costCents: 12,
              barcode: const Value('7501000000010'),
              baseProductId: const Value('paq'),
              unitsPerPack: const Value(1),
            ),
          );
    }
    if (withPacks) {
      // 45 cigarros sueltos y su presentación: cajetilla de 20 (comparten existencias).
      await product('cig', 'Cigarro suelto', '7500000000099', 'Pieza', 45);
      await db.into(db.productsTable).insert(
            ProductsTableCompanion.insert(
              id: const Value('caj'),
              name: 'Cajetilla de 20',
              categoryId: categories.values.first,
              unitId: units['Pieza']!,
              priceCents: 175,
              costCents: 120,
              barcode: const Value('7501000000001'),
              baseProductId: const Value('cig'),
              unitsPerPack: const Value(20),
            ),
          );
    }
    await DriftCashRepository(db).open(openingCents: 1000);
  });

  final pos = PosProvider();
  await tester.binding.setSurfaceSize(const Size(1400, 900));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(lazy: false, create: (_) => CategoryProvider(DriftCategoryRepository(db))),
        ChangeNotifierProvider(lazy: false, create: (_) => UnitProvider(DriftUnitRepository(db))),
        ChangeNotifierProvider(lazy: false, create: (_) => InventoryProvider(DriftProductRepository(db))),
        ChangeNotifierProvider(lazy: false, create: (_) => CustomerProvider(DriftCustomerRepository(db))),
        ChangeNotifierProvider(lazy: false, create: (_) => SalesProvider(DriftSaleRepository(db))),
        ChangeNotifierProvider(lazy: false, create: (_) => CashProvider(DriftCashRepository(db))),
        ChangeNotifierProvider<PosProvider>.value(value: pos),
      ],
      child: const MaterialApp(home: PosScreen()),
    ),
  );
  await _settle(tester);
  return pos;
}

Future<void> _scan(WidgetTester tester, String code) async {
  await tester.enterText(find.byType(TextField).first, code);
  await tester.testTextInput.receiveAction(TextInputAction.done);
  await _settle(tester);
}

void main() {
  // El recibo formatea fechas en español (la app lo hace al arrancar).
  setUpAll(() => initializeDateFormatting('es_MX'));

  testWidgets('escanear un producto registrado lo agrega al carrito', (tester) async {
    final pos = await _mountPos(tester);
    expect(find.text('Galleta Oreo 54 g'), findsWidgets); // la tarjeta del POS se dibuja

    await _scan(tester, '7702133009037');

    expect(pos.cart, hasLength(1));
    expect(pos.cart.single.product.name, 'Galleta Oreo 54 g');
    expect(pos.cart.single.quantity, 1);

    // Escanearlo otra vez suma una pieza.
    await _scan(tester, '7702133009037');
    expect(pos.cart.single.quantity, 2);
    await _teardown(tester);
  });

  testWidgets('el carrito muestra el nombre COMPLETO del producto y sigue mostrando el último agregado', (tester) async {
    final pos = await _mountPos(tester);
    const long = 'Desodorante Nivea Derma Control tono uniforme roll on femenino - 50 ml';
    for (var i = 0; i < 12; i++) {
      pos.addGeneric(name: i == 11 ? long : 'Producto $i', priceCents: 100);
    }
    await _settle(tester);

    final text = tester.widget<Text>(find.text(long));
    expect(text.overflow, isNull); // sin "..."
    expect(text.maxLines, isNull);
    // El último agregado quedó a la vista dentro de la lista desplazable.
    final rowBottom = tester.getBottomLeft(find.text(long)).dy;
    expect(rowBottom, lessThanOrEqualTo(tester.view.physicalSize.height / tester.view.devicePixelRatio));
    await _teardown(tester);
  });

  testWidgets('tocar la tarjeta del producto también lo agrega', (tester) async {
    final pos = await _mountPos(tester);
    await tester.tap(find.text('Galleta Oreo 54 g').first);
    await _settle(tester);
    expect(pos.cart.single.product.id, 'oreo');
    await _teardown(tester);
  });

  testWidgets('un producto por libra pide la cantidad y la agrega', (tester) async {
    final pos = await _mountPos(tester);
    await _scan(tester, '2100000000011');

    expect(find.text('Agregar'), findsOneWidget); // el cuadro de cantidad
    await tester.tap(find.text('Agregar'));
    await _settle(tester);

    expect(pos.cart.single.product.id, 'papa');
    expect(pos.cart.single.quantity, 1); // propuesta: 1 lb
    await _teardown(tester);
  });

  testWidgets('con productos que tienen miniatura: se dibujan las tarjetas y escanear agrega al carrito', (tester) async {
    final pos = await _mountPos(tester, withImages: true);
    expect(find.byType(Image), findsWidgets); // las miniaturas se pintan

    await _scan(tester, '7702133009037');
    expect(pos.cart.single.product.name, 'Galleta Oreo 54 g');
    await _teardown(tester);
  });

  testWidgets('las presentaciones comparten las existencias: cajetillas y sueltas suman contra el mismo pool', (tester) async {
    final pos = await _mountPos(tester, withPacks: true);

    // 45 cigarros alcanzan para 2 cajetillas (40); la tercera ya no cabe.
    await _scan(tester, '7501000000001');
    await _scan(tester, '7501000000001');
    expect(pos.cart.single.product.id, 'caj');
    expect(pos.cart.single.quantity, 2);
    await _scan(tester, '7501000000001');
    expect(pos.cart.single.quantity, 2, reason: 'solo quedan 5 cigarros: no cabe otra cajetilla');

    // Los 5 que sobran sí se pueden vender sueltos, y ni uno más.
    for (var i = 0; i < 5; i++) {
      await _scan(tester, '7500000000099');
    }
    final loose = pos.cart.firstWhere((i) => i.product.id == 'cig');
    expect(loose.quantity, 5);
    await _scan(tester, '7500000000099');
    expect(loose.quantity, 5, reason: 'el pool se agotó con las cajetillas del carrito');
    expect(pos.poolUnitsInCart('cig'), 45);
    await _teardown(tester);
  });

  testWidgets('con el PAQUETE como base: paquetes y cigarros sueltos comparten el mismo pool', (tester) async {
    final pos = await _mountPos(tester, withInverse: true);

    // El pool son 410 cigarros: el POS muestra 2 paquetes y 410 cigarros.
    expect(find.text('2 paq'), findsOneWidget);
    expect(find.text('410 disp.'), findsOneWidget);

    await _scan(tester, '7501000000009');
    await _scan(tester, '7501000000009');
    expect(pos.cart.single.product.id, 'paq');
    expect(pos.cart.single.quantity, 2);
    await _scan(tester, '7501000000009');
    expect(pos.cart.single.quantity, 2, reason: 'solo sobran 10 cigarros: no cabe otro paquete');

    // Los 10 cigarros que sobran se venden sueltos, y ni uno más.
    for (var i = 0; i < 10; i++) {
      await _scan(tester, '7501000000010');
    }
    final loose = pos.cart.firstWhere((i) => i.product.id == 'cig');
    expect(loose.quantity, 10);
    await _scan(tester, '7501000000010');
    expect(loose.quantity, 10, reason: 'el pool se agotó con lo que hay en el carrito');
    expect(pos.poolUnitsInCart('paq'), 410); // 2 × 200 + 10
    await _teardown(tester);
  });

  group('revisión de la venta antes de registrarla', () {
    Future<List<SalesTableData>> savedSales(WidgetTester tester) async =>
        (await tester.runAsync(() => _db!.select(_db!.salesTable).get()))!;

    /// Texto dentro del cuadro de revisión (el carrito de atrás repite algunos).
    Finder inReview(String text) => find.descendant(of: find.byType(AlertDialog), matching: find.text(text));

    Future<void> startCheckout(WidgetTester tester, PosProvider pos) async {
      await _scan(tester, '7702133009037'); // Galleta Oreo a $0.35
      await _scan(tester, '7702133009037'); // 2 piezas = $0.70
      expect(pos.cart.single.quantity, 2);
      await tester.tap(find.text('Cobrar'));
      await tester.pumpAndSettle();
      await tester.enterText(find.widgetWithText(TextField, 'Efectivo recibido'), '5');
      await tester.pump();
      await tester.tap(find.text('Revisar venta'));
      await tester.pumpAndSettle();
    }

    testWidgets('muestra el ticket completo y NO guarda nada hasta confirmar', (tester) async {
      final pos = await _mountPos(tester);
      await startCheckout(tester, pos);

      // El ticket: producto, cantidad, precio, total, pago, recibido y vuelto.
      expect(find.text('Confirmar venta'), findsOneWidget);
      expect(inReview('Galleta Oreo 54 g'), findsOneWidget);
      expect(inReview('2 ×'), findsOneWidget);
      expect(inReview(r'$0.35 c/u'), findsOneWidget);
      expect(inReview('Total (2 artículos)'), findsOneWidget);
      expect(inReview(r'$0.70'), findsWidgets); // el renglón y el total
      expect(inReview('Efectivo'), findsOneWidget);
      expect(inReview('Recibido'), findsOneWidget);
      expect(inReview(r'$5.00'), findsOneWidget);
      expect(inReview('Vuelto a entregar'), findsOneWidget);
      expect(inReview(r'$4.30'), findsOneWidget); // 5.00 - 0.70

      // Todavía no hay venta registrada, el stock no se movió y el carrito sigue.
      expect(await savedSales(tester), isEmpty);
      expect(pos.cart.single.quantity, 2);

      // Se cancela para no dejar el cuadro abierto.
      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();
      await _teardown(tester);
    });

    testWidgets('"Corregir pago" vuelve al cobro con lo escrito y permite cambiarlo antes de confirmar', (tester) async {
      final pos = await _mountPos(tester);
      await startCheckout(tester, pos);

      await tester.tap(find.text('Corregir pago'));
      await tester.pumpAndSettle();
      // Se reabre el cobro con el efectivo que ya se había escrito.
      expect(find.text('Cobrar venta'), findsOneWidget);
      final field = tester.widget<TextField>(find.widgetWithText(TextField, 'Efectivo recibido'));
      expect(field.controller!.text, '5.00');
      expect(await savedSales(tester), isEmpty);

      // El cliente en realidad dio $10.
      await tester.enterText(find.widgetWithText(TextField, 'Efectivo recibido'), '10');
      await tester.pump();
      await tester.tap(find.text('Revisar venta'));
      await tester.pumpAndSettle();
      expect(inReview(r'$10.00'), findsOneWidget);
      expect(inReview(r'$9.30'), findsOneWidget); // 10.00 - 0.70

      await tester.tap(find.text('Confirmar venta'));
      await _settle(tester);

      // Ahora sí: se guarda con lo corregido y se muestra el recibo.
      final sales = await savedSales(tester);
      expect(sales, hasLength(1));
      expect(sales.single.totalCents, 70);
      expect(sales.single.tenderedCents, 1000);
      expect(sales.single.changeCents, 930);
      expect(find.text('Venta registrada'), findsOneWidget);
      expect(pos.isEmpty, isTrue); // el carrito se vació

      await tester.tap(find.text('Listo'));
      await tester.pumpAndSettle();
      await _teardown(tester);
    });

    testWidgets('"Cancelar" abandona el cobro: no se guarda nada y el carrito se conserva', (tester) async {
      final pos = await _mountPos(tester);
      await startCheckout(tester, pos);

      await tester.tap(find.text('Cancelar'));
      await _settle(tester);

      expect(find.text('Confirmar venta'), findsNothing);
      expect(find.text('Cobrar venta'), findsNothing);
      expect(await savedSales(tester), isEmpty);
      expect(pos.cart.single.quantity, 2); // se puede seguir editando el carrito
      await _teardown(tester);
    });

    testWidgets('Esc en la revisión equivale a volver al cobro (no se pierde lo escrito)', (tester) async {
      final pos = await _mountPos(tester);
      await startCheckout(tester, pos);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.text('Cobrar venta'), findsOneWidget);
      expect(
        tester.widget<TextField>(find.widgetWithText(TextField, 'Efectivo recibido')).controller!.text,
        '5.00',
      );
      expect(await savedSales(tester), isEmpty);
      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();
      await _teardown(tester);
    });

    testWidgets('con Enter se confirma rápido: monto + Enter + Enter', (tester) async {
      final pos = await _mountPos(tester);
      await _scan(tester, '7702133009037');
      await tester.tap(find.text('Cobrar'));
      await tester.pumpAndSettle();

      await tester.enterText(find.widgetWithText(TextField, 'Efectivo recibido'), '1');
      await tester.testTextInput.receiveAction(TextInputAction.done); // Enter en el monto
      await tester.pumpAndSettle();
      expect(find.text('Confirmar venta'), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.enter); // Enter en la revisión
      await _settle(tester);
      expect((await savedSales(tester)).single.changeCents, 65); // 1.00 - 0.35
      expect(pos.isEmpty, isTrue);
      await tester.tap(find.text('Listo'));
      await tester.pumpAndSettle();
      await _teardown(tester);
    });
  });
}
