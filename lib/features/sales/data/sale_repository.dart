import '../../../models/sale.dart';

/// Un renglón que se quiere vender: producto, cantidad y la foto de precio
/// y costo vigentes en este momento (en centavos).
///
/// Si [productId] es nulo es una VENTA GENÉRICA: algo que no está en el
/// inventario (nombre y precio escritos por el cajero). No toca existencias
/// y su costo es 0 (se desconoce).
class SaleLine {
  SaleLine({
    required this.productId,
    required this.productName,
    required this.quantity,
    required this.unitPriceCents,
    required this.unitCostCents,
    this.fixedSubtotalCents,
  });

  final String? productId;
  final String productName;
  final double quantity;
  final int unitPriceCents;
  final int unitCostCents;

  /// Subtotal ya calculado con los combos del producto (ej. 2 por $0.25). Si
  /// es nulo, es simplemente cantidad × precio.
  final int? fixedSubtotalCents;

  int get subtotalCents => fixedSubtotalCents ?? (quantity * unitPriceCents).round();

  bool get isGeneric => productId == null;
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

/// Una venta a crédito (fiado) necesita un cliente registrado.
class CreditRequiresCustomerException implements Exception {
  @override
  String toString() => 'Para vender a crédito selecciona un cliente.';
}

/// La venta que se quiere anular no existe.
class SaleNotFoundException implements Exception {
  @override
  String toString() => 'La venta no existe.';
}

/// La venta ya estaba anulada.
class SaleAlreadyVoidedException implements Exception {
  @override
  String toString() => 'La venta ya fue anulada.';
}

/// El cliente entregó menos de lo que cuesta la venta.
class InsufficientTenderException implements Exception {
  InsufficientTenderException(this.missingCents);

  final int missingCents;

  @override
  String toString() => 'El efectivo recibido no alcanza para pagar la venta.';
}

abstract class SaleRepository {
  /// Ventas desde [from] (incluida) hasta [to] (excluida; sin límite si es
  /// nulo), de la más reciente a la más antigua.
  Stream<List<Sale>> watchBetween(DateTime from, {DateTime? to});

  /// Todas las ventas de un turno de caja (incluidas las anuladas), de la
  /// más reciente a la más antigua.
  Stream<List<Sale>> watchBySession(String sessionId);

  /// Registra una venta COMPLETA en una sola transacción: encabezado,
  /// renglones, descuento de existencias y (si es en efectivo) el movimiento
  /// de caja. Si algo falla —por ejemplo no hay existencias— no se guarda
  /// nada. Las ventas a crédito también cargan el saldo del cliente. Lanza
  /// [InsufficientStockException], [ProductNotFoundException],
  /// [CashSessionClosedException] o [CreditRequiresCustomerException].
  ///
  /// En efectivo, [tenderedCents] es lo que ENTREGÓ el cliente (si es nulo se
  /// toma el total exacto). Entra a la caja completo y el vuelto sale como un
  /// movimiento aparte, así que el neto es el total. Si es menor al total lanza
  /// [InsufficientTenderException]; en otras formas de pago no se admite.
  Future<Sale> registerSale({
    required String sessionId,
    required List<SaleLine> lines,
    required PaymentMethod paymentMethod,
    String? customerId,
    String? customerName,
    int? tenderedCents,
    String? cashierName,
  });

  /// Anula una venta en una sola transacción: la marca como anulada con su
  /// [reason], devuelve las existencias, revierte el efectivo (un retiro en
  /// la caja abierta [cashSessionId]; obligatorio si la venta fue en
  /// efectivo) y, si fue fiado, revierte el cargo al cliente. Lanza
  /// [SaleNotFoundException], [SaleAlreadyVoidedException] o
  /// [CashSessionClosedException].
  Future<void> voidSale({
    required String saleId,
    required String reason,
    String? cashSessionId,
    String? voidedBy,
  });
}
