enum PaymentMethod { cash, card, credit }

extension PaymentMethodLabel on PaymentMethod {
  String get label {
    switch (this) {
      case PaymentMethod.cash:
        return 'Efectivo';
      case PaymentMethod.card:
        return 'Tarjeta';
      case PaymentMethod.credit:
        return 'Fiado';
    }
  }
}

class SaleItem {
  SaleItem({
    required this.productName,
    required this.quantity,
    required this.unitPrice,
  });

  final String productName;
  final int quantity;
  final double unitPrice;

  double get subtotal => quantity * unitPrice;
}

class Sale {
  Sale({
    required this.id,
    required this.date,
    required this.items,
    required this.total,
    required this.paymentMethod,
    this.customerName,
  });

  final String id;
  final DateTime date;
  final List<SaleItem> items;
  final double total;
  final PaymentMethod paymentMethod;
  final String? customerName;

  int get itemCount => items.fold(0, (sum, item) => sum + item.quantity);
}
