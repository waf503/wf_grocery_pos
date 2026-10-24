import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:wf_grocery_pos/core/database/app_database.dart';
import 'package:wf_grocery_pos/core/format/money_input.dart';
import 'package:wf_grocery_pos/features/cash/data/drift_cash_repository.dart';
import 'package:wf_grocery_pos/features/categories/data/category_seeder.dart';
import 'package:wf_grocery_pos/features/pos/widgets/checkout_dialog.dart';
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
  moneyInputTests();
  group('efectivo recibido y vuelto', () {
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

    test('con vuelto: entra lo recibido, el vuelto sale aparte y el neto es el total', () async {
      final total = cola.priceCents * 2; // 2400
      final sale = await sales.registerSale(
        sessionId: session.id,
        lines: [_line(cola, 2)],
        paymentMethod: PaymentMethod.cash,
        tenderedCents: 5000,
      );

      expect(sale.totalCents, total);
      expect(sale.tenderedCents, 5000);
      expect(sale.changeCents, 5000 - total);

      final current = (await cash.watchCurrent().first)!;
      final byType = {for (final m in current.movements) m.type: m.amountCents};
      expect(byType[CashMovementType.sale], 5000); // lo que entregó el cliente
      expect(byType[CashMovementType.change], 5000 - total); // el vuelto, como salida de caja
      expect(current.changeCents, 5000 - total);
      expect(current.expectedCents, 10000 + total); // neto = fondo + lo vendido
      expect(current.movements.where((m) => m.type == CashMovementType.change).single.note, 'Vuelto V-000001');
      expect(CashMovementType.change.isOutflow, isTrue);
    });

    test('pago exacto (sin monto): sin movimiento de vuelto y se guarda recibido = total', () async {
      final sale = await sales.registerSale(
        sessionId: session.id,
        lines: [_line(cola, 1)],
        paymentMethod: PaymentMethod.cash,
      );
      expect(sale.tenderedCents, sale.totalCents);
      expect(sale.changeCents, 0);

      final current = (await cash.watchCurrent().first)!;
      expect(current.movements.map((m) => m.type), [CashMovementType.sale]);
      expect(current.expectedCents, 10000 + sale.totalCents);
    });

    test('recibido igual al total también es exacto', () async {
      final total = cola.priceCents;
      final sale = await sales.registerSale(
        sessionId: session.id,
        lines: [_line(cola, 1)],
        paymentMethod: PaymentMethod.cash,
        tenderedCents: total,
      );
      expect(sale.changeCents, 0);
      expect((await cash.watchCurrent().first)!.movements, hasLength(1));
    });

    test('si lo recibido no alcanza, falla y no se guarda NADA', () async {
      await expectLater(
        sales.registerSale(
          sessionId: session.id,
          lines: [_line(cola, 2)],
          paymentMethod: PaymentMethod.cash,
          tenderedCents: 1000,
        ),
        throwsA(isA<InsufficientTenderException>().having((e) => e.missingCents, 'faltan', cola.priceCents * 2 - 1000)),
      );
      expect(await sales.watchBetween(DateTime(2000)).first, isEmpty);
      expect((await cash.watchCurrent().first)!.movements, isEmpty);
      expect((await (db.select(db.productsTable)..where((r) => r.id.equals(cola.id))).getSingle()).stock, cola.stock);
    });

    test('tarjeta y fiado no admiten monto recibido ni guardan vuelto', () async {
      expect(
        () => sales.registerSale(
          sessionId: session.id,
          lines: [_line(cola, 1)],
          paymentMethod: PaymentMethod.card,
          tenderedCents: 5000,
        ),
        throwsArgumentError,
      );
      final sale = await sales.registerSale(
        sessionId: session.id,
        lines: [_line(cola, 1)],
        paymentMethod: PaymentMethod.card,
      );
      expect(sale.tenderedCents, isNull);
      expect(sale.changeCents, isNull);
    });

    test('anular una venta con vuelto devuelve solo el total: la caja queda como estaba', () async {
      final sale = await sales.registerSale(
        sessionId: session.id,
        lines: [_line(cola, 2)],
        paymentMethod: PaymentMethod.cash,
        tenderedCents: 5000,
      );
      await sales.voidSale(saleId: sale.id, reason: 'x', cashSessionId: session.id);
      expect((await cash.watchCurrent().first)!.expectedCents, 10000);
    });

    test('el historial conserva con cuánto pagó el cliente', () async {
      await sales.registerSale(
        sessionId: session.id,
        lines: [_line(cola, 1)],
        paymentMethod: PaymentMethod.cash,
        tenderedCents: 2000,
      );
      final saved = (await sales.watchBetween(DateTime(2000)).first).single;
      expect(saved.tenderedCents, 2000);
      expect(saved.changeCents, 2000 - cola.priceCents);
      expect(saved.change, (2000 - cola.priceCents) / 100);
    });

    test('al cerrar la caja el esperado ya descuenta los vueltos', () async {
      final sale = await sales.registerSale(
        sessionId: session.id,
        lines: [_line(cola, 1)],
        paymentMethod: PaymentMethod.cash,
        tenderedCents: 10000,
      );
      final expected = 10000 + sale.totalCents;
      final closed = await cash.close(sessionId: session.id, countedCents: expected);
      expect(closed.expectedCents, expected);
      expect(closed.differenceCents, 0); // cuadra: el vuelto no genera faltante
    });
  });

  group('migración v15 → v16', () {
    late Directory tempDir;
    late File dbFile;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('wf_tender_test');
      dbFile = File(p.join(tempDir.path, 'test.sqlite'));
    });

    tearDown(() => tempDir.delete(recursive: true));

    test('las ventas en efectivo anteriores se conservan (sin dato de recibido)', () async {
      final seeded = await _seededDb(AppDatabase.forTesting(NativeDatabase(dbFile)));
      final cola = await (seeded.select(seeded.productsTable)..where((r) => r.name.equals('Coca-Cola Lata 355ml'))).getSingle();
      final session = await DriftCashRepository(seeded).open(openingCents: 1000);
      await DriftSaleRepository(seeded).registerSale(
        sessionId: session.id,
        lines: [_line(cola, 1)],
        paymentMethod: PaymentMethod.cash,
      );
      await seeded.customStatement('ALTER TABLE sales DROP COLUMN tendered_cents');
      await seeded.customStatement('ALTER TABLE sales DROP COLUMN change_cents');
      await seeded.customStatement('DROP TABLE product_combos');
      await seeded.customStatement('ALTER TABLE products DROP COLUMN base_product_id');
      await seeded.customStatement('ALTER TABLE products DROP COLUMN units_per_pack');
      await seeded.customStatement('ALTER TABLE sale_items DROP COLUMN stock_product_id');
      await seeded.customStatement('ALTER TABLE sale_items DROP COLUMN stock_quantity');
      await seeded.customStatement('PRAGMA user_version = 15');
      await seeded.close();

      final migrated = AppDatabase.forTesting(NativeDatabase(dbFile));
      addTearDown(migrated.close);
      final history = await DriftSaleRepository(migrated).watchBetween(DateTime(2000)).first;
      expect(history.single.number, 1);
      expect(history.single.tenderedCents, isNull);
      expect(history.single.changeCents, isNull);

      // Y se puede cobrar con vuelto sobre la base migrada.
      final next = await DriftSaleRepository(migrated).registerSale(
        sessionId: session.id,
        lines: [_line(cola, 1)],
        paymentMethod: PaymentMethod.cash,
        tenderedCents: 5000,
      );
      expect(next.changeCents, 5000 - cola.priceCents);
    });
  });

  group('diálogo de cobro', () {
    testWidgets('muestra el vuelto en vivo y devuelve lo recibido', (tester) async {
      PaymentChoice? result;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () async => result = await showPaymentMethodDialog(context, total: 12.5),
                child: const Text('abrir'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('abrir'));
      await tester.pumpAndSettle();

      expect(find.text('Pago exacto, sin vuelto'), findsOneWidget);

      await tester.enterText(find.byType(TextField), '20');
      await tester.pump();
      expect(find.text('Vuelto: \$7.50'), findsOneWidget);

      await tester.tap(find.text('Revisar venta'));
      await tester.pumpAndSettle();
      expect(result, (method: PaymentMethod.cash, tenderedCents: 2000));
    });

    testWidgets('si lo recibido no alcanza muestra lo que falta y no deja confirmar', (tester) async {
      PaymentChoice? result;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () async => result = await showPaymentMethodDialog(context, total: 12.5),
                child: const Text('abrir'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('abrir'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), '10');
      await tester.pump();
      expect(find.text('Faltan \$2.50'), findsOneWidget);
      final confirm = tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Revisar venta'));
      expect(confirm.onPressed, isNull);
      expect(result, isNull);
    });

    testWidgets('los atajos de monedas y billetes llenan el monto; los que no alcanzan salen deshabilitados', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showPaymentMethodDialog(context, total: 12.5),
                child: const Text('abrir'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('abrir'));
      await tester.pumpAndSettle();

      ActionChip chip(String label) => tester.widget<ActionChip>(find.widgetWithText(ActionChip, label));

      // Siempre están los típicos, en orden: 25¢ 50¢ 75¢ $1 $5 $10 $20.
      for (final label in ['25¢', '50¢', '75¢', '\$1', '\$5', '\$10', '\$20']) {
        expect(find.widgetWithText(ActionChip, label), findsOneWidget, reason: label);
      }
      // Con $12.50 los menores al total no se pueden elegir; $20 sí.
      expect(chip('25¢').onPressed, isNull);
      expect(chip('\$10').onPressed, isNull);
      expect(chip('\$20').onPressed, isNotNull);
      // Los billetes grandes solo aparecen en ventas de más de $20.
      expect(find.widgetWithText(ActionChip, '\$50'), findsNothing);

      await tester.ensureVisible(find.widgetWithText(ActionChip, '\$20'));
      await tester.tap(find.widgetWithText(ActionChip, '\$20'));
      await tester.pump();
      expect(find.text('Vuelto: \$7.50'), findsOneWidget);

      await tester.ensureVisible(find.text('Exacto'));
      await tester.tap(find.text('Exacto'));
      await tester.pump();
      expect(find.text('Pago exacto, sin vuelto'), findsOneWidget);
    });

    testWidgets('una venta chica se paga con monedas: 25¢ para \$0.20 deja 5¢ de vuelto', (tester) async {
      PaymentChoice? result;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () async => result = await showPaymentMethodDialog(context, total: 0.20),
                child: const Text('abrir'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('abrir'));
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.widgetWithText(ActionChip, '25¢'));
      await tester.tap(find.widgetWithText(ActionChip, '25¢'));
      await tester.pump();
      expect(find.text('Vuelto: \$0.05'), findsOneWidget);
      await tester.tap(find.text('Revisar venta'));
      await tester.pumpAndSettle();
      expect(result, (method: PaymentMethod.cash, tenderedCents: 25));
    });

    testWidgets('en ventas de más de \$20 aparecen también \$50 y \$100', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showPaymentMethodDialog(context, total: 35),
                child: const Text('abrir'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('abrir'));
      await tester.pumpAndSettle();

      expect(find.widgetWithText(ActionChip, '\$50'), findsOneWidget);
      expect(find.widgetWithText(ActionChip, '\$100'), findsOneWidget);
      expect(tester.widget<ActionChip>(find.widgetWithText(ActionChip, '\$20')).onPressed, isNull);
      expect(tester.widget<ActionChip>(find.widgetWithText(ActionChip, '\$50')).onPressed, isNotNull);
    });

    testWidgets('con tarjeta o fiado no se pide efectivo', (tester) async {
      PaymentChoice? result;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () async => result = await showPaymentMethodDialog(context, total: 12.5, customerName: 'Ana'),
                child: const Text('abrir'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('abrir'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Fiado'));
      await tester.pumpAndSettle();
      expect(find.byType(TextField), findsNothing);

      await tester.tap(find.text('Revisar venta'));
      await tester.pumpAndSettle();
      expect(result, (method: PaymentMethod.credit, tenderedCents: null));
    });
  });
}

void moneyInputTests() {
  group('campo de dinero (solo números con hasta 2 decimales)', () {
    const formatter = MoneyInputFormatter();

    /// Escribe [text] sobre un campo que tenía [before] y devuelve cómo queda.
    String type(String before, String text) => formatter
        .formatEditUpdate(
          TextEditingValue(text: before),
          TextEditingValue(text: text),
        )
        .text;

    test('acepta dígitos, un punto o una coma y hasta dos decimales', () {
      expect(type('', '2'), '2');
      expect(type('2', '20'), '20');
      expect(type('20', '20.'), '20.');
      expect(type('20.', '20.5'), '20.5');
      expect(type('20.5', '20.50'), '20.50');
      expect(type('', '0,25'), '0,25');
      expect(type('', '.5'), '.5');
    });

    test('rechaza letras, signos y espacios: el campo queda como estaba', () {
      expect(type('12', '12a'), '12');
      expect(type('12', '12e'), '12');
      expect(type('12', '-12'), '12');
      expect(type('12', '12 5'), '12');
      expect(type('12', r'$12'), '12');
      expect(type('', 'abc'), '');
    });

    test('rechaza un segundo separador y un tercer decimal', () {
      expect(type('12.5', '12.5.'), '12.5');
      expect(type('12.5', '12.5,5'), '12.5');
      expect(type('12.50', '12.505'), '12.50');
    });

    test('limita los dígitos enteros a siete', () {
      expect(type('1234567', '12345678'), '1234567');
    });

    testWidgets('en el diálogo de cobro no deja escribir letras', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showPaymentMethodDialog(context, total: 12.5),
                child: const Text('abrir'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('abrir'));
      await tester.pumpAndSettle();

      final field = find.byType(TextField);
      await tester.enterText(field, '2a0');
      await tester.pump();
      expect(tester.widget<TextField>(field).controller!.text, '');

      await tester.enterText(field, '20');
      await tester.pump();
      await tester.enterText(field, '20.555');
      await tester.pump();
      expect(tester.widget<TextField>(field).controller!.text, '20');
      expect(find.text('Vuelto: \$7.50'), findsOneWidget);
    });
  });
}
