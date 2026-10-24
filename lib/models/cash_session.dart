import '../core/money.dart';

/// Tipos de movimiento de efectivo. `sale` (lo que ENTREGÓ el cliente),
/// `deposit` y `customerPayment` entran a la caja; `withdrawal`, `saleVoid`
/// (devolución por una venta anulada) y `change` (el vuelto de una venta)
/// salen. `deposit`/`withdrawal` son los manuales del cajero.
enum CashMovementType { sale, deposit, withdrawal, customerPayment, saleVoid, change }

extension CashMovementTypeLabel on CashMovementType {
  String get label {
    switch (this) {
      case CashMovementType.sale:
        return 'Venta';
      case CashMovementType.deposit:
        return 'Ingreso';
      case CashMovementType.withdrawal:
        return 'Retiro';
      case CashMovementType.customerPayment:
        return 'Abono de cliente';
      case CashMovementType.saleVoid:
        return 'Anulación de venta';
      case CashMovementType.change:
        return 'Vuelto';
    }
  }

  /// `true` si el movimiento saca efectivo de la caja.
  bool get isOutflow =>
      this == CashMovementType.withdrawal ||
      this == CashMovementType.saleVoid ||
      this == CashMovementType.change;
}

class CashMovement {
  CashMovement({
    required this.id,
    required this.type,
    required this.amountCents,
    required this.note,
    required this.time,
  });

  final String id;
  final CashMovementType type;
  final int amountCents;
  final String note;
  final DateTime time;

  double get amount => fromCents(amountCents);
}

/// Una sesión de caja (turno): del momento en que se abre con un fondo
/// inicial hasta que se cierra contando el efectivo. Solo los movimientos
/// de efectivo afectan el monto esperado.
class CashSession {
  CashSession({
    required this.id,
    required this.openingCents,
    required this.openedAt,
    required this.movements,
    this.closedAt,
    this.closingCountedCents,
  });

  final String id;
  final int openingCents;
  final DateTime openedAt;
  final List<CashMovement> movements;
  final DateTime? closedAt;
  final int? closingCountedCents;

  bool get isOpen => closedAt == null;

  int get salesCents => _sum(CashMovementType.sale);
  int get depositsCents => _sum(CashMovementType.deposit);
  int get withdrawalsCents => _sum(CashMovementType.withdrawal);
  int get customerPaymentsCents => _sum(CashMovementType.customerPayment);
  int get voidsCents => _sum(CashMovementType.saleVoid);

  /// Vueltos entregados a clientes. Las ventas en efectivo suman lo que el
  /// cliente ENTREGÓ y el vuelto resta, así que el neto es el total vendido.
  int get changeCents => _sum(CashMovementType.change);
  int get expectedCents =>
      openingCents +
      salesCents +
      depositsCents +
      customerPaymentsCents -
      withdrawalsCents -
      voidsCents -
      changeCents;
  int? get differenceCents =>
      closingCountedCents == null ? null : closingCountedCents! - expectedCents;

  double get openingAmount => fromCents(openingCents);
  double get salesTotal => fromCents(salesCents);
  double get depositsTotal => fromCents(depositsCents);
  double get withdrawalsTotal => fromCents(withdrawalsCents);
  double get customerPaymentsTotal => fromCents(customerPaymentsCents);
  double get voidsTotal => fromCents(voidsCents);
  double get changeTotal => fromCents(changeCents);
  double get expectedAmount => fromCents(expectedCents);
  double? get closingCountedAmount =>
      closingCountedCents == null ? null : fromCents(closingCountedCents!);
  double? get difference => differenceCents == null ? null : fromCents(differenceCents!);

  int _sum(CashMovementType type) =>
      movements.where((m) => m.type == type).fold(0, (sum, m) => sum + m.amountCents);
}
