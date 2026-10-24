import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:wf_grocery_pos/features/pos/widgets/product_tile.dart';
import 'package:wf_grocery_pos/models/product.dart';

Product _product(String name, {double stock = 50}) => Product(
      id: 'p',
      name: name,
      categoryId: 'c',
      category: 'Golosinas',
      unitId: 'u',
      unit: 'U.',
      priceCents: 35,
      costCents: 20,
      stock: stock,
      createdAt: DateTime(2025),
      updatedAt: DateTime(2025),
    );

void main() {
  // La cuadrícula del POS usa columnas de hasta 200 px y relación 0.82:
  // la tarjeta debe caber (sin overflow) en cualquier ancho razonable.
  for (final width in [130.0, 150.0, 180.0, 200.0]) {
    testWidgets('la tarjeta no se desborda con columnas de $width px', (tester) async {
      for (final product in [
        _product('Galleta Oreo 54 g'),
        _product('Jalapeños Diana Max Temporada Edición Especial 150 g con nombre muy largo'),
        _product('Agotado', stock: 0),
      ]) {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Center(
                child: SizedBox(
                  width: width,
                  height: width / 0.82,
                  child: ProductTile(product: product, onTap: () {}, categoryColor: Colors.red),
                ),
              ),
            ),
          ),
        );
        expect(tester.takeException(), isNull);
        expect(find.byType(ProductTile), findsOneWidget);
      }
    });
  }

  testWidgets('un producto agotado muestra "Agotado" y no responde al toque', (tester) async {
    var taps = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 200,
            height: 244,
            child: ProductTile(product: _product('Galleta', stock: 0), onTap: () => taps++, categoryColor: Colors.red),
          ),
        ),
      ),
    );
    expect(find.text('Agotado'), findsOneWidget);
    await tester.tap(find.byType(ProductTile));
    expect(taps, 0);
  });
}
