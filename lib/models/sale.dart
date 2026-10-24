import '../core/money.dart';

enum PaymentMethod { cash, card, credit }

extension PaymentMethodAvailability on PaymentMethod {
  /// El pago electrónico aún no está soportado: se muestra deshabilitado al
  /// cobrar, pero las ventas ya guardadas con ese método se siguen listando.
  bool get isAvailable => this != PaymentMethod.card;
}

/// Una venta anulada se conserva en el historial (con su motivo), pero ya
/// no cuenta en totales ni reportes.
enum SaleStatus { completed, voided }

extension PaymentMethodLabel on PaymentMethod {
  String get label {
    switch (this) {
      case PaymentMethod.cash:
        return 'Efectivo';
      case PaymentMethod.card:
        // Categoría de pago electrónico (tarjeta, transferencia, billeteras...).
        return 'Pago electrónico';
      case PaymentMethod.credit:
        return 'Fiado';
    }
  }
}

/// Un renglón de una venta ya registrada. Nombre, precio y costo son una
/// FOTO del momento de la venta: si luego cambian en el inventario (o el
/// producto se borra), el historial no se altera.
class SaleItem {
  SaleItem({
    this.productId,
    required this.productName,
    required this.quantity,
    required this.unitPriceCents,
    required this.unitCostCents,
    required this.subtotalCents,
  });

  final String? productId;
  final String productName;
  final double quantity;
  final int unitPriceCents;
  final int unitCostCents;
  final int subtotalCents;

  double get unitPrice => fromCents(unitPriceCents);
  double get subtotal => fromCents(subtotalCents);
}

class Sale {
  Sale({
    required this.id,
    required this.number,
    required this.date,
    required this.items,
    required this.totalCents,
    required this.paymentMethod,
    this.customerId,
    this.customerName,
    this.status = SaleStatus.completed,
    this.voidedAt,
    this.voidReason,
    this.tenderedCents,
    this.changeCents,
  });

  final String id;

  /// Folio consecutivo, el que se ve en el recibo.
  final int number;
  final DateTime date;
  final List<SaleItem> items;
  final int totalCents;
  final PaymentMethod paymentMethod;
  final String? customerId;
  final String? customerName;
  final SaleStatus status;
  final DateTime? voidedAt;
  final String? voidReason;

  /// Ventas en efectivo: lo que entregó el cliente y el vuelto devuelto.
  /// Nulos en otras formas de pago y en ventas antiguas.
  final int? tenderedCents;
  final int? changeCents;

  double? get tendered => tenderedCents == null ? null : fromCents(tenderedCents!);
  double? get change => changeCents == null ? null : fromCents(changeCents!);

  bool get isVoided => status == SaleStatus.voided;

  double get total => fromCents(totalCents);

  /// Folio con formato de recibo, ej. `V-000123`.
  String get receiptNumber => 'V-${number.toString().padLeft(6, '0')}';

  double get itemCount => items.fold(0.0, (sum, item) => sum + item.quantity);
}
