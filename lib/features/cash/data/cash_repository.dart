import '../../../models/cash_session.dart';

/// Ya hay una sesión de caja abierta: solo puede haber una a la vez.
class CashSessionAlreadyOpenException implements Exception {
  @override
  String toString() => 'Ya hay una caja abierta.';
}

/// Un retiro mayor al efectivo que hay en la caja.
class InsufficientCashException implements Exception {
  InsufficientCashException(this.availableCents);

  final int availableCents;

  @override
  String toString() => 'No hay suficiente efectivo en la caja para ese retiro.';
}

/// La sesión que se quiere cerrar no existe o ya estaba cerrada.
class CashSessionNotOpenException implements Exception {
  @override
  String toString() => 'La caja ya estaba cerrada.';
}

abstract class CashRepository {
  /// La sesión abierta (con sus movimientos), o `null` si la caja está cerrada.
  Stream<CashSession?> watchCurrent();

  /// Abre la caja con un fondo inicial (en centavos). Lanza
  /// [CashSessionAlreadyOpenException] si ya hay una abierta.
  Future<CashSession> open({required int openingCents});

  /// Ingreso o retiro manual de efectivo en la sesión indicada. Las ventas
  /// NO se registran aquí: las crea `SaleRepository.registerSale`. Un retiro
  /// no puede exceder el efectivo esperado (lanza
  /// [InsufficientCashException]).
  Future<void> addMovement({
    required String sessionId,
    required CashMovementType type,
    required int amountCents,
    required String note,
  });

  /// Cierra la sesión guardando el efectivo contado físicamente y devuelve
  /// la sesión ya cerrada (con su diferencia). Lanza
  /// [CashSessionNotOpenException] si ya estaba cerrada.
  Future<CashSession> close({required String sessionId, required int countedCents});

  /// Turnos ya cerrados con sus movimientos, del más reciente al más antiguo.
  Stream<List<CashSession>> watchClosed({int limit = 200});
}
