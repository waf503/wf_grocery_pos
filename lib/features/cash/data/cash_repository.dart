import '../../../models/cash_session.dart';

/// Ya hay una sesión de caja abierta: solo puede haber una a la vez.
class CashSessionAlreadyOpenException implements Exception {
  @override
  String toString() => 'Ya hay una caja abierta.';
}

abstract class CashRepository {
  /// La sesión abierta (con sus movimientos), o `null` si la caja está cerrada.
  Stream<CashSession?> watchCurrent();

  /// Abre la caja con un fondo inicial (en centavos). Lanza
  /// [CashSessionAlreadyOpenException] si ya hay una abierta.
  Future<CashSession> open({required int openingCents});

  /// Ingreso o retiro manual de efectivo en la sesión indicada. Las ventas
  /// NO se registran aquí: las crea `SaleRepository.registerSale`.
  Future<void> addMovement({
    required String sessionId,
    required CashMovementType type,
    required int amountCents,
    required String note,
  });

  /// Cierra la sesión guardando el efectivo contado físicamente.
  Future<void> close({required String sessionId, required int countedCents});
}
