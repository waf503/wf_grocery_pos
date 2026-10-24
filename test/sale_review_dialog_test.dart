import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:wf_grocery_pos/features/pos/widgets/checkout_dialog.dart';
import 'package:wf_grocery_pos/features/pos/widgets/sale_review_dialog.dart';
import 'package:wf_grocery_pos/models/cart_item.dart';
import 'package:wf_grocery_pos/models/product.dart';
import 'package:wf_grocery_pos/models/product_combo.dart';
import 'package:wf_grocery_pos/models/sale.dart';

Product _product(String name, int priceCents, {bool decimals = false, String unit = 'pz', List<ProductCombo> combos = const []}) =>
    Product(
      id: name,
      name: name,
      categoryId: 'c',
      category: 'c',
      unitId: 'u',
      unit: unit,
      allowsDecimals: decimals,
      priceCents: priceCents,
      costCents: 1,
      stock: 100,
      createdAt: DateTime(2025),
      updatedAt: DateTime(2025),
      combos: combos,
    );

void main() {
  Future<SaleReviewDecision Function()> open(
    WidgetTester tester, {
    required List<CartItem> items,
    required PaymentChoice payment,
    String? customerName,
  }) async {
    SaleReviewDecision? decision;
    await tester.binding.setSurfaceSize(const Size(900, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                decision = await showSaleReviewDialog(
                  context,
                  items: items,
                  totalCents: items.fold(0, (s, i) => s + i.subtotalCents),
                  payment: payment,
                  customerName: customerName,
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
    return () => decision!;
  }

  testWidgets('pago en efectivo: muestra lo recibido y el vuelto a entregar', (tester) async {
    await open(
      tester,
      items: [CartItem(product: _product('Agua', 15), quantity: 3), CartItem(product: _product('Pan', 50), quantity: 1)],
      payment: (method: PaymentMethod.cash, tenderedCents: 500),
    );
    expect(find.text('Total (4 artículos)'), findsOneWidget);
    expect(find.text(r'$0.95'), findsOneWidget); // 3 × 0.15 + 0.50
    expect(find.text('Recibido'), findsOneWidget);
    expect(find.text(r'$5.00'), findsOneWidget);
    expect(find.text('Vuelto a entregar'), findsOneWidget);
    expect(find.text(r'$4.05'), findsOneWidget);
    expect(find.text('Corregir pago'), findsOneWidget);
  });

  testWidgets('pago exacto (sin monto escrito): sin vuelto', (tester) async {
    await open(
      tester,
      items: [CartItem(product: _product('Agua', 15), quantity: 2)],
      payment: (method: PaymentMethod.cash, tenderedCents: null),
    );
    expect(find.text('Pago exacto'), findsOneWidget);
    expect(find.text('Vuelto a entregar'), findsNothing);
    expect(find.text(r'$0.30'), findsWidgets); // renglón y total
  });

  testWidgets('el combo aplicado se ve en el ticket con lo que ahorra el cliente', (tester) async {
    await open(
      tester,
      items: [
        CartItem(
          product: _product('Bolsa de agua', 15, combos: const [ProductCombo(quantity: 2, priceCents: 25)]),
          quantity: 4,
        ),
      ],
      payment: (method: PaymentMethod.cash, tenderedCents: null),
    );
    expect(find.text(r'$0.15 c/u · combo: ahorra $0.10'), findsOneWidget);
    expect(find.text('Ahorro por combos'), findsOneWidget);
    expect(find.text(r'$0.50'), findsWidgets); // 2 combos de 25¢
  });

  testWidgets('productos por peso muestran la unidad en la cantidad', (tester) async {
    await open(
      tester,
      items: [CartItem(product: _product('Papa', 49, decimals: true, unit: 'lb'), quantity: 2.5)],
      payment: (method: PaymentMethod.cash, tenderedCents: null),
    );
    expect(find.text('2.5 lb ×'), findsOneWidget);
  });

  testWidgets('fiado: muestra el cliente y avisa que no entra dinero a la caja', (tester) async {
    await open(
      tester,
      items: [CartItem(product: _product('Arroz', 325), quantity: 1)],
      payment: (method: PaymentMethod.credit, tenderedCents: null),
      customerName: 'Doña Carmen',
    );
    expect(find.text('Cliente'), findsOneWidget);
    expect(find.text('Doña Carmen'), findsOneWidget);
    expect(find.textContaining('no entra dinero a la caja'), findsOneWidget);
    expect(find.text('Recibido'), findsNothing);
    expect(find.text('Volver'), findsOneWidget); // sin efectivo no hay "pago" que corregir
  });

  testWidgets('cada botón devuelve su decisión', (tester) async {
    final items = [CartItem(product: _product('Agua', 15), quantity: 1)];
    const cash = (method: PaymentMethod.cash, tenderedCents: 100);

    var decision = await open(tester, items: items, payment: cash);
    await tester.tap(find.text('Confirmar venta'));
    await tester.pumpAndSettle();
    expect(decision(), SaleReviewDecision.confirm);

    decision = await open(tester, items: items, payment: cash);
    await tester.tap(find.text('Corregir pago'));
    await tester.pumpAndSettle();
    expect(decision(), SaleReviewDecision.back);

    decision = await open(tester, items: items, payment: cash);
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();
    expect(decision(), SaleReviewDecision.cancel);
  });

  testWidgets('con muchos productos el ticket se desplaza y los botones siguen visibles', (tester) async {
    await open(
      tester,
      items: [for (var i = 0; i < 40; i++) CartItem(product: _product('Producto $i', 10 + i), quantity: 1)],
      payment: (method: PaymentMethod.cash, tenderedCents: 10000),
    );
    expect(find.text('Confirmar venta'), findsOneWidget);
    expect(find.text('Total (40 artículos)'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
