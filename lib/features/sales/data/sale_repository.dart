import '../../../models/sale.dart';

/// Un renglón que se quiere vender: producto, cantidad y la foto de precio
/// y costo vigentes en este momento (en centavos).
class SaleLine {
  SaleLine({
    required this.productId,
    required this.productName,
    required this.quantity,
    required this.unitPriceCents,
    required this.unitCostCents,
  });

  final String productId;
  final String productName;
  final double quantity;
  final int unitPriceCents;
  final int unitCostCents;

  int get subtotalCents => (quantity * unitPriceCents).round();
}

/// No hay existencias suficientes de un producto para completar la venta.
class InsufficientStockException implements Exception {
  InsufficientStockException(this.productName, {required this.available});

  final String productName;
  final double available;

  @override
  String toString() => 'Existencias insuficientes de $productName (hay $available).';
}

/// Un producto de la venta ya no existe en el inventario.
class ProductNotFoundException implements Exception {
  ProductNotFoundException(this.productName);

  final String productName;

  @override
  String toString() => 'El producto "$productName" ya no existe en el inventario.';
}

/// La sesión de caja indicada no existe o ya está cerrada.
class CashSessionClosedException implements Exception {
  @override
  String toString() => 'La caja está cerrada: ábrela antes de registrar una venta.';
}

abstract class SaleRepository {
  /// Ventas desde [from] en adelante, de la más reciente a la más antigua.
  Stream<List<Sale>> watchSince(DateTime from);

  /// Registra una venta COMPLETA en una sola transacción: encabezado,
  /// renglones, descuento de existencias y (si es en efectivo) el movimiento
  /// de caja. Si algo falla —por ejemplo no hay existencias— no se guarda
  /// nada. Lanza [InsufficientStockException], [ProductNotFoundException] o
  /// [CashSessionClosedException].
  Future<Sale> registerSale({
    required String sessionId,
    required List<SaleLine> lines,
    required PaymentMethod paymentMethod,
    String? customerId,
    String? customerName,
  });
}
