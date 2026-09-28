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
    required this.type,
    required this.amount,
    required this.note,
    required this.time,
  });

  final CashMovementType type;
  final double amount;
  final String note;
  final DateTime time;
}

class CashSession {
  CashSession({required this.openingAmount, required this.openedAt});

  final double openingAmount;
  final DateTime openedAt;
  final List<CashMovement> movements = [];
  DateTime? closedAt;
  double? closingCountedAmount;

  bool get isOpen => closedAt == null;

  double get salesTotal => _sum(CashMovementType.sale);
  double get depositsTotal => _sum(CashMovementType.deposit);
  double get withdrawalsTotal => _sum(CashMovementType.withdrawal);

  double get expectedAmount =>
      openingAmount + salesTotal + depositsTotal - withdrawalsTotal;

  double? get difference =>
      closingCountedAmount == null ? null : closingCountedAmount! - expectedAmount;

  double _sum(CashMovementType type) => movements
      .where((m) => m.type == type)
      .fold(0.0, (sum, m) => sum + m.amount);
}
