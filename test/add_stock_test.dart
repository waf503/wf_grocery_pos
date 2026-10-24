import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';

import 'package:wf_grocery_pos/core/database/app_database.dart';
import 'package:wf_grocery_pos/features/categories/data/category_seeder.dart';
import 'package:wf_grocery_pos/features/categories/data/drift_category_repository.dart';
import 'package:wf_grocery_pos/features/inventory/inventory_screen.dart';
import 'package:wf_grocery_pos/features/inventory/widgets/add_stock_dialog.dart';
import 'package:wf_grocery_pos/features/products/data/drift_product_repository.dart';
import 'package:wf_grocery_pos/features/units/data/drift_unit_repository.dart';
import 'package:wf_grocery_pos/features/units/data/unit_seeder.dart';
import 'package:wf_grocery_pos/models/product.dart';
import 'package:wf_grocery_pos/models/product_combo.dart';
import 'package:wf_grocery_pos/state/category_provider.dart';
import 'package:wf_grocery_pos/state/inventory_provider.dart';
import 'package:wf_grocery_pos/state/unit_provider.dart';

Product _product(
  String id,
  String name, {
  double stock = 0,
  String? baseId,
  double unitsPerPack = 1,
  bool decimals = false,
  String unit = 'pz',
}) =>
    Product(
      id: id,
      name: name,
      categoryId: 'c',
      category: 'Cigarros',
      unitId: 'u',
      unit: unit,
      allowsDecimals: decimals,
      quantityStep: decimals ? 0.5 : 1,
      priceCents: 10,
      costCents: 6,
      stock: stock,
      createdAt: DateTime(2025),
      updatedAt: DateTime(2025),
      baseProductId: baseId,
      unitsPerPack: unitsPerPack,
      combos: const <ProductCombo>[],
    );

void main() {
  // La tabla de Inventario formatea fechas en español (la app lo hace al arrancar).
  setUpAll(() => initializeDateFormatting('es_MX'));

  group('sumar existencias en la base de datos', () {
    late AppDatabase db;
    late DriftProductRepository repo;
    late InventoryProvider provider;
    late String baseId;

    setUp(() async {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      final categories = await seedCategoriesIfEmpty(db);
      final units = await seedUnitsIfEmpty(db);
      repo = DriftProductRepository(db);
      provider = InventoryProvider(repo);
      // Se crea SIN existencias: todavía no se sabe cuánto hay.
      baseId = await repo.add(
        ProductsTableCompanion.insert(
          name: 'Cigarro suelto',
          categoryId: categories.values.first,
          unitId: units['Pieza']!,
          priceCents: 10,
          costCents: 6,
        ),
      );
      await repo.savePresentations(baseId, const [
        PresentationDraft(name: 'Cajetilla de 20', unitsPerPack: 20, priceCents: 175),
        PresentationDraft(name: 'Paquete de 20 cajetillas', unitsPerPack: 400, priceCents: 3000),
      ]);
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });

    tearDown(() async {
      provider.dispose();
      await db.close();
    });

    Future<double> poolStock() async => (await repo.getById(baseId))!.stock;
    Product byName(String name) => provider.products.firstWhere((p) => p.name == name);

    test('un producto sin existencias empieza en cero, también sus presentaciones', () async {
      expect(await poolStock(), 0);
      expect(byName('Cajetilla de 20').stock, 0);
    });

    test('agregar paquetes suma 400 unidades por paquete al pool del producto base', () async {
      final added = await provider.addStock(byName('Paquete de 20 cajetillas'), 5);
      expect(added, 2000);
      expect(await poolStock(), 2000);
    });

    test('agregar suma a lo que ya había: no lo reemplaza', () async {
      await provider.addStock(byName('Cajetilla de 20'), 10); // 200
      await provider.addStock(byName('Paquete de 20 cajetillas'), 1); // +400
      await provider.addStock(provider.products.firstWhere((p) => !p.isPresentation), 7); // +7 sueltas
      expect(await poolStock(), 607);
    });

    test('lo agregado lo ven todas las presentaciones (mismo pool)', () async {
      await provider.addStock(byName('Paquete de 20 cajetillas'), 5); // 2,000 unidades
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(byName('Cajetilla de 20').stock, 100);
      expect(byName('Paquete de 20 cajetillas').stock, 5);
    });

    test('el costo por paquete calcula el de la unidad y el de cada presentación', () async {
      // Llegan 5 paquetes que costaron $25.00 cada uno.
      await provider.addStock(byName('Paquete de 20 cajetillas'), 5, costCents: 2500);
      await Future<void>.delayed(const Duration(milliseconds: 200));

      expect(await poolStock(), 2000);
      // $25 ÷ 400 = 6.25¢ por unidad: el unitario se redondea a 6¢...
      expect(byName('Cigarro suelto').costCents, 6);
      // ...pero la cajetilla sale del valor exacto (20 × 6.25 = 125¢), no de 20 × 6.
      expect(byName('Cajetilla de 20').costCents, 125);
      expect(byName('Paquete de 20 cajetillas').costCents, 2500);
    });

    test('el costo escrito en una cajetilla se reparte entre sus unidades', () async {
      await provider.addStock(byName('Cajetilla de 20'), 10, costCents: 120); // $1.20 la cajetilla
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(byName('Cigarro suelto').costCents, 6);
      expect(byName('Cajetilla de 20').costCents, 120);
      expect(byName('Paquete de 20 cajetillas').costCents, 2400);
    });

    test('el costo escrito en la unidad es el de la unidad', () async {
      await provider.addStock(provider.products.firstWhere((p) => !p.isPresentation), 50, costCents: 8);
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(byName('Cigarro suelto').costCents, 8);
      expect(byName('Cajetilla de 20').costCents, 160);
    });

    test('sin costo, agregar inventario no toca el costo que ya había', () async {
      await provider.addStock(byName('Paquete de 20 cajetillas'), 1);
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(byName('Cigarro suelto').costCents, 6);
      expect(byName('Cajetilla de 20').costCents, 120);
    });

    test('un costo de cero o negativo se rechaza', () async {
      expect(() => repo.setCostFromPresentation(baseId, 0), throwsArgumentError);
      expect(() => repo.setCostFromPresentation(baseId, -5), throwsArgumentError);
    });

    test('no se puede agregar cero ni negativo', () async {
      expect(() => repo.addStock(baseId, 0), throwsArgumentError);
      expect(() => repo.addStock(baseId, -5), throwsArgumentError);
      expect(await poolStock(), 0);
    });

    test('la suma es atómica: varias entradas seguidas no se pierden', () async {
      await Future.wait([for (var i = 0; i < 10; i++) repo.addStock(baseId, 3)]);
      expect(await poolStock(), 30);
    });
  });

  group('cuadro "Agregar inventario"', () {
    final base = _product('cig', 'Cigarro suelto', stock: 7200);
    final box = _product('caj', 'Cajetilla de 20', baseId: 'cig', unitsPerPack: 20, stock: 360);
    final carton = _product('paq', 'Paquete de 20 cajetillas', baseId: 'cig', unitsPerPack: 400, stock: 18);

    Future<Future<StockEntry?> Function()> open(
      WidgetTester tester, {
      required Product from,
      Product? baseProduct,
      List<Product>? presentations,
    }) async {
      StockEntry? result;
      var done = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () async {
                  result = await showAddStockDialog(
                    context,
                    product: from,
                    base: baseProduct ?? base,
                    presentations: presentations ?? [box, carton],
                  );
                  done = true;
                },
                child: const Text('abrir'),
              ),
            ),
          ),
        ),
      );
      return () async {
        await tester.pump();
        return done ? result : null;
      };
    }

    bool selected(WidgetTester tester, String label) =>
        tester.widget<ChoiceChip>(find.widgetWithText(ChoiceChip, label)).selected;

    Future<void> show(WidgetTester tester) async {
      await tester.tap(find.text('abrir'));
      await tester.pumpAndSettle();
    }

    testWidgets('desde una cajetilla se esperan cajetillas', (tester) async {
      final result = await open(tester, from: box);
      await tester.pumpAndSettle();
      await show(tester);

      expect(selected(tester, 'Cajetilla de 20'), isTrue);
      expect(selected(tester, 'Unidades (pz)'), isFalse);
      expect(selected(tester, 'Paquete de 20 cajetillas'), isFalse);
      expect(find.text('Cantidad de cajetilla de 20'), findsOneWidget);
      expect(find.text('Cada una trae 20 pz'), findsOneWidget);

      await tester.enterText(find.byType(TextFormField).first, '5');
      await tester.pump();
      expect(find.text('Se agregan 100 pz'), findsOneWidget);
      expect(find.text('Hay 7200 pz → quedarán 7300 pz'), findsOneWidget);

      await tester.tap(find.text('Agregar'));
      await tester.pumpAndSettle();
      final entry = (await result())!;
      expect(entry.target.id, 'caj');
      expect(entry.quantity, 5);
    });

    testWidgets('desde un paquete se esperan paquetes', (tester) async {
      final result = await open(tester, from: carton);
      await tester.pumpAndSettle();
      await show(tester);

      expect(selected(tester, 'Paquete de 20 cajetillas'), isTrue);
      await tester.enterText(find.byType(TextFormField).first, '5');
      await tester.pump();
      expect(find.text('Se agregan 2000 pz'), findsOneWidget);
      expect(find.text('Hay 7200 pz → quedarán 9200 pz'), findsOneWidget);

      await tester.tap(find.text('Agregar'));
      await tester.pumpAndSettle();
      final entry = (await result())!;
      expect(entry.target.id, 'paq');
      expect(entry.quantity, 5);
    });

    testWidgets('desde la unidad se esperan unidades', (tester) async {
      final result = await open(tester, from: base);
      await tester.pumpAndSettle();
      await show(tester);

      expect(selected(tester, 'Unidades (pz)'), isTrue);
      await tester.enterText(find.byType(TextFormField).first, '12');
      await tester.pump();
      expect(find.text('Hay 7200 pz → quedarán 7212 pz'), findsOneWidget);
      expect(find.textContaining('Se agregan'), findsNothing); // ya son unidades

      await tester.tap(find.text('Agregar'));
      await tester.pumpAndSettle();
      expect((await result())!.target.id, 'cig');
    });

    testWidgets('se puede cambiar la presentación elegida antes de agregar', (tester) async {
      final result = await open(tester, from: box);
      await tester.pumpAndSettle();
      await show(tester);

      await tester.tap(find.widgetWithText(ChoiceChip, 'Paquete de 20 cajetillas'));
      await tester.pump();
      expect(find.text('Cada una trae 400 pz'), findsOneWidget);
      await tester.enterText(find.byType(TextFormField).first, '2');
      await tester.pump();
      expect(find.text('Hay 7200 pz → quedarán 8000 pz'), findsOneWidget);

      await tester.tap(find.text('Agregar'));
      await tester.pumpAndSettle();
      expect((await result())!.target.id, 'paq');
    });

    testWidgets('un producto sin existencias y sin presentaciones también se puede abastecer', (tester) async {
      final solo = _product('sol', 'Cigarro');
      final result = await open(tester, from: solo, baseProduct: solo, presentations: const []);
      await tester.pumpAndSettle();
      await show(tester);

      expect(find.byType(ChoiceChip), findsNothing); // sin presentaciones no hay nada que elegir
      expect(find.text('Hay ahora: 0 pz'), findsOneWidget);
      await tester.enterText(find.byType(TextFormField).first, '50');
      await tester.tap(find.text('Agregar'));
      await tester.pumpAndSettle();
      expect((await result())!.quantity, 50);
    });

    testWidgets('el costo es opcional: si no se escribe, no se pide actualizar nada', (tester) async {
      final result = await open(tester, from: carton);
      await tester.pumpAndSettle();
      await show(tester);

      expect(find.text('Costo por paquete de 20 cajetillas (opcional)'), findsOneWidget);
      await tester.enterText(find.byType(TextFormField).first, '5');
      await tester.tap(find.text('Agregar'));
      await tester.pumpAndSettle();
      expect((await result())!.costCents, isNull);
    });

    testWidgets('con el costo del paquete muestra el costo exacto de cada unidad y lo devuelve', (tester) async {
      final result = await open(tester, from: carton);
      await tester.pumpAndSettle();
      await show(tester);

      await tester.enterText(find.byType(TextFormField).first, '5');
      await tester.enterText(find.byType(TextFormField).at(1), '25');
      await tester.pump();
      expect(find.text('Costo por pz: \$0.0625'), findsOneWidget); // 25 ÷ 400

      await tester.tap(find.text('Agregar'));
      await tester.pumpAndSettle();
      final entry = (await result())!;
      expect(entry.costCents, 2500);
      expect(entry.quantity, 5);
    });

    testWidgets('el costo por unidad cambia al elegir otra presentación', (tester) async {
      await open(tester, from: carton);
      await tester.pumpAndSettle();
      await show(tester);

      await tester.enterText(find.byType(TextFormField).at(1), '1.20');
      await tester.pump();
      expect(find.text('Costo por pz: \$0.003'), findsOneWidget); // 1.20 ÷ 400
      // El cuadro se desplazó hacia abajo al escribir el costo: se vuelve a las presentaciones.
      await tester.ensureVisible(find.widgetWithText(ChoiceChip, 'Cajetilla de 20'));
      await tester.tap(find.widgetWithText(ChoiceChip, 'Cajetilla de 20'));
      await tester.pump();
      expect(find.text('Costo por pz: \$0.06'), findsOneWidget); // 1.20 ÷ 20
    });

    testWidgets('un costo de cero no se acepta', (tester) async {
      final result = await open(tester, from: box);
      await tester.pumpAndSettle();
      await show(tester);

      await tester.enterText(find.byType(TextFormField).first, '5');
      await tester.enterText(find.byType(TextFormField).at(1), '0');
      await tester.tap(find.text('Agregar'));
      await tester.pump();
      expect(find.text('Ingresa un costo mayor a cero'), findsOneWidget);
      expect(await result(), isNull);
    });

    testWidgets('no acepta cantidades vacías, cero, ni decimales en una presentación', (tester) async {
      final result = await open(tester, from: box);
      await tester.pumpAndSettle();
      await show(tester);

      await tester.tap(find.text('Agregar'));
      await tester.pump();
      expect(find.text('Ingresa una cantidad mayor a cero'), findsOneWidget);

      await tester.enterText(find.byType(TextFormField).first, '0');
      await tester.tap(find.text('Agregar'));
      await tester.pump();
      expect(find.text('Ingresa una cantidad mayor a cero'), findsOneWidget);

      // El punto decimal ni siquiera se puede escribir en una cajetilla.
      await tester.enterText(find.byType(TextFormField).first, '2.5');
      await tester.pump();
      expect(tester.widget<TextFormField>(find.byType(TextFormField).first).controller!.text, '25');
      expect(await result(), isNull);
    });

    testWidgets('una unidad por peso (libras) sí admite decimales', (tester) async {
      final papa = _product('papa', 'Papa', decimals: true, unit: 'lb', stock: 10);
      final result = await open(tester, from: papa, baseProduct: papa, presentations: const []);
      await tester.pumpAndSettle();
      await show(tester);

      await tester.enterText(find.byType(TextFormField).first, '2.5');
      await tester.pump();
      expect(find.text('Hay 10 lb → quedarán 12.5 lb'), findsOneWidget);
      await tester.tap(find.text('Agregar'));
      await tester.pumpAndSettle();
      expect((await result())!.quantity, 2.5);
    });
  });

  group('flujo completo desde la pantalla de Inventario', () {
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

    testWidgets('cada fila pregunta por su presentación y el inventario se SUMA al producto base', (tester) async {
      ignoreOverflow();
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      late final String baseId;
      await tester.runAsync(() async {
        final categories = await seedCategoriesIfEmpty(db);
        final units = await seedUnitsIfEmpty(db);
        final repo = DriftProductRepository(db);
        baseId = await repo.add(
          ProductsTableCompanion.insert(
            name: 'Cigarro suelto',
            categoryId: categories.values.first,
            unitId: units['Pieza']!,
            priceCents: 10,
            costCents: 6,
            stock: const Value(0),
          ),
        );
        await repo.savePresentations(baseId, const [
          PresentationDraft(name: 'Cajetilla de 20', unitsPerPack: 20, priceCents: 175),
          PresentationDraft(name: 'Paquete de 20 cajetillas', unitsPerPack: 400, priceCents: 3000),
        ]);
      });

      await tester.binding.setSurfaceSize(const Size(1500, 1000));
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

      // Las filas salen ordenadas por nombre: Cajetilla, Cigarro y Paquete.
      expect(find.byTooltip('Agregar inventario'), findsNWidgets(3));
      expect(find.byTooltip('Agregar presentación'), findsOneWidget); // solo el producto base

      Future<double> poolStock() async {
        final row = await tester.runAsync(
          () => (db.select(db.productsTable)..where((r) => r.id.equals(baseId))).getSingle(),
        );
        return row!.stock;
      }

      // 1) Desde la fila de la CAJETILLA: se esperan cajetillas. Llegan 5 = 100 unidades.
      await tester.tap(find.byTooltip('Agregar inventario').at(0));
      await tester.pumpAndSettle();
      expect(tester.widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'Cajetilla de 20')).selected, isTrue);
      await tester.enterText(find.byType(TextFormField).first, '5');
      await tester.pump();
      await tester.tap(find.text('Agregar'));
      await settle(tester);
      expect(await poolStock(), 100);

      // 2) Desde la fila del PAQUETE: se esperan paquetes. Llegan 5 = 2,000 unidades más.
      await tester.tap(find.byTooltip('Agregar inventario').at(2));
      await tester.pumpAndSettle();
      expect(tester.widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'Paquete de 20 cajetillas')).selected, isTrue);
      await tester.enterText(find.byType(TextFormField).first, '5');
      await tester.pump();
      expect(find.text('Hay 100 pz → quedarán 2100 pz'), findsOneWidget);
      // Cada paquete costó $25: el costo de las unidades y cajetillas sale solo.
      await tester.enterText(find.byType(TextFormField).at(1), '25');
      await tester.pump();
      await tester.tap(find.text('Agregar'));
      await settle(tester);
      expect(await poolStock(), 2100);
      final costs = await tester.runAsync(() async {
        final rows = await db.select(db.productsTable).get();
        return {for (final r in rows) r.name: r.costCents};
      });
      expect(costs!['Cigarro suelto'], 6); // 25 ÷ 400 = 6.25¢
      expect(costs['Cajetilla de 20'], 125);
      expect(costs['Paquete de 20 cajetillas'], 2500);

      // 3) Desde la fila de la UNIDAD (producto base): se esperan unidades.
      await tester.tap(find.byTooltip('Agregar inventario').at(1));
      await tester.pumpAndSettle();
      expect(tester.widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'Unidades (pz)')).selected, isTrue);
      await tester.enterText(find.byType(TextFormField).first, '30');
      await tester.pump();
      await tester.tap(find.text('Agregar'));
      await settle(tester);
      expect(await poolStock(), 2130);

      await teardown(tester);
    });
  });
}
