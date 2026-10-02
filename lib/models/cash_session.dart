import '../core/money.dart';

enum CashMovementType { sale, deposit, withdrawal }

extension CashMovementTypeLabel on CashMovementType {
  String get label {
    switch (this) {
      case CashMovementType.sale:
        return 'Venta';
      case CashMovementType.deposit:
        return 'Ingreso';
      case CashMovementType.withdrawal:
        return 'Retiro';
    }
  }
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
  int get expectedCents => openingCents + salesCents + depositsCents - withdrawalsCents;
  int? get differenceCents =>
      closingCountedCents == null ? null : closingCountedCents! - expectedCents;

  double get openingAmount => fromCents(openingCents);
  double get salesTotal => fromCents(salesCents);
  double get depositsTotal => fromCents(depositsCents);
  double get withdrawalsTotal => fromCents(withdrawalsCents);
  double get expectedAmount => fromCents(expectedCents);
  double? get closingCountedAmount =>
      closingCountedCents == null ? null : fromCents(closingCountedCents!);
  double? get difference => differenceCents == null ? null : fromCents(differenceCents!);

  int _sum(CashMovementType type) =>
      movements.where((m) => m.type == type).fold(0, (sum, m) => sum + m.amountCents);
}
