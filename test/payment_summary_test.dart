import 'package:flutter_test/flutter_test.dart';

import 'package:wf_grocery_pos/features/cash/widgets/session_sales_list.dart';
import 'package:wf_grocery_pos/models/sale.dart';

Sale _sale(int number, PaymentMethod method, int totalCents, {bool voided = false}) => Sale(
      id: 'v$number',
      number: number,
      date: DateTime(2025, 1, 1),
      items: const [],
      totalCents: totalCents,
      paymentMethod: method,
      status: voided ? SaleStatus.voided : SaleStatus.completed,
    );

void main() {
  test('totales por método de pago: ignoran anuladas y siempre traen los tres métodos', () {
    final totals = totalsByPaymentMethod([
      _sale(1, PaymentMethod.cash, 500),
      _sale(2, PaymentMethod.cash, 250),
      _sale(3, PaymentMethod.card, 900, voided: true),
      _sale(4, PaymentMethod.credit, 1000),
    ]);

    expect(totals.keys, PaymentMethod.values);
    expect(totals[PaymentMethod.cash], (count: 2, totalCents: 750));
    expect(totals[PaymentMethod.card], (count: 0, totalCents: 0));
    expect(totals[PaymentMethod.credit], (count: 1, totalCents: 1000));
  });

  test('el pago electrónico se muestra con su nombre de categoría y está deshabilitado', () {
    expect(PaymentMethod.card.label, 'Pago electrónico');
    expect(PaymentMethod.card.isAvailable, isFalse);
    expect(PaymentMethod.cash.isAvailable, isTrue);
    expect(PaymentMethod.credit.isAvailable, isTrue);
  });
}
