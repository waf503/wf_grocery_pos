import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import 'package:wf_grocery_pos/features/inventory/widgets/presentations_editor.dart';
import 'package:wf_grocery_pos/features/inventory/widgets/product_form_dialog.dart';
import 'package:wf_grocery_pos/models/category.dart';
import 'package:wf_grocery_pos/models/product_combo.dart';
import 'package:wf_grocery_pos/models/unit.dart';

void main() {
  group('lista de presentaciones: la relación va en las dos direcciones', () {
    PresentationEntry entry(
      String name,
      String count,
      String price, {
      int ofIndex = -1,
      bool inside = false,
      int? fixed,
    }) =>
        PresentationEntry(name: name, count: count, price: price, ofIndex: ofIndex, inside: inside, fixedPoolUnits: fixed);

    PresentationsController build(List<PresentationEntry> entries, {int rootFactor = 1}) {
      final controller = PresentationsController(entries, currentRootFactor: rootFactor);
      addTearDown(controller.dispose);
      return controller;
    }

    test('de menor a mayor: la cajetilla contiene 20 y el paquete contiene 20 cajetillas', () {
      final controller = build([
        entry('Cajetilla', '20', '1.75'),
        entry('Paquete', '20', '30', ofIndex: 0),
      ]);

      final layout = controller.computeLayout().layout!;
      expect(layout.rootUnitsPerPack, 1); // el base es la unidad más pequeña
      expect(layout.unitsPerEntry, [20, 400]);
      expect(layout.stockScale, 1);

      final drafts = controller.buildDrafts(layout)!;
      expect(drafts.map((d) => d.unitsPerPack), [20, 400]);
      expect(drafts.map((d) => d.priceCents), [175, 3000]);
      expect(drafts.first.barcode, isNull);
      expect(drafts.first.costCents, isNull); // se calcula con el costo del base
    });

    test('de mayor a menor: el base es el PAQUETE y el cigarro suelto viene dentro (200 por paquete)', () {
      final controller = build([entry('Cigarro suelto', '200', '0.15', inside: true)]);

      final layout = controller.computeLayout().layout!;
      expect(layout.rootUnitsPerPack, 200); // el paquete vale 200 cigarros
      expect(layout.unitsPerEntry, [1]); // el cigarro es la unidad mínima
      expect(layout.stockScale, 200); // lo que hubiera en paquetes ahora son cigarros
    });

    test('de mayor a menor en cadena: paquete → cajetillas → cigarros', () {
      final controller = build([
        entry('Cajetilla', '10', '1.75', inside: true), // 10 cajetillas por paquete
        entry('Cigarro suelto', '20', '0.10', inside: true, ofIndex: 0), // 20 cigarros por cajetilla
      ]);

      final layout = controller.computeLayout().layout!;
      expect(layout.rootUnitsPerPack, 200);
      expect(layout.unitsPerEntry, [20, 1]);
    });

    test('direcciones mezcladas: el base es la cajetilla, hay cigarros dentro y paquetes que la contienen', () {
      final controller = build([
        entry('Cigarro suelto', '20', '0.10', inside: true),
        entry('Paquete', '10', '16', ofIndex: -1), // contiene 10 cajetillas
      ]);

      final layout = controller.computeLayout().layout!;
      expect(layout.rootUnitsPerPack, 20);
      expect(layout.unitsPerEntry, [1, 200]);
    });

    test('si el base ya valía 200, repetir lo mismo no cambia nada (no reescala las existencias)', () {
      final controller = build([entry('Cigarro suelto', '200', '0.15', inside: true)], rootFactor: 200);
      final layout = controller.computeLayout().layout!;
      expect(layout.rootUnitsPerPack, 200);
      expect(layout.stockScale, 1);
    });

    test('quitar todas las presentaciones devuelve el base a valer 1 y reduce las existencias', () {
      final controller = build(const [], rootFactor: 200);
      final layout = controller.computeLayout().layout!;
      expect(layout.rootUnitsPerPack, 1);
      expect(layout.stockScale, 1 / 200);
    });

    test('cantidades que no cuadran (1/3 y 1/2 del base) dan un error claro en vez de guardar mal', () {
      final controller = build([
        entry('Tercio', '3', '1', inside: true),
        entry('Mitad', '2', '1', inside: true),
      ]);
      final result = controller.computeLayout();
      expect(result.layout, isNull);
      expect(result.error, contains('Mitad'));
    });

    test('una medida antigua que no cuadra con el base se avisa en vez de corromper las existencias', () {
      // El base vale 200 y hay una presentación de 12: 12 no divide a 200 ni al revés.
      final controller = build([entry('Docena', '', '2', fixed: 12)], rootFactor: 200);
      expect(controller.computeLayout().layout, isNull);
      expect(controller.computeLayout().error, isNotNull);
    });

    test('datos incompletos: no hay layout pero tampoco error', () {
      final controller = build([
        entry('Cajetilla', '', '1.75'),
        entry('Paquete', '20', '30', ofIndex: 0),
      ]);
      final result = controller.computeLayout();
      expect(result.layout, isNull);
      expect(result.error, isNull);
    });

    test('con nombre o precio vacío no se pueden armar las presentaciones', () {
      final noName = build([entry('', '20', '1.75')]);
      expect(noName.buildDrafts(noName.computeLayout().layout!), isNull);

      final noPrice = build([entry('Cajetilla', '20', '')]);
      expect(noPrice.buildDrafts(noPrice.computeLayout().layout!), isNull);
    });

    test('quitar una presentación reacomoda las que se relacionaban con ella', () {
      final controller = build([
        entry('Cajetilla', '20', '1.75'),
        entry('Paquete', '20', '30', ofIndex: 0),
        entry('Caja', '5', '120', ofIndex: 1),
      ]);

      controller.removeAt(0);
      // "Paquete" contaba de la cajetilla borrada: vuelve a contar del producto base.
      expect(controller.entries.map((e) => e.name.text), ['Paquete', 'Caja']);
      expect(controller.entries[0].ofIndex, -1);
      // "Caja" contaba del paquete (que ahora es el índice 0).
      expect(controller.entries[1].ofIndex, 0);
      expect(controller.computeLayout().layout!.unitsPerEntry, [20, 100]);
    });

    test('conserva el costo fijado a mano y las promociones de cada presentación', () {
      final controller = build([
        PresentationEntry(
          id: 'p9',
          name: 'Cajetilla',
          count: '20',
          price: '1.75',
          combos: const [ProductCombo(quantity: 2, priceCents: 330)],
          explicitCostCents: 110,
        ),
      ]);

      final draft = controller.buildDrafts(controller.computeLayout().layout!)!.single;
      expect(draft.id, 'p9');
      expect(draft.costCents, 110);
      expect(draft.combos, const [ProductCombo(quantity: 2, priceCents: 330)]);
    });
  });

  group('formulario de producto con presentaciones y combos', () {
    final units = [Unit(id: 'u1', name: 'Pieza', abbreviation: 'pz')];
    final categories = [Category(id: 'c1', name: 'Cigarros')];

    Future<void> open(
      WidgetTester tester,
      void Function(ProductFormResult?) onClosed, {
      Future<Uint8List?> Function()? pickImageFile,
    }) async {
      await tester.binding.setSurfaceSize(const Size(1000, 2200));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () async {
                  onClosed(
                    await showProductFormDialog(
                      context,
                      categories: categories,
                      units: units,
                      suggestionsFor: (_) => const [],
                      generateBarcode: () => '2000000000017',
                      isBarcodeTaken: (code, {exceptId}) => code == '7500000000000',
                      pickImageFile: pickImageFile,
                    ),
                  );
                },
                child: const Text('abrir'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('abrir'));
      await tester.pumpAndSettle();
    }

    Finder field(String label) => find.widgetWithText(TextFormField, label);

    Future<void> type(WidgetTester tester, Finder finder, String text) async {
      await tester.ensureVisible(finder);
      await tester.enterText(finder, text);
      await tester.pump();
    }

    Future<void> tapText(WidgetTester tester, String text, {int index = 0}) async {
      final finder = find.text(text).at(index);
      await tester.ensureVisible(finder);
      await tester.tap(finder);
      await tester.pumpAndSettle();
    }

    testWidgets('un producto con cajetilla y paquete se crea SIN existencias (aún no se sabe cuánto hay)', (tester) async {
      ProductFormResult? result;
      await open(tester, (r) => result = r);

      await type(tester, field('Nombre del producto'), 'Cigarro suelto');
      await type(tester, field('Precio de venta'), '0.10');
      await type(tester, field('Costo (opcional)'), '0.06');
      await tapText(tester, 'Selecciona'); // la unidad no viene elegida
      await tapText(tester, 'Pieza');

      // Presentaciones: cajetilla (20 unidades) y paquete (20 cajetillas).
      await tapText(tester, 'Presentaciones (cajetilla, paquete...)');
      await tapText(tester, 'Agregar presentación');
      await type(tester, field('Nombre de la presentación').at(0), 'Cajetilla de 20');
      await type(tester, field('Contiene').at(0), '20');
      await type(tester, field('Precio de venta').at(1), '1.75');

      await tapText(tester, 'Agregar presentación');
      await type(tester, field('Nombre de la presentación').at(1), 'Paquete de 20 cajetillas');
      await type(tester, field('Contiene').at(1), '20');
      await tester.ensureVisible(find.byType(DropdownButtonFormField<int>).at(1));
      await tester.tap(find.byType(DropdownButtonFormField<int>).at(1));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cajetilla de 20').last);
      await tester.pumpAndSettle();
      await type(tester, field('Precio de venta').at(2), '30');

      // Se ve el total en unidades que resulta de la cuenta.
      expect(find.textContaining('Equivale a 400 unidades mínimas'), findsOneWidget);

      // Las existencias se pueden dejar vacías: se agregan después con
      // "Agregar inventario". Con presentaciones se llevan en unidades.
      expect(find.widgetWithText(TextFormField, 'Existencias (en unidades)'), findsOneWidget);
      expect(find.byTooltip('Calcular existencias'), findsNothing);

      // Promoción del producto: 3 por $0.25.
      await tapText(tester, 'Promoción');
      await tester.enterText(find.widgetWithText(TextFormField, 'Cantidad que lleva el combo'), '3');
      await tester.enterText(find.widgetWithText(TextFormField, 'Precio de TODO el combo'), '0.25');
      await tester.pump();
      await tester.tap(find.text('Agregar'));
      await tester.pumpAndSettle();
      expect(find.text('3 por \$0.25'), findsOneWidget);

      await tapText(tester, 'Guardar');

      final saved = result!;
      expect(saved.name, 'Cigarro suelto');
      expect(saved.priceCents, 10);
      expect(saved.costCents, 6);
      expect(saved.stock, 0); // vacío = en cero
      expect(saved.combos, const [ProductCombo(quantity: 3, priceCents: 25)]);
      expect(saved.presentations, hasLength(2));
      expect(saved.presentations[0].name, 'Cajetilla de 20');
      expect(saved.presentations[0].unitsPerPack, 20);
      expect(saved.presentations[0].priceCents, 175);
      expect(saved.presentations[1].unitsPerPack, 400);
      expect(saved.presentations[1].priceCents, 3000);
    });

    testWidgets('el costo es opcional: sin escribirlo el producto se guarda con costo cero', (tester) async {
      ProductFormResult? result;
      await open(tester, (r) => result = r);

      await type(tester, field('Nombre del producto'), 'Cigarro suelto');
      await type(tester, field('Precio de venta'), '0.10');
      await tapText(tester, 'Selecciona');
      await tapText(tester, 'Pieza');
      await tapText(tester, 'Guardar');

      expect(result, isNotNull);
      expect(result!.costCents, 0);
      expect(result!.stock, 0);
    });

    testWidgets('no deja guardar si falta elegir la unidad', (tester) async {
      ProductFormResult? result;
      var closed = false;
      await open(tester, (r) {
        result = r;
        closed = true;
      });

      await type(tester, field('Nombre del producto'), 'Cigarro suelto');
      await type(tester, field('Precio de venta'), '0.10');
      await type(tester, field('Costo (opcional)'), '0.06');
      await tapText(tester, 'Guardar');

      expect(closed, isFalse);
      expect(result, isNull);
      expect(find.text('Requerido'), findsWidgets);
    });

    testWidgets('con una presentación incompleta abre la lista y avisa en vez de guardar', (tester) async {
      var closed = false;
      await open(tester, (_) => closed = true);

      await type(tester, field('Nombre del producto'), 'Cigarro suelto');
      await type(tester, field('Precio de venta'), '0.10');
      await type(tester, field('Costo (opcional)'), '0.06');
      await tapText(tester, 'Selecciona');
      await tapText(tester, 'Pieza');

      await tapText(tester, 'Presentaciones (cajetilla, paquete...)');
      await tapText(tester, 'Agregar presentación');
      // Se cierra la lista sin completar la presentación y se intenta guardar.
      await tapText(tester, 'Presentaciones (1)');
      expect(find.text('Agregar presentación'), findsNothing);
      await tapText(tester, 'Guardar');

      expect(closed, isFalse);
      // Se vuelve a abrir la lista para mostrar los campos que faltan.
      expect(find.text('Agregar presentación'), findsOneWidget);
      expect(find.text('Requerido'), findsWidgets);
    });

    testWidgets('el código de barras de una presentación no puede ser uno ya usado', (tester) async {
      await open(tester, (_) {});

      await type(tester, field('Nombre del producto'), 'Cigarro suelto');
      await tapText(tester, 'Presentaciones (cajetilla, paquete...)');
      await tapText(tester, 'Agregar presentación');
      await type(tester, find.widgetWithText(TextFormField, 'Código de barras (opcional)').at(1), '7500000000000');
      await tapText(tester, 'Guardar');

      expect(find.text('Este código ya pertenece a otro producto'), findsOneWidget);
    });

    group('subir una imagen del disco', () {
      /// Una "foto" de 800 x 400 en PNG, como la que elegiría el usuario.
      Uint8List photoFile() {
        final image = img.Image(width: 800, height: 400);
        for (final pixel in image) {
          pixel
            ..r = pixel.x % 256
            ..g = pixel.y % 256
            ..b = 120;
        }
        return Uint8List.fromList(img.encodePng(image));
      }

      /// La imagen se procesa en otro hilo: se espera a que termine.
      Future<void> waitForImage(WidgetTester tester) async {
        for (var i = 0; i < 10; i++) {
          await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 150)));
          await tester.pump();
        }
      }

      Future<void> fillRequired(WidgetTester tester) async {
        await type(tester, field('Nombre del producto'), 'Galleta Oreo');
        await type(tester, field('Precio de venta'), '0.35');
        await tapText(tester, 'Selecciona');
        await tapText(tester, 'Pieza');
      }

      testWidgets('la imagen elegida se recorta a cuadrado, se reduce y se guarda con el producto', (tester) async {
        ProductFormResult? result;
        await open(tester, (r) => result = r, pickImageFile: () async => photoFile());
        await fillRequired(tester);
        expect(find.text('Quitar'), findsNothing);

        await tapText(tester, 'Subir imagen');
        await waitForImage(tester);
        expect(find.text('Quitar'), findsOneWidget);
        expect(find.byType(Image), findsOneWidget); // la vista previa

        await tapText(tester, 'Guardar');
        final saved = result!;
        expect(saved.imageChanged, isTrue);
        final decoded = img.decodeJpg(saved.image!)!;
        expect((decoded.width, decoded.height), (300, 300)); // cuadrada, de 800x400
        expect(saved.image!.length, lessThan(100 * 1024));
      });

      testWidgets('si el usuario cancela el selector, no pasa nada', (tester) async {
        await open(tester, (_) {}, pickImageFile: () async => null);
        await tapText(tester, 'Subir imagen');
        await waitForImage(tester);
        expect(find.text('Quitar'), findsNothing);
        expect(find.byType(Image), findsNothing);
      });

      testWidgets('un archivo que no es una imagen avisa y no cambia nada', (tester) async {
        await open(tester, (_) {}, pickImageFile: () async => Uint8List.fromList([1, 2, 3, 4, 5]));
        await tapText(tester, 'Subir imagen');
        await waitForImage(tester);

        expect(find.text('No se pudo usar esa imagen'), findsOneWidget);
        expect(find.text('Quitar'), findsNothing);
        await tester.pump(const Duration(seconds: 5)); // deja terminar el aviso
      });

      testWidgets('una imagen demasiado pesada avisa igual', (tester) async {
        await open(tester, (_) {}, pickImageFile: () async => throw const FormatException('La imagen pesa demasiado.'));
        await tapText(tester, 'Subir imagen');
        await waitForImage(tester);

        expect(find.text('No se pudo usar esa imagen'), findsOneWidget);
        await tester.pump(const Duration(seconds: 5));
      });

      testWidgets('se puede quitar la imagen subida y volver a elegir otra', (tester) async {
        ProductFormResult? result;
        await open(tester, (r) => result = r, pickImageFile: () async => photoFile());
        await fillRequired(tester);

        await tapText(tester, 'Subir imagen');
        await waitForImage(tester);
        await tapText(tester, 'Quitar');
        expect(find.byType(Image), findsNothing);

        await tapText(tester, 'Subir imagen');
        await waitForImage(tester);
        expect(find.byType(Image), findsOneWidget);

        await tapText(tester, 'Guardar');
        expect(result!.image, isNotNull);
      });
    });
  });
}
